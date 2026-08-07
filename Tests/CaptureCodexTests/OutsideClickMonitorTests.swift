import AppKit
import XCTest
@testable import CaptureCodex

final class OutsideClickMonitorTests: XCTestCase {
    // MARK: - Pure policy (left / right / other are treated the same at decision layer)

    func testGeometryDismissesOnlyWhenPointerIsOutsideVisiblePanel() {
        let frame = CGRect(x: 100, y: 200, width: 620, height: 92)

        XCTAssertFalse(
            OutsideClickPolicy.shouldDismiss(
                isPanelVisible: true,
                panelFrame: frame,
                pointerLocation: CGPoint(x: 150, y: 220)
            ),
            "Inside click must not dismiss"
        )
        XCTAssertTrue(
            OutsideClickPolicy.shouldDismiss(
                isPanelVisible: true,
                panelFrame: frame,
                pointerLocation: CGPoint(x: 10, y: 10)
            ),
            "Outside click must dismiss"
        )
        XCTAssertFalse(
            OutsideClickPolicy.shouldDismiss(
                isPanelVisible: false,
                panelFrame: frame,
                pointerLocation: CGPoint(x: 10, y: 10)
            ),
            "Hidden panel must not dismiss again"
        )
    }

    func testLocalEventUsesWindowIdentityBeforeGeometry() {
        let frame = CGRect(x: 100, y: 200, width: 620, height: 92)
        // Pointer still inside frame, but event belongs to another window (settings/history).
        XCTAssertTrue(
            OutsideClickPolicy.shouldDismissLocalEvent(
                isPanelVisible: true,
                panelFrame: frame,
                pointerLocation: CGPoint(x: 150, y: 220),
                eventWindowIsPanel: false
            ),
            "Click on another Capture Codex window must dismiss even if geometry is ambiguous"
        )
        XCTAssertFalse(
            OutsideClickPolicy.shouldDismissLocalEvent(
                isPanelVisible: true,
                panelFrame: frame,
                pointerLocation: CGPoint(x: 150, y: 220),
                eventWindowIsPanel: true
            ),
            "Click on the panel window must not dismiss"
        )
        XCTAssertTrue(
            OutsideClickPolicy.shouldDismissLocalEvent(
                isPanelVisible: true,
                panelFrame: frame,
                pointerLocation: CGPoint(x: 10, y: 10),
                eventWindowIsPanel: nil
            ),
            "Window-less local event falls back to geometry"
        )
    }

    func testMouseDownMaskIncludesLeftRightAndOther() {
        let mask = OutsideClickPolicy.mouseDownEventTypes
        XCTAssertTrue(mask.contains(.leftMouseDown))
        XCTAssertTrue(mask.contains(.rightMouseDown))
        XCTAssertTrue(mask.contains(.otherMouseDown))
        XCTAssertFalse(mask.contains(.leftMouseUp))
    }

    // MARK: - Lifecycle state machine

    func testLifecycleInstallRemovesDuplicatesAndClearOnRemove() {
        var life = OutsideClickMonitorLifecycle()
        XCTAssertFalse(life.isActive)

        life.install()
        XCTAssertTrue(life.globalInstalled)
        XCTAssertTrue(life.localInstalled)
        XCTAssertTrue(life.resignActiveInstalled)
        XCTAssertEqual(life.installGeneration, 1)

        life.install()
        XCTAssertEqual(life.installGeneration, 2, "Re-show must reinstall without stacking generation only once per install")
        XCTAssertTrue(life.isActive)

        life.remove()
        XCTAssertFalse(life.isActive)
        XCTAssertFalse(life.globalInstalled)
        XCTAssertFalse(life.localInstalled)
        XCTAssertFalse(life.resignActiveInstalled)
        XCTAssertEqual(life.installGeneration, 2, "remove must not bump generation")
    }

    // MARK: - FloatingPanelController integration

    @MainActor
    func testPanelShowInstallsMonitorsHideRemovesAndReshowReinstalls() async throws {
        try requireAppKit()
        let model = AppModel()
        let controller = FloatingPanelController(model: model)

        XCTAssertFalse(controller.isOutsideClickMonitoringActive)

        controller.show(expanded: false)
        // show() re-arms monitors on the next main-queue turn after capture-like activation.
        await yieldMainQueue()
        XCTAssertTrue(
            controller.isOutsideClickMonitoringActive,
            "show must install outside-click monitoring"
        )
        let generationAfterShow = controller.outsideClickInstallGeneration
        XCTAssertGreaterThan(generationAfterShow, 0)

        controller.hide()
        XCTAssertFalse(
            controller.isOutsideClickMonitoringActive,
            "hide must tear down global/local/resign-active monitoring"
        )

        controller.show(expanded: true)
        await yieldMainQueue()
        XCTAssertTrue(controller.isOutsideClickMonitoringActive)
        XCTAssertGreaterThan(
            controller.outsideClickInstallGeneration,
            generationAfterShow,
            "re-show must reinstall monitors (no stale registration)"
        )

        controller.hide()
    }

    @MainActor
    func testCaptureSequenceHideThenCompactShowOutsideDismissesAndDisarms() async throws {
        try requireAppKit()
        let model = AppModel()
        let controller = FloatingPanelController(model: model)

        // Mirrors AppModel.capture(): hide → (interactive capture) → show(expanded: false)
        controller.hide()
        XCTAssertFalse(controller.isOutsideClickMonitoringActive)

        controller.show(expanded: false)
        await yieldMainQueue()
        XCTAssertTrue(controller.isOutsideClickMonitoringActive)
        let frame = try XCTUnwrap(controller.visibleFrame)
        XCTAssertLessThan(frame.height, 200, "post-capture panel is compact")

        let outside = CGPoint(x: frame.minX - 50, y: frame.minY - 50)
        XCTAssertTrue(
            controller.evaluateOutsideClickForTesting(at: outside, eventWindowIsPanel: nil)
        )
        XCTAssertNil(controller.visibleFrame)
        XCTAssertFalse(controller.isOutsideClickMonitoringActive)

        // Re-show (menu / history) must arm again without leftover monitors.
        controller.show(expanded: true)
        await yieldMainQueue()
        XCTAssertTrue(controller.isOutsideClickMonitoringActive)
        controller.hide()
        XCTAssertFalse(controller.isOutsideClickMonitoringActive)
    }

    @MainActor
    func testOutsidePointerEvaluationDismissesAndInsideKeepsPanel() async throws {
        try requireAppKit()
        let model = AppModel()
        let controller = FloatingPanelController(model: model)
        controller.show(expanded: false)

        let frame = try XCTUnwrap(controller.visibleFrame)
        let inside = CGPoint(x: frame.midX, y: frame.midY)
        let outside = CGPoint(x: frame.minX - 80, y: frame.minY - 80)

        XCTAssertFalse(
            controller.evaluateOutsideClickForTesting(
                at: inside,
                eventWindowIsPanel: true
            ),
            "Inside / panel-window click must not dismiss"
        )
        XCTAssertTrue(controller.isOutsideClickMonitoringActive)

        XCTAssertTrue(
            controller.evaluateOutsideClickForTesting(
                at: outside,
                eventWindowIsPanel: nil
            ),
            "Outside pointer must dismiss"
        )
        XCTAssertFalse(
            controller.isOutsideClickMonitoringActive,
            "Dismiss must remove monitors so they do not accumulate"
        )
        XCTAssertNil(controller.visibleFrame)
    }

    @MainActor
    func testLocalClickOnOtherWindowDismissesEvenIfPointerStillInPanelFrame() async throws {
        try requireAppKit()
        let model = AppModel()
        let controller = FloatingPanelController(model: model)
        controller.show(expanded: false)

        let frame = try XCTUnwrap(controller.visibleFrame)
        let insidePoint = CGPoint(x: frame.midX, y: frame.midY)

        // Regression: geometry-only local handling would keep the panel open.
        XCTAssertTrue(
            controller.evaluateOutsideClickForTesting(
                at: insidePoint,
                eventWindowIsPanel: false
            ),
            "Click targeting another app window must dismiss the question panel"
        )
        XCTAssertFalse(controller.isOutsideClickMonitoringActive)
    }

    @MainActor
    func testApplicationResignActiveDismissesVisiblePanelAndRemovesMonitors() async throws {
        try requireAppKit()
        let model = AppModel()
        let controller = FloatingPanelController(model: model)
        controller.show(expanded: false)
        XCTAssertTrue(controller.isOutsideClickMonitoringActive)
        XCTAssertNotNil(controller.visibleFrame)

        // Post-capture focus races: outside clicks may not arrive as global mouse
        // events, but clicking desktop/other apps resigns active. That path must dismiss.
        NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)

        // Allow main-queue observer + MainActor Task delivery.
        for _ in 0..<10 {
            if controller.visibleFrame == nil, !controller.isOutsideClickMonitoringActive {
                break
            }
            await yieldMainQueue()
        }

        XCTAssertNil(controller.visibleFrame, "Resign-active must hide the panel")
        XCTAssertFalse(
            controller.isOutsideClickMonitoringActive,
            "Resign-active hide must remove monitors"
        )
    }

    @MainActor
    func testControllerWiresLeftRightOtherMouseDownMonitors() async throws {
        try requireAppKit()
        let model = AppModel()
        let controller = FloatingPanelController(model: model)
        controller.show(expanded: false)

        let mask = controller.outsideClickEventMaskForTesting
        XCTAssertTrue(mask.contains(.leftMouseDown))
        XCTAssertTrue(mask.contains(.rightMouseDown))
        XCTAssertTrue(mask.contains(.otherMouseDown))

        controller.hide()
    }

    // MARK: - Helpers

    private func requireAppKit() throws {
        // Ensure NSApp exists for panel ordering in unit tests.
        _ = NSApplication.shared
        if NSApp.activationPolicy() == .prohibited {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    @MainActor
    private func yieldMainQueue() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
    }
}
