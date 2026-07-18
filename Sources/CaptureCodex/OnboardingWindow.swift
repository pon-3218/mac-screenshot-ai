import AppKit
import SwiftUI

enum OnboardingState {
    private static let completionKey = "onboarding.completed.v1"

    static var needsPresentation: Bool {
        !UserDefaults.standard.bool(forKey: completionKey)
    }

    static func markCompleted() {
        UserDefaults.standard.set(true, forKey: completionKey)
    }
}

@MainActor
final class OnboardingWindowController: NSWindowController {
    init(
        settings: AppSettings,
        onRequestPermissions: @escaping () -> Void,
        onFinish: @escaping () -> Void
    ) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 470),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Capture Codexへようこそ"
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.contentView = NSHostingView(
            rootView: CaptureOnboardingView(
                settings: settings,
                onRequestPermissions: onRequestPermissions,
                onFinish: onFinish
            )
        )
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct CaptureOnboardingView: View {
    @ObservedObject var settings: AppSettings
    let onRequestPermissions: () -> Void
    let onFinish: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack(alignment: .top, spacing: 18) {
                Image(systemName: "viewfinder")
                    .font(.system(size: 38, weight: .medium))
                    .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 6) {
                    Text("画面を切り取って、すぐに聞く")
                        .font(.system(size: 26, weight: .semibold))
                    Text("Capture Codexはメニューバーで待機します。")
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 20) {
                onboardingStep(number: "1", title: "アクセス権を許可", detail: "画面収録、アクセシビリティ、通知を使用します。")
                onboardingStep(number: "2", title: "⌘⇧4で範囲を選ぶ", detail: "調べたい場所をドラッグして切り取ります。")
                onboardingStep(number: "3", title: "質問して回答を受け取る", detail: "上部の入力欄から、その画面について聞けます。")
            }

            Toggle("Macへのログイン時に自動で起動", isOn: $settings.launchAtLogin)
                .toggleStyle(.switch)

            HStack {
                Button("アクセス権を設定", action: onRequestPermissions)
                Spacer()
                Button("使い始める", action: onFinish)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(32)
        .frame(width: 620, height: 470, alignment: .topLeading)
    }

    private func onboardingStep(number: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 18) {
            Text(number)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(width: 20, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 16, weight: .medium))
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
