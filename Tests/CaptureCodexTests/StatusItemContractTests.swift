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

    func testSparkleUpdaterIsConfiguredAndPackaged() throws {
        let app = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Sources/CaptureCodex/CaptureCodexApp.swift"),
            encoding: .utf8
        )
        let package = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Package.swift"),
            encoding: .utf8
        )
        let plist = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Info.plist"),
            encoding: .utf8
        )
        let buildScript = try String(
            contentsOf: repositoryRoot.appendingPathComponent("scripts/build-app.sh"),
            encoding: .utf8
        )

        XCTAssertTrue(package.contains("sparkle-project/Sparkle"))
        XCTAssertTrue(package.contains(".product(name: \"Sparkle\""))
        XCTAssertTrue(app.contains("import Sparkle"))
        XCTAssertTrue(app.contains("SPUStandardUpdaterController"))
        XCTAssertTrue(app.contains("supportsGentleScheduledUpdateReminders"))
        XCTAssertTrue(app.contains("アップデートを確認…"))
        XCTAssertTrue(plist.contains("SUFeedURL"))
        XCTAssertTrue(plist.contains("SUPublicEDKey"))
        XCTAssertTrue(plist.contains("SUEnableAutomaticChecks"))
        XCTAssertTrue(plist.contains("SUAutomaticallyUpdate"))
        XCTAssertTrue(buildScript.contains("Contents/Frameworks/Sparkle.framework"))
        XCTAssertTrue(buildScript.contains("XPCServices/Installer.xpc"))
        XCTAssertTrue(buildScript.contains("XPCServices/Downloader.xpc"))
        XCTAssertFalse(buildScript.contains("--deep \\\n+"))
    }

    func testReleasePublishesSignedSparkleAppcast() throws {
        let releaseScript = try String(
            contentsOf: repositoryRoot.appendingPathComponent("scripts/release.sh"),
            encoding: .utf8
        )
        let workflow = try String(
            contentsOf: repositoryRoot.appendingPathComponent(".github/workflows/release.yml"),
            encoding: .utf8
        )

        XCTAssertTrue(releaseScript.contains("SPARKLE_EDDSA_PRIVATE_KEY"))
        XCTAssertTrue(releaseScript.contains("generate_appcast"))
        XCTAssertTrue(releaseScript.contains("appcast.xml"))
        XCTAssertTrue(workflow.contains("secrets.SPARKLE_EDDSA_PRIVATE_KEY"))
    }
}
