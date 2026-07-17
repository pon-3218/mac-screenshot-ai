import AppKit
import SwiftUI

@MainActor
final class CompletionToastController {
    private let panel: NSPanel
    private let onOpen: () -> Void
    private var dismissWorkItem: DispatchWorkItem?
    private let size = NSSize(width: 360, height: 96)

    init(onOpen: @escaping () -> Void) {
        self.onOpen = onOpen
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
    }

    func show(answer: String, avoiding avoidFrame: NSRect? = nil) {
        dismissWorkItem?.cancel()
        panel.contentView = NSHostingView(
            rootView: CompletionToastView(
                answer: answer,
                onOpen: { [weak self] in
                    self?.hide()
                    self?.onOpen()
                }
            )
        )

        let screen = screenUnderPointer() ?? NSScreen.main ?? NSScreen.screens.first
        if let visible = screen?.visibleFrame {
            var frame = NSRect(
                x: visible.midX - size.width / 2,
                y: visible.maxY - size.height - 16,
                width: size.width,
                height: size.height
            )
            if let avoidFrame, frame.intersects(avoidFrame) {
                frame.origin.y = max(visible.minY + 16, avoidFrame.minY - size.height - 10)
            }
            panel.setFrameOrigin(frame.origin)
        }
        panel.orderFrontRegardless()

        let workItem = DispatchWorkItem { [weak self] in self?.hide() }
        dismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: workItem)
    }

    func hide() {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        panel.orderOut(nil)
    }

    private func screenUnderPointer() -> NSScreen? {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(location) })
    }
}

private struct CompletionToastView: View {
    let answer: String
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 14) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(.green)

                VStack(alignment: .leading, spacing: 5) {
                    Text("回答が完了しました")
                        .font(.system(size: 14, weight: .semibold))
                    Text(singleLineAnswer)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .frame(width: 360, height: 96)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("回答が完了しました。クリックして回答を表示")
    }

    private var singleLineAnswer: String {
        answer.replacingOccurrences(of: "\n", with: " ")
    }
}
