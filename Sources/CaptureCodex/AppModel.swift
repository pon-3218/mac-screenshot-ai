import AppKit
import ApplicationServices
import Foundation

struct ConversationMessage: Identifiable, Equatable {
    enum Role {
        case user
        case assistant
    }

    let id: UUID
    let role: Role
    var text: String

    init(id: UUID = UUID(), role: Role, text: String) {
        self.id = id
        self.role = role
        self.text = text
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var prompt = ""
    @Published var response = ""
    @Published var errorMessage: String?
    @Published var needsScreenCapturePermission = false
    @Published var image: NSImage?
    @Published var isCapturing = false
    @Published var isAsking = false
    @Published var statusText = "領域をキャプチャ"
    @Published var conversation: [ConversationMessage] = []

    weak var panelController: FloatingPanelController?
    weak var completionToastController: CompletionToastController?
    var onHotkeyAvailabilityChanged: ((Bool) -> Void)?

    private let hotkeyMonitor = GlobalHotkeyMonitor()
    private let captureService = CaptureService()
    private let codexClient = CodexAppServerClient()
    private let settings = AppSettings.shared
    private let historyStore = HistoryStore.shared
    private var lastCaptureURL: URL?
    private var askTask: Task<Void, Never>?

    init() {
        statusText = captureHint
        if let savedPrompt = UserDefaults.standard.string(forKey: DefaultsKey.lastPrompt),
           let savedResponse = UserDefaults.standard.string(forKey: DefaultsKey.lastResponse),
           !savedResponse.isEmpty {
            response = savedResponse
            conversation = [
                ConversationMessage(role: .user, text: savedPrompt),
                ConversationMessage(role: .assistant, text: savedResponse)
            ]
            statusText = "前回の回答"
        }
        hotkeyMonitor.onCapture = { [weak self] in
            Task { @MainActor in self?.capture() }
        }
        hotkeyMonitor.onShortcutRecorded = { [weak self] shortcut in
            Task { @MainActor in
                guard let self else { return }
                self.settings.shortcut = shortcut
                self.applyShortcut(shortcut)
            }
        }
    }

    func startHotkeyMonitoring(requestPermission: Bool) -> Bool {
        let available = hotkeyMonitor.start(
            shortcut: settings.shortcut,
            requestPermission: requestPermission
        )
        onHotkeyAvailabilityChanged?(available)
        if !available {
            statusText = "アクセシビリティ権限が必要です"
        } else if lastCaptureURL == nil {
            statusText = captureHint
        }
        return available
    }

    func stop() {
        askTask?.cancel()
        hotkeyMonitor.stop()
        if let lastCaptureURL {
            try? FileManager.default.removeItem(at: lastCaptureURL)
        }
    }

    func requestPermissions() {
        _ = hotkeyMonitor.requestAccessibilityPermission()
        _ = CGRequestScreenCaptureAccess()
    }

    func openScreenCaptureSettings() {
        SystemSettingsNavigator.openScreenCapture()
    }

    func applyShortcut(_ shortcut: GlobalShortcut) {
        hotkeyMonitor.updateShortcut(shortcut)
        if !isCapturing, !isAsking, lastCaptureURL == nil {
            statusText = captureHint
        }
    }

    func setShortcutRecording(_ isRecording: Bool) {
        hotkeyMonitor.setShortcutRecording(isRecording)
    }

    func capture() {
        if isCapturing { return }
        if isAsking {
            panelController?.show(expanded: true)
            return
        }
        askTask?.cancel()
        isCapturing = true
        errorMessage = nil
        needsScreenCapturePermission = false
        response = ""
        prompt = ""
        conversation = []
        panelController?.hide()

        Task {
            do {
                let url = try await captureService.captureInteractive(
                    playSound: settings.captureSoundEnabled
                )
                if let previousURL = lastCaptureURL, previousURL != url {
                    try? FileManager.default.removeItem(at: previousURL)
                }
                lastCaptureURL = url
                image = NSImage(contentsOf: url)
                statusText = "クリップボードにコピーしました"
                isCapturing = false
                panelController?.show(expanded: false)
            } catch CaptureService.CaptureError.cancelled {
                isCapturing = false
                statusText = captureHint
            } catch CaptureService.CaptureError.permissionRequired {
                isCapturing = false
                needsScreenCapturePermission = true
                errorMessage = CaptureService.CaptureError.permissionRequired.localizedDescription
                statusText = "画面収録の許可が必要です"
                panelController?.show(expanded: true)
            } catch {
                isCapturing = false
                needsScreenCapturePermission = false
                errorMessage = error.localizedDescription
                statusText = "キャプチャできませんでした"
                panelController?.show(expanded: true)
            }
        }
    }

    func showPanel() {
        guard lastCaptureURL != nil || !conversation.isEmpty || errorMessage != nil else {
            capture()
            return
        }
        panelController?.show(expanded: !conversation.isEmpty || errorMessage != nil)
    }

    func restoreLastAnswerAndShow() {
        guard let savedResponse = UserDefaults.standard.string(forKey: DefaultsKey.lastResponse),
              !savedResponse.isEmpty else {
            showPanel()
            return
        }
        let savedPrompt = UserDefaults.standard.string(forKey: DefaultsKey.lastPrompt) ?? ""
        prompt = ""
        response = savedResponse
        conversation = [
            ConversationMessage(role: .user, text: savedPrompt),
            ConversationMessage(role: .assistant, text: savedResponse)
        ]
        errorMessage = nil
        isAsking = false
        statusText = "前回の回答"
        panelController?.show(expanded: true)
    }

    func dismissPanel() {
        panelController?.hide()
    }

    func askCodex() {
        let question = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, let imageURL = lastCaptureURL, !isAsking else { return }

        let priorConversation = conversation
        let requestQuestion = contextualQuestion(
            newQuestion: question,
            priorConversation: priorConversation
        )
        let userMessage = ConversationMessage(role: .user, text: question)
        let assistantMessage = ConversationMessage(role: .assistant, text: "")
        conversation.append(userMessage)
        conversation.append(assistantMessage)
        prompt = ""
        isAsking = true
        response = ""
        errorMessage = nil
        statusText = "Codexが確認しています"
        panelController?.setExpanded(true)
        let modelID = settings.modelID
        let reasoningEffort = settings.reasoningEffort

        askTask = Task { [weak self] in
            guard let self else { return }
            do {
                let answer = try await codexClient.ask(
                    question: requestQuestion,
                    imageURL: imageURL,
                    modelID: modelID,
                    reasoningEffort: reasoningEffort
                ) { [weak self] partialAnswer in
                    DispatchQueue.main.async {
                        guard let self, self.isAsking else { return }
                        self.response = partialAnswer
                        self.updateConversationMessage(
                            id: assistantMessage.id,
                            text: partialAnswer
                        )
                    }
                }
                response = answer
                updateConversationMessage(id: assistantMessage.id, text: answer)
                saveLastAnswer(question: question, answer: answer)
                historyStore.add(
                    question: question,
                    answer: answer,
                    modelID: modelID,
                    reasoningEffort: reasoningEffort
                )
                isAsking = false
                statusText = "回答しました"
                completionToastController?.show(
                    answer: answer,
                    avoiding: panelController?.visibleFrame
                )
            } catch {
                conversation.removeAll {
                    $0.id == userMessage.id || $0.id == assistantMessage.id
                }
                isAsking = false
                errorMessage = error.localizedDescription
                statusText = "Codexに接続できませんでした"
            }
        }
    }

    func sendTestNotification() {
        let message = "完了通知はこのように表示されます。"
        completionToastController?.show(
            answer: message,
            avoiding: panelController?.visibleFrame
        )
    }

    private func saveLastAnswer(question: String, answer: String) {
        UserDefaults.standard.set(question, forKey: DefaultsKey.lastPrompt)
        UserDefaults.standard.set(answer, forKey: DefaultsKey.lastResponse)
    }

    private func updateConversationMessage(id: UUID, text: String) {
        guard let index = conversation.firstIndex(where: { $0.id == id }) else { return }
        conversation[index].text = text
    }

    private func contextualQuestion(
        newQuestion: String,
        priorConversation: [ConversationMessage]
    ) -> String {
        guard !priorConversation.isEmpty else { return newQuestion }

        let transcript = priorConversation.suffix(10).map { message in
            let label = message.role == .user ? "ユーザー" : "アシスタント"
            return "\(label): \(String(message.text.prefix(4_000)))"
        }.joined(separator: "\n\n")

        return """
        以下は、同じ画面キャプチャについての直前までの会話です。内容を引き継いで回答してください。

        \(transcript)

        追加の質問または指示: \(newQuestion)
        """
    }

    private var captureHint: String {
        "\(settings.shortcut.displayText)で領域をキャプチャ"
    }

    private enum DefaultsKey {
        static let lastPrompt = "lastPrompt"
        static let lastResponse = "lastResponse"
    }
}
