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
}
