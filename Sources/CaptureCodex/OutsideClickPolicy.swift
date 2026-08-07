import AppKit
import Foundation

/// Pure rules for dismissing the floating capture panel on outside clicks.
/// Kept free of NSEvent monitor side effects so unit tests can lock the contract.
enum OutsideClickPolicy {
    static let mouseDownEventTypes: NSEvent.EventTypeMask = [
        .leftMouseDown,
        .rightMouseDown,
        .otherMouseDown
    ]

    /// Geometry-only decision used for global mouse events (other apps / desktop).
    static func shouldDismiss(
        isPanelVisible: Bool,
        panelFrame: CGRect,
        pointerLocation: CGPoint
    ) -> Bool {
        guard isPanelVisible else { return false }
        return !panelFrame.contains(pointerLocation)
    }

    /// Local events (same app): prefer window identity, fall back to geometry.
    /// - eventWindowIsPanel == true: click landed in the panel → keep open
    /// - eventWindowIsPanel == false: click landed in another app window → dismiss
    /// - eventWindowIsPanel == nil: no window (rare) → geometry
    static func shouldDismissLocalEvent(
        isPanelVisible: Bool,
        panelFrame: CGRect,
        pointerLocation: CGPoint,
        eventWindowIsPanel: Bool?
    ) -> Bool {
        guard isPanelVisible else { return false }
        if let eventWindowIsPanel {
            return !eventWindowIsPanel
        }
        return !panelFrame.contains(pointerLocation)
    }
}

/// Tracks whether outside-click monitors are installed so tests can assert
/// show/hide/re-show lifecycle without depending on opaque NSEvent tokens.
struct OutsideClickMonitorLifecycle: Equatable {
    private(set) var globalInstalled = false
    private(set) var localInstalled = false
    private(set) var resignActiveInstalled = false
    private(set) var installGeneration = 0

    var isActive: Bool {
        globalInstalled || localInstalled || resignActiveInstalled
    }

    /// Install after removing any previous registration (no duplicate monitors).
    mutating func install(global: Bool = true, local: Bool = true, resignActive: Bool = true) {
        remove()
        globalInstalled = global
        localInstalled = local
        resignActiveInstalled = resignActive
        installGeneration += 1
    }

    mutating func remove() {
        globalInstalled = false
        localInstalled = false
        resignActiveInstalled = false
    }
}
