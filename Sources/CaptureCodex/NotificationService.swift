import Foundation
import UserNotifications

final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    var onOpen: (() -> Void)?

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                NSLog("Capture Codex notification authorization failed: %@", error.localizedDescription)
            } else {
                NSLog("Capture Codex notification authorization: %@", granted ? "granted" : "denied")
            }
        }
    }

    func notifyAnswerCompleted(answer: String) {
        notify(
            subtitle: "回答が完了しました",
            body: Self.notificationBody(from: answer),
            identifierPrefix: "capture-codex-answer"
        )
    }

    func notifyTest() {
        notify(
            subtitle: "テスト通知",
            body: "完了通知はこのように表示されます。",
            identifierPrefix: "capture-codex-test"
        )
    }

    private func notify(subtitle: String, body: String, identifierPrefix: String) {
        let content = UNMutableNotificationContent()
        content.title = "Capture Codex"
        content.subtitle = subtitle
        content.body = body
        content.sound = .default
        content.threadIdentifier = "capture-codex-answers"

        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized
                    || settings.authorizationStatus == .provisional else {
                NSLog(
                    "Capture Codex notification skipped: authorization status %ld",
                    settings.authorizationStatus.rawValue
                )
                return
            }

            let request = UNNotificationRequest(
                identifier: "\(identifierPrefix)-\(UUID().uuidString)",
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.5, repeats: false)
            )
            center.add(request) { error in
                if let error {
                    NSLog("Capture Codex notification failed: %@", error.localizedDescription)
                } else {
                    NSLog("Capture Codex notification scheduled: %@", request.identifier)
                }
            }
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        NSLog("Capture Codex presenting notification: %@", notification.request.identifier)
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        DispatchQueue.main.async { [weak self] in self?.onOpen?() }
        completionHandler()
    }

    private static func notificationBody(from answer: String) -> String {
        let singleLine = answer
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard singleLine.count > 180 else { return singleLine }
        return String(singleLine.prefix(180)) + "…"
    }
}
