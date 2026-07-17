import ApplicationServices
import CoreGraphics
import Foundation

final class GlobalHotkeyMonitor {
    var onCapture: (() -> Void)?
    var onShortcutRecorded: ((GlobalShortcut) -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var shortcut = GlobalShortcut.captureDefault
    private var isRecordingShortcut = false

    var isRunning: Bool { eventTap != nil }

    @discardableResult
    func start(shortcut: GlobalShortcut, requestPermission: Bool) -> Bool {
        self.shortcut = shortcut
        if isRunning { return true }
        if requestPermission {
            _ = requestAccessibilityPermission()
        }

        let eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: Self.eventCallback,
            userInfo: context
        ) else {
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        runLoopSource = source
        return true
    }

    func updateShortcut(_ shortcut: GlobalShortcut) {
        self.shortcut = shortcut
    }

    func setShortcutRecording(_ isRecording: Bool) {
        isRecordingShortcut = isRecording
    }

    func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        runLoopSource = nil
        eventTap = nil
    }

    @discardableResult
    func requestAccessibilityPermission() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    private static let eventCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let monitor = Unmanaged<GlobalHotkeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = monitor.eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        if monitor.isRecordingShortcut, type == .keyDown {
            if keyCode == 53 {
                return Unmanaged.passUnretained(event)
            }
            if event.getIntegerValueField(.keyboardEventAutorepeat) == 0,
               let recorded = GlobalShortcut(keyCode: keyCode, flags: flags) {
                monitor.isRecordingShortcut = false
                DispatchQueue.main.async { monitor.onShortcutRecorded?(recorded) }
                return nil
            }
            return Unmanaged.passUnretained(event)
        }

        let matches = monitor.shortcut.matches(keyCode: keyCode, flags: flags)

        guard matches else { return Unmanaged.passUnretained(event) }
        if type == .keyDown, event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
            DispatchQueue.main.async { monitor.onCapture?() }
        }
        return nil
    }
}
