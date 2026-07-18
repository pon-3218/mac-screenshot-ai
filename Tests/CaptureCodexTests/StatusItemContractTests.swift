import Foundation
import XCTest

final class StatusItemContractTests: XCTestCase {
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testStatusItemIsExplicitlyVisibleAndRestorable() throws {
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Sources/CaptureCodex/CaptureCodexApp.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("item.autosaveName = \"CaptureCodex.statusItem\""))
        XCTAssertTrue(source.contains("item.isVisible = true"))
    }

    func testReleaseChecksumsUsePortableFileNames() throws {
        let script = try String(
            contentsOf: repositoryRoot.appendingPathComponent("scripts/release.sh"),
            encoding: .utf8
        )

        XCTAssertTrue(script.contains("shasum -a 256 \"${archive_path:t}\""))
        XCTAssertTrue(script.contains("shasum -a 256 \"${stable_archive_path:t}\""))
    }

    func testLaunchAtLoginIsEnabledByDefaultAndConfigurable() throws {
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Sources/CaptureCodex/AppSettings.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("@Published var launchAtLogin"))
        XCTAssertTrue(source.contains("launchAtLogin = true"))
    }

    func testOnboardingIsFirstRunOnlyAndReopenableFromMenu() throws {
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Sources/CaptureCodex/CaptureCodexApp.swift"),
            encoding: .utf8
        )
        let onboarding = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Sources/CaptureCodex/OnboardingWindow.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("OnboardingState.needsPresentation"))
        XCTAssertTrue(source.contains("NSMenuItem(title: \"使い方…\""))
        XCTAssertTrue(onboarding.contains("アクセス権を設定"))
        XCTAssertTrue(onboarding.contains("⌘⇧4"))
    }

    func testCompletionUsesOnlyInAppNotificationAndReopenShowsAnswer() throws {
        let app = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Sources/CaptureCodex/CaptureCodexApp.swift"),
            encoding: .utf8
        )
        let model = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Sources/CaptureCodex/AppModel.swift"),
            encoding: .utf8
        )
        let settings = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Sources/CaptureCodex/SettingsWindow.swift"),
            encoding: .utf8
        )
        let onboarding = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Sources/CaptureCodex/OnboardingWindow.swift"),
            encoding: .utf8
        )
        let package = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Package.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(FileManager.default.fileExists(
            atPath: repositoryRoot.appendingPathComponent("Sources/CaptureCodex/NotificationService.swift").path
        ))
        XCTAssertFalse(model.contains("NotificationService"))
        XCTAssertFalse(package.contains("UserNotifications"))
        XCTAssertFalse(settings.contains("UserNotifications"))
        XCTAssertFalse(onboarding.contains("通知"))
        XCTAssertTrue(app.contains("else {\n            showLastAnswer()\n        }"))
    }
}
