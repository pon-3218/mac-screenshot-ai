import AppKit
import CoreGraphics
import Foundation

@MainActor
final class CaptureService {
    enum CaptureError: LocalizedError {
        case permissionRequired
        case launchFailed
        case cancelled
        case invalidImage
        case clipboardFailed

        var errorDescription: String? {
            switch self {
            case .permissionRequired:
                return "画面収録の許可が必要です。システム設定の「プライバシーとセキュリティ」からCapture Codexを許可してください。"
            case .launchFailed:
                return "macOSの画面キャプチャを起動できませんでした。"
            case .cancelled:
                return "キャプチャをキャンセルしました。"
            case .invalidImage:
                return "キャプチャ画像を読み取れませんでした。"
            case .clipboardFailed:
                return "画像をクリップボードへコピーできませんでした。"
            }
        }
    }

    func captureInteractive(playSound: Bool) async throws -> URL {
        if !CGPreflightScreenCaptureAccess(), !CGRequestScreenCaptureAccess() {
            throw CaptureError.permissionRequired
        }

        let destination = try makeDestinationURL()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = playSound
            ? ["-i", destination.path]
            : ["-i", "-x", destination.path]

        do {
            try process.run()
        } catch {
            throw CaptureError.launchFailed
        }

        let status = await withCheckedContinuation { continuation in
            process.terminationHandler = { process in
                continuation.resume(returning: process.terminationStatus)
            }
        }

        guard status == 0, FileManager.default.fileExists(atPath: destination.path) else {
            try? FileManager.default.removeItem(at: destination)
            throw CaptureError.cancelled
        }
        guard let image = NSImage(contentsOf: destination) else {
            throw CaptureError.invalidImage
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.writeObjects([image]) else {
            throw CaptureError.clipboardFailed
        }
        return destination
    }

    private func makeDestinationURL() throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptureCodex", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let safeTimestamp = formatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        return base.appendingPathComponent("capture-\(safeTimestamp).png")
    }
}
