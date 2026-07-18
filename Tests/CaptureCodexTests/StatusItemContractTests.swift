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
}
