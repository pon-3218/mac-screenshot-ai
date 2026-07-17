import AppKit

@MainActor
enum SystemSettingsNavigator {
    static func openScreenCapture() {
        openPrivacyPane(anchor: "Privacy_ScreenCapture")
    }

    static func openAccessibility() {
        openPrivacyPane(anchor: "Privacy_Accessibility")
    }

    static func openNotifications() {
        open(
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(Bundle.main.bundleIdentifier ?? "")"
        )
    }

    private static func openPrivacyPane(anchor: String) {
        open("x-apple.systempreferences:com.apple.preference.security?\(anchor)")
    }

    private static func open(_ urlString: String) {
        guard let url = URL(string: urlString), NSWorkspace.shared.open(url) else {
            NSWorkspace.shared.open(
                URL(fileURLWithPath: "/System/Applications/System Settings.app")
            )
            return
        }
    }
}
