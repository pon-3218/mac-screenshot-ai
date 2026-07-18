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
}
