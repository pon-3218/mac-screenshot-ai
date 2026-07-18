import AppKit
import ApplicationServices
import CoreGraphics
import SwiftUI
import UserNotifications

@MainActor
final class SettingsWindowController: NSWindowController {
    private let state: SettingsViewState

    init(
        settings: AppSettings,
        onRequestPermissions: @escaping () -> Void,
        onShortcutChanged: @escaping (GlobalShortcut) -> Void,
        onShortcutRecordingChanged: @escaping (Bool) -> Void,
        onTestNotification: @escaping () -> Void
    ) {
        state = SettingsViewState(onRequestPermissions: onRequestPermissions)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 520),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Capture Codex 設定"
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.contentView = NSHostingView(
            rootView: SettingsView(
                state: state,
                settings: settings,
                onShortcutChanged: onShortcutChanged,
                onShortcutRecordingChanged: onShortcutRecordingChanged,
                onTestNotification: onTestNotification
            )
        )
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        state.refresh()
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

@MainActor
private final class SettingsViewState: ObservableObject {
    @Published var screenCaptureAllowed = false
    @Published var accessibilityAllowed = false
    @Published var notificationAllowed: Bool?
    @Published var notificationDetails = ""

    private let onRequestPermissions: () -> Void

    init(onRequestPermissions: @escaping () -> Void) {
        self.onRequestPermissions = onRequestPermissions
    }

    func refresh() {
        screenCaptureAllowed = CGPreflightScreenCaptureAccess()
        accessibilityAllowed = AXIsProcessTrusted()
        notificationAllowed = nil
        notificationDetails = ""

        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            let authorized = settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
            let bannerEnabled = settings.alertSetting == .enabled
            let centerEnabled = settings.notificationCenterSetting == .enabled
            let soundEnabled = settings.soundSetting == .enabled
            let allowed = authorized && (bannerEnabled || centerEnabled)
            let details = [
                "バナー\(bannerEnabled ? "ON" : "OFF")",
                "通知センター\(centerEnabled ? "ON" : "OFF")",
                "サウンド\(soundEnabled ? "ON" : "OFF")"
            ].joined(separator: "・")
            DispatchQueue.main.async {
                self?.notificationAllowed = allowed
                self?.notificationDetails = authorized ? details : "通知が許可されていません"
            }
        }
    }

    func requestPermissions() {
        onRequestPermissions()
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.refresh()
            }
        }
    }

    func openScreenCaptureSettings() {
        SystemSettingsNavigator.openScreenCapture()
    }

    func openAccessibilitySettings() {
        SystemSettingsNavigator.openAccessibility()
    }

    func openNotificationSettings() {
        SystemSettingsNavigator.openNotifications()
    }
}

private struct SettingsView: View {
    @ObservedObject var state: SettingsViewState
    @ObservedObject var settings: AppSettings
    let onShortcutChanged: (GlobalShortcut) -> Void
    let onShortcutRecordingChanged: (Bool) -> Void
    let onTestNotification: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Capture Codex")
                    .font(.system(size: 22, weight: .semibold))
                Text("現在の応答設定とmacOSのアクセス権")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            settingsSection
            launchSection
            permissionsSection

            HStack {
                Button("アクセス権を確認", action: state.requestPermissions)
                    .buttonStyle(.borderedProminent)

                Button(action: state.refresh) {
                    Label("状態を更新", systemImage: "arrow.clockwise")
                }

                Button("テスト通知", action: onTestNotification)

                Spacer()

                Text(versionText)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(28)
        .frame(width: 520, height: 520, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: settings.modelID) {
            settings.normalizeReasoningEffort()
        }
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("応答とキャプチャ")
            settingsRow(label: "モデル") {
                Picker("", selection: $settings.modelID) {
                    ForEach(ResponseModelOption.all) { model in
                        Text(model.name).tag(model.id)
                    }
                }
                .labelsHidden()
                .frame(width: 210)
            }
            settingsRow(label: "推論レベル") {
                Picker("", selection: $settings.reasoningEffort) {
                    ForEach(settings.availableEfforts) { effort in
                        Text(effort.name).tag(effort.id)
                    }
                }
                .labelsHidden()
                .frame(width: 210)
            }
            settingsRow(label: "ショートカット") {
                ShortcutRecorderView(
                    shortcut: $settings.shortcut,
                    onChange: onShortcutChanged,
                    onRecordingChanged: onShortcutRecordingChanged
                )
                .frame(width: 210, height: 26)
            }
            settingsRow(label: "キャプチャ音") {
                Toggle("", isOn: $settings.captureSoundEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
        }
    }

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("アクセス権")
            permissionRow(
                label: "画面収録",
                allowed: state.screenCaptureAllowed,
                openSettings: state.openScreenCaptureSettings
            )
            permissionRow(
                label: "アクセシビリティ",
                allowed: state.accessibilityAllowed,
                openSettings: state.openAccessibilitySettings
            )
            permissionRow(
                label: "通知",
                allowed: state.notificationAllowed,
                details: state.notificationDetails,
                openSettings: state.openNotificationSettings
            )
        }
    }

    private var launchSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("起動")
            settingsRow(label: "ログイン時") {
                Toggle("自動で起動", isOn: $settings.launchAtLogin)
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.secondary)
    }

    private func settingsRow<Content: View>(
        label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 16) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 132, alignment: .leading)
            content()
            Spacer()
        }
        .font(.system(size: 14))
        .frame(height: 26)
    }

    private func permissionRow(
        label: String,
        allowed: Bool?,
        details: String? = nil,
        openSettings: (() -> Void)? = nil
    ) -> some View {
        HStack(spacing: 16) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 132, alignment: .leading)

            if let allowed {
                VStack(alignment: .leading, spacing: 2) {
                    Label(
                        allowed ? "許可済み" : "設定が必要",
                        systemImage: allowed ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
                    )
                    .foregroundStyle(allowed ? Color.green : Color.orange)
                    if let details, !details.isEmpty {
                        Text(details)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                HStack(spacing: 7) {
                    ProgressView().controlSize(.small)
                    Text("確認中")
                }
                .foregroundStyle(.secondary)
            }
            Spacer()
            if let openSettings {
                Button("設定を開く", action: openSettings)
                    .controlSize(.small)
            }
        }
        .font(.system(size: 14, weight: .medium))
        .frame(minHeight: 20)
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        return version.isEmpty ? "" : "バージョン \(version)"
    }
}

private struct ShortcutRecorderView: NSViewRepresentable {
    @Binding var shortcut: GlobalShortcut
    let onChange: (GlobalShortcut) -> Void
    let onRecordingChanged: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> ShortcutRecorderButton {
        let button = ShortcutRecorderButton()
        button.shortcut = shortcut
        button.onShortcut = context.coordinator.didRecord
        button.onRecordingChanged = onRecordingChanged
        return button
    }

    func updateNSView(_ button: ShortcutRecorderButton, context: Context) {
        context.coordinator.parent = self
        let shortcutChanged = button.shortcut != shortcut
        button.shortcut = shortcut
        button.onRecordingChanged = onRecordingChanged
        if shortcutChanged, button.isRecording {
            button.finishRecording()
        } else {
            button.updateTitle()
        }
    }

    final class Coordinator {
        var parent: ShortcutRecorderView

        init(parent: ShortcutRecorderView) {
            self.parent = parent
        }

        func didRecord(_ shortcut: GlobalShortcut) {
            parent.shortcut = shortcut
            parent.onChange(shortcut)
        }
    }
}

private final class ShortcutRecorderButton: NSButton {
    var shortcut = GlobalShortcut.captureDefault
    var onShortcut: ((GlobalShortcut) -> Void)?
    var onRecordingChanged: ((Bool) -> Void)?
    private(set) var isRecording = false

    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        bezelStyle = .rounded
        controlSize = .regular
        target = self
        action = #selector(beginRecording)
        setAccessibilityLabel("キャプチャのショートカット")
        updateTitle()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func beginRecording() {
        isRecording = true
        onRecordingChanged?(true)
        title = "キーを入力…"
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            window?.makeFirstResponder(nil)
            return
        }
        guard let recorded = GlobalShortcut(event: event) else {
            NSSound.beep()
            return
        }
        shortcut = recorded
        onShortcut?(recorded)
        window?.makeFirstResponder(nil)
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        updateTitle()
        onRecordingChanged?(false)
        return super.resignFirstResponder()
    }

    func updateTitle() {
        if !isRecording {
            title = shortcut.displayText
        }
    }

    func finishRecording() {
        window?.makeFirstResponder(nil)
    }
}
