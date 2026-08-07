import AppKit
import SwiftUI

final class CapturePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class FloatingPanelController: NSObject {
    private let panel: CapturePanel
    private let compactSize = NSSize(width: 620, height: 92)
    private let expandedSize = NSSize(width: 620, height: 440)
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var resignActiveObserver: NSObjectProtocol?
    private var lifecycle = OutsideClickMonitorLifecycle()

    var visibleFrame: NSRect? {
        panel.isVisible ? panel.frame : nil
    }

    /// Test/inspection: true while global, local, or resign-active monitoring is armed.
    var isOutsideClickMonitoringActive: Bool { lifecycle.isActive }

    /// Test/inspection: increments on each successful install (show / re-show).
    var outsideClickInstallGeneration: Int { lifecycle.installGeneration }

    /// Test/inspection: event mask used for mouse monitors.
    var outsideClickEventMaskForTesting: NSEvent.EventTypeMask {
        OutsideClickPolicy.mouseDownEventTypes
    }

    init(model: AppModel) {
        panel = CapturePanel(
            contentRect: NSRect(origin: .zero, size: compactSize),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init()

        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .utilityWindow
        panel.contentView = NSHostingView(rootView: CapturePanelView(model: model))
    }

    func show(expanded: Bool) {
        setExpanded(expanded, animated: false)
        NSApp.activate(ignoringOtherApps: true)
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
        installOutsideClickMonitors()
        // Re-arm on the next turn after capture/activation settles. install()
        // always removes first, so this never stacks duplicate monitors.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.panel.isVisible else { return }
            self.installOutsideClickMonitors()
        }
    }

    func hide() {
        panel.orderOut(nil)
        removeOutsideClickMonitors()
    }

    func setExpanded(_ expanded: Bool, animated: Bool = true) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let size = expanded ? expandedSize : compactSize
        let visible = screen.visibleFrame
        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.maxY - size.height - 12
        )
        let frame = NSRect(origin: origin, size: size)
        panel.setFrame(frame, display: true, animate: animated && panel.isVisible)
    }

    /// Synchronous evaluation used by monitors and unit tests.
    /// Returns true when the panel was dismissed.
    @discardableResult
    func evaluateOutsideClickForTesting(
        at pointerLocation: CGPoint,
        eventWindowIsPanel: Bool?
    ) -> Bool {
        handlePotentialOutsideClick(
            pointerLocation: pointerLocation,
            eventWindowIsPanel: eventWindowIsPanel
        )
    }

    private func installOutsideClickMonitors() {
        removeOutsideClickMonitors()
        let events = OutsideClickPolicy.mouseDownEventTypes

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] _ in
            // Capture location immediately so a later MainActor hop cannot
            // evaluate a moved pointer after the outside click.
            let location = NSEvent.mouseLocation
            Task { @MainActor in
                self?.handlePotentialOutsideClick(
                    pointerLocation: location,
                    eventWindowIsPanel: nil
                )
            }
        }

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
            guard let self else { return event }
            let location = NSEvent.mouseLocation
            let eventWindowIsPanel: Bool? = {
                guard let window = event.window else { return nil }
                return window === self.panel
            }()
            Task { @MainActor in
                self.handlePotentialOutsideClick(
                    pointerLocation: location,
                    eventWindowIsPanel: eventWindowIsPanel
                )
            }
            return event
        }

        resignActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Desktop / other-app clicks resign active. This path still works when
            // global mouse monitors miss events after interactive capture.
            Task { @MainActor in
                self?.dismissIfVisibleFromOutsideInteraction()
            }
        }

        lifecycle.install(
            global: globalMouseMonitor != nil,
            local: localMouseMonitor != nil,
            resignActive: resignActiveObserver != nil
        )
    }

    private func removeOutsideClickMonitors() {
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
        }
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
        }
        if let resignActiveObserver {
            NotificationCenter.default.removeObserver(resignActiveObserver)
        }
        globalMouseMonitor = nil
        localMouseMonitor = nil
        resignActiveObserver = nil
        lifecycle.remove()
    }

    @discardableResult
    private func handlePotentialOutsideClick(
        pointerLocation: CGPoint,
        eventWindowIsPanel: Bool?
    ) -> Bool {
        guard panel.isVisible else {
            removeOutsideClickMonitors()
            return false
        }

        let shouldDismiss: Bool
        if eventWindowIsPanel != nil {
            shouldDismiss = OutsideClickPolicy.shouldDismissLocalEvent(
                isPanelVisible: true,
                panelFrame: panel.frame,
                pointerLocation: pointerLocation,
                eventWindowIsPanel: eventWindowIsPanel
            )
        } else {
            shouldDismiss = OutsideClickPolicy.shouldDismiss(
                isPanelVisible: true,
                panelFrame: panel.frame,
                pointerLocation: pointerLocation
            )
        }

        if shouldDismiss {
            hide()
            return true
        }
        return false
    }

    private func dismissIfVisibleFromOutsideInteraction() {
        guard panel.isVisible else {
            removeOutsideClickMonitors()
            return
        }
        hide()
    }
}

private struct CapturePanelView: View {
    @ObservedObject var model: AppModel
    @FocusState private var promptFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Group {
                    if let image = model.image {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Image(systemName: "viewfinder")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 58, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 7) {
                    Text(model.statusText)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)

                    if model.conversation.isEmpty {
                        promptComposer(placeholder: "キャプチャについて質問または指示")
                    }
                }

                Button(action: model.dismissPanel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .frame(height: 92)

            if model.isAsking || !model.conversation.isEmpty || model.errorMessage != nil {
                Divider().opacity(0.55)

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            ForEach(model.conversation) { message in
                                ConversationMessageView(
                                    message: message,
                                    isWaiting: model.isAsking
                                        && message.id == model.conversation.last?.id
                                )
                                .id(message.id)
                            }

                            if let error = model.errorMessage {
                                HStack(alignment: .firstTextBaseline, spacing: 12) {
                                    Label(error, systemImage: "exclamationmark.circle")
                                        .font(.system(size: 13))
                                        .foregroundStyle(.red)
                                        .textSelection(.enabled)

                                    if model.needsScreenCapturePermission {
                                        Button("設定を開く", action: model.openScreenCaptureSettings)
                                            .buttonStyle(.borderedProminent)
                                            .controlSize(.small)
                                    }
                                }
                            }
                        }
                        .padding(18)
                    }
                    .frame(maxHeight: .infinity)
                    .onChange(of: model.conversation) {
                        if let lastID = model.conversation.last?.id {
                            proxy.scrollTo(lastID, anchor: .bottom)
                        }
                    }
                }

                if !model.conversation.isEmpty {
                    Divider().opacity(0.55)

                    promptComposer(
                        placeholder: model.isAsking
                            ? "回答を待っています"
                            : "追加で質問または指示"
                    )
                    .padding(.horizontal, 18)
                    .frame(height: 64)
                }
            }
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .padding(1)
        .onAppear { promptFocused = model.image != nil }
        .onReceive(model.$image) { image in
            if image != nil { promptFocused = true }
        }
        .onReceive(model.$isAsking) { isAsking in
            if !isAsking, model.image != nil { promptFocused = true }
        }
    }

    private func promptComposer(placeholder: String) -> some View {
        HStack(spacing: 8) {
            TextField(placeholder, text: $model.prompt)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused($promptFocused)
                .onSubmit(model.askCodex)
                .disabled(model.image == nil || model.isAsking)

            if model.isAsking {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 28, height: 28)
            } else {
                Button(action: model.askCodex) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.circle)
                .disabled(
                    model.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || model.image == nil
                )
            }
        }
    }
}

private struct ConversationMessageView: View {
    let message: ConversationMessage
    let isWaiting: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(message.role == .user ? "質問・指示" : "回答")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            if message.text.isEmpty, isWaiting {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("画像を確認しています…")
                }
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            } else {
                Text(message.text)
                    .font(.system(size: 14))
                    .fontWeight(message.role == .user ? .medium : .regular)
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
