import AppKit
import CoreGraphics
import Foundation

struct ResponseModelOption: Identifiable, Hashable {
    let id: String
    let name: String
    let supportsMaximumEffort: Bool

    static let all: [ResponseModelOption] = [
        .init(id: "gpt-5.6-luna", name: "GPT-5.6 Luna", supportsMaximumEffort: true),
        .init(id: "gpt-5.6-terra", name: "GPT-5.6 Terra", supportsMaximumEffort: true),
        .init(id: "gpt-5.6-sol", name: "GPT-5.6 Sol", supportsMaximumEffort: true),
        .init(id: "gpt-5.5", name: "GPT-5.5", supportsMaximumEffort: false),
        .init(id: "gpt-5.4-mini", name: "GPT-5.4 Mini", supportsMaximumEffort: false),
        .init(id: "gpt-5.4", name: "GPT-5.4", supportsMaximumEffort: false)
    ]
}

struct ReasoningEffortOption: Identifiable, Hashable {
    let id: String
    let name: String

    static let standard: [ReasoningEffortOption] = [
        .init(id: "low", name: "Low"),
        .init(id: "medium", name: "Medium"),
        .init(id: "high", name: "High"),
        .init(id: "xhigh", name: "Extra High")
    ]
    static let maximum = ReasoningEffortOption(id: "max", name: "Maximum")
}

struct GlobalShortcut: Codable, Equatable {
    var keyCode: Int64
    var command: Bool
    var shift: Bool
    var option: Bool
    var control: Bool

    static let captureDefault = GlobalShortcut(
        keyCode: 21,
        command: true,
        shift: true,
        option: false,
        control: false
    )

    init(
        keyCode: Int64,
        command: Bool,
        shift: Bool,
        option: Bool,
        control: Bool
    ) {
        self.keyCode = keyCode
        self.command = command
        self.shift = shift
        self.option = option
        self.control = control
    }

    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let hasModifier = flags.contains(.command)
            || flags.contains(.shift)
            || flags.contains(.option)
            || flags.contains(.control)
        guard hasModifier else { return nil }

        self.init(
            keyCode: Int64(event.keyCode),
            command: flags.contains(.command),
            shift: flags.contains(.shift),
            option: flags.contains(.option),
            control: flags.contains(.control)
        )
    }

    init?(keyCode: Int64, flags: CGEventFlags) {
        let hasModifier = flags.contains(.maskCommand)
            || flags.contains(.maskShift)
            || flags.contains(.maskAlternate)
            || flags.contains(.maskControl)
        guard hasModifier else { return nil }

        self.init(
            keyCode: keyCode,
            command: flags.contains(.maskCommand),
            shift: flags.contains(.maskShift),
            option: flags.contains(.maskAlternate),
            control: flags.contains(.maskControl)
        )
    }

    func matches(keyCode: Int64, flags: CGEventFlags) -> Bool {
        guard self.keyCode == keyCode else { return false }
        return command == flags.contains(.maskCommand)
            && shift == flags.contains(.maskShift)
            && option == flags.contains(.maskAlternate)
            && control == flags.contains(.maskControl)
    }

    var displayText: String {
        var result = ""
        if control { result += "⌃" }
        if option { result += "⌥" }
        if shift { result += "⇧" }
        if command { result += "⌘" }
        return result + Self.keyName(for: keyCode)
    }

    private static func keyName(for keyCode: Int64) -> String {
        let names: [Int64: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y",
            17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=",
            25: "9", 26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U",
            33: "[", 34: "I", 35: "P", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";",
            42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".", 49: "Space",
            36: "Return", 48: "Tab", 51: "Delete", 53: "Esc", 123: "←", 124: "→",
            125: "↓", 126: "↑", 122: "F1", 120: "F2", 99: "F3", 118: "F4",
            96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10",
            103: "F11", 111: "F12"
        ]
        return names[keyCode] ?? "Key \(keyCode)"
    }
}

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var modelID: String {
        didSet { defaults.set(modelID, forKey: Key.modelID) }
    }
    @Published var reasoningEffort: String {
        didSet { defaults.set(reasoningEffort, forKey: Key.reasoningEffort) }
    }
    @Published var shortcut: GlobalShortcut {
        didSet {
            if let data = try? JSONEncoder().encode(shortcut) {
                defaults.set(data, forKey: Key.shortcut)
            }
        }
    }
    @Published var captureSoundEnabled: Bool {
        didSet { defaults.set(captureSoundEnabled, forKey: Key.captureSoundEnabled) }
    }
    @Published var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: Key.launchAtLogin)
            LoginItem.setEnabled(launchAtLogin)
        }
    }

    private let defaults: UserDefaults

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let savedModel = defaults.string(forKey: Key.modelID) ?? "gpt-5.6-luna"
        modelID = ResponseModelOption.all.contains(where: { $0.id == savedModel })
            ? savedModel
            : "gpt-5.6-luna"

        reasoningEffort = defaults.string(forKey: Key.reasoningEffort) ?? "low"

        if let data = defaults.data(forKey: Key.shortcut),
           let savedShortcut = try? JSONDecoder().decode(GlobalShortcut.self, from: data) {
            shortcut = savedShortcut
        } else {
            shortcut = .captureDefault
        }

        if defaults.object(forKey: Key.captureSoundEnabled) == nil {
            captureSoundEnabled = true
        } else {
            captureSoundEnabled = defaults.bool(forKey: Key.captureSoundEnabled)
        }
        if defaults.object(forKey: Key.launchAtLogin) == nil {
            launchAtLogin = true
        } else {
            launchAtLogin = defaults.bool(forKey: Key.launchAtLogin)
        }
        normalizeReasoningEffort()
    }

    var selectedModel: ResponseModelOption {
        ResponseModelOption.all.first(where: { $0.id == modelID }) ?? ResponseModelOption.all[0]
    }

    var availableEfforts: [ReasoningEffortOption] {
        selectedModel.supportsMaximumEffort
            ? ReasoningEffortOption.standard + [.maximum]
            : ReasoningEffortOption.standard
    }

    func normalizeReasoningEffort() {
        if !availableEfforts.contains(where: { $0.id == reasoningEffort }) {
            reasoningEffort = "low"
        }
    }

    private enum Key {
        static let modelID = "settings.modelID"
        static let reasoningEffort = "settings.reasoningEffort"
        static let shortcut = "settings.shortcut"
        static let captureSoundEnabled = "settings.captureSoundEnabled"
        static let launchAtLogin = "settings.launchAtLogin"
    }
}
