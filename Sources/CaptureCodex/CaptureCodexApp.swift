import AppKit
import Sparkle

@main
enum CaptureCodexMain {
    static func main() {
        LegacyPreferencesMigrator.migrateIfNeeded()
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, SPUStandardUserDriverDelegate {
    private let model = AppModel()
    private var panelController: FloatingPanelController?
    private var settingsWindowController: SettingsWindowController?
    private var historyWindowController: HistoryWindowController?
    private var onboardingWindowController: OnboardingWindowController?
    private var completionToastController: CompletionToastController?
    private var statusItem: NSStatusItem?
    private var permissionRetryTimer: Timer?
    private var updaterController: SPUStandardUpdaterController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: self
        )
        if let icon = bundledAppIcon() {
            NSApp.applicationIconImage = icon
        }
        let panelController = FloatingPanelController(model: model)
        self.panelController = panelController
        model.panelController = panelController
        let completionToastController = CompletionToastController { [weak self] in
            self?.model.restoreLastAnswerAndShow()
        }
        self.completionToastController = completionToastController
        model.completionToastController = completionToastController
        model.onHotkeyAvailabilityChanged = { [weak self] available in
            self?.updateStatusItem(available: available)
        }

        let isOutsideClickProbe = ProcessInfo.processInfo.arguments.contains("--probe-outside-click")
        let shouldShowOnboarding = !isOutsideClickProbe
            && (OnboardingState.needsPresentation
                || ProcessInfo.processInfo.arguments.contains("--open-onboarding"))
        LoginItem.setEnabled(AppSettings.shared.launchAtLogin)
        configureStatusItem()
        beginHotkeyMonitoring(requestPermission: !shouldShowOnboarding && !isOutsideClickProbe)
        if shouldShowOnboarding {
            showOnboarding()
        }
        // CAPTURE-004 GUI probe: same FloatingPanelController.show(expanded: false)
        // path used immediately after a successful interactive capture.
        if isOutsideClickProbe {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.model.statusText = "クリップボードにコピーしました"
                self?.panelController?.show(expanded: false)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        permissionRetryTimer?.invalidate()
        model.stop()
    }

    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = "CaptureCodex.statusItem"
        item.isVisible = true
        item.button?.image = menuBarIcon(available: true)
        item.button?.imageScaling = .scaleProportionallyDown
        item.button?.toolTip = "Capture Codex"

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "領域をキャプチャ", action: #selector(captureNow), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "現在の画面を表示", action: #selector(showCurrentPanel), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "最後の回答を表示", action: #selector(showLastAnswer), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "履歴…", action: #selector(showHistory), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "使い方…", action: #selector(showOnboarding), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "設定…", action: #selector(showSettings), keyEquivalent: ","))
        let updates = NSMenuItem(
            title: "アップデートを確認…",
            action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
            keyEquivalent: ""
        )
        updates.target = updaterController
        updates.isEnabled = updaterController.updater.canCheckForUpdates
        menu.addItem(updates)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Capture Codexを終了", action: #selector(quit), keyEquivalent: "q"))
        menu.items.filter { $0 !== updates }.forEach { $0.target = self }
        item.menu = menu
        statusItem = item

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            self?.statusItem?.isVisible = true
        }
    }

    private func beginHotkeyMonitoring(requestPermission: Bool = true) {
        if model.startHotkeyMonitoring(requestPermission: requestPermission) {
            permissionRetryTimer?.invalidate()
            permissionRetryTimer = nil
            return
        }

        permissionRetryTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self else { return }
                if self.model.startHotkeyMonitoring(requestPermission: false) {
                    timer.invalidate()
                    self.permissionRetryTimer = nil
                }
            }
        }
    }

    private func updateStatusItem(available: Bool) {
        statusItem?.isVisible = true
        statusItem?.button?.image = menuBarIcon(available: available)
        statusItem?.button?.toolTip = available ? "Capture Codex" : "Capture Codex：アクセシビリティ権限が必要"
    }

    private func menuBarIcon(available: Bool) -> NSImage? {
        let symbolName = available ? "viewfinder" : "viewfinder.trianglebadge.exclamationmark"
        let description = available ? "Capture Codex" : "アクセス権が必要"
        guard let icon = NSImage(systemSymbolName: symbolName, accessibilityDescription: description) else {
            return nil
        }
        let configuration = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        let menuIcon = icon.withSymbolConfiguration(configuration) ?? icon
        menuIcon.isTemplate = true
        return menuIcon
    }

    private func bundledAppIcon() -> NSImage? {
        guard let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns") else {
            return NSImage(systemSymbolName: "viewfinder", accessibilityDescription: "Capture Codex")
        }
        return NSImage(contentsOf: url)
    }

    @objc private func captureNow() {
        model.capture()
    }

    @objc private func showCurrentPanel() {
        model.showPanel()
    }

    @objc private func showLastAnswer() {
        model.restoreLastAnswerAndShow()
    }

    @objc private func showHistory() {
        if historyWindowController == nil {
            historyWindowController = HistoryWindowController(store: .shared)
        }
        historyWindowController?.show()
    }

    @objc private func showOnboarding() {
        if onboardingWindowController == nil {
            onboardingWindowController = OnboardingWindowController(
                settings: .shared,
                onRequestPermissions: { [weak self] in
                    guard let self else { return }
                    self.model.requestPermissions()
                    self.beginHotkeyMonitoring()
                },
                onFinish: { [weak self] in
                    OnboardingState.markCompleted()
                    self?.onboardingWindowController?.close()
                    self?.beginHotkeyMonitoring()
                }
            )
        }
        onboardingWindowController?.show()
    }

    @objc private func showSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(
                settings: .shared,
                onRequestPermissions: { [weak self] in
                    self?.model.requestPermissions()
                    self?.beginHotkeyMonitoring()
                },
                onShortcutChanged: { [weak self] shortcut in
                    self?.model.applyShortcut(shortcut)
                },
                onShortcutRecordingChanged: { [weak self] isRecording in
                    self?.model.setShortcutRecording(isRecording)
                },
                onTestNotification: { [weak self] in
                    self?.model.sendTestNotification()
                }
            )
        }
        settingsWindowController?.show()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if OnboardingState.needsPresentation {
            showOnboarding()
        } else {
            showLastAnswer()
        }
        return true
    }
}

private enum LegacyPreferencesMigrator {
    private static let migrationKey = "migration.jp.local.CaptureCodex.v2"
    private static let legacyBundleID = "jp.local.CaptureCodex"
    private static let keys = [
        "settings.modelID",
        "settings.reasoningEffort",
        "settings.shortcut",
        "settings.captureSoundEnabled",
        "lastPrompt",
        "lastResponse"
    ]

    static func migrateIfNeeded() {
        let current = UserDefaults.standard
        guard !current.bool(forKey: migrationKey),
              let legacy = UserDefaults(suiteName: legacyBundleID) else { return }

        for key in keys where current.object(forKey: key) == nil {
            if let value = legacy.object(forKey: key) {
                current.set(value, forKey: key)
            }
        }
        current.set(true, forKey: migrationKey)
    }
}
