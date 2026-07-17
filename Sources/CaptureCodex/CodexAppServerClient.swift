import Foundation
import Darwin

final class CodexAppServerClient: @unchecked Sendable {
    enum ClientError: LocalizedError {
        case codexNotFound
        case launchFailed(String)
        case protocolFailure(String)
        case connectionClosed(String)
        case emptyResponse
        case timedOut

        var errorDescription: String? {
            switch self {
            case .codexNotFound:
                return "Codex CLIが見つかりません。Codexをインストールし、ログインしてください。"
            case .launchFailed(let detail):
                return detail.isEmpty ? "Codex App Serverを起動できませんでした。" : "Codex App Serverを起動できませんでした。\n\(detail)"
            case .protocolFailure(let detail):
                return "Codexから回答を取得できませんでした。\n\(detail)"
            case .connectionClosed(let detail):
                return detail.isEmpty ? "Codex App Serverとの接続が終了しました。" : detail
            case .emptyResponse:
                return "Codexから回答本文が返りませんでした。"
            case .timedOut:
                return "Codexの回答が1分以内に完了しませんでした。"
            }
        }
    }

    func ask(
        question: String,
        imageURL: URL,
        modelID: String = "gpt-5.6-luna",
        reasoningEffort: String = "low",
        onPartialAnswer: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let runner = CodexAppServerRunner(
                        question: question,
                        imageURL: imageURL,
                        modelID: modelID,
                        reasoningEffort: reasoningEffort,
                        onPartialAnswer: onPartialAnswer
                    )
                    continuation.resume(returning: try runner.run())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

private final class CodexAppServerRunner {
    private let question: String
    private let imageURL: URL
    private let modelID: String
    private let reasoningEffort: String
    private let onPartialAnswer: @Sendable (String) -> Void
    private let process = Process()
    private let inputPipe = Pipe()
    private let outputPipe = Pipe()
    private let processLock = NSLock()
    private var outputBuffer = Data()
    private var answerChunks: [String] = []
    private var lastPartialPublish = Date.distantPast

    init(
        question: String,
        imageURL: URL,
        modelID: String,
        reasoningEffort: String,
        onPartialAnswer: @escaping @Sendable (String) -> Void
    ) {
        self.question = question
        self.imageURL = imageURL
        self.modelID = modelID
        self.reasoningEffort = reasoningEffort
        self.onPartialAnswer = onPartialAnswer
    }

    func run() throws -> String {
        guard let executable = Self.codexExecutableURL() else {
            throw CodexAppServerClient.ClientError.codexNotFound
        }

        process.executableURL = executable
        process.arguments = ["app-server", "--stdio"]
        process.standardInput = inputPipe.fileHandleForReading
        process.standardOutput = outputPipe.fileHandleForWriting
        process.standardError = FileHandle.nullDevice
        process.environment = Self.processEnvironment()

        do {
            try process.run()
            try inputPipe.fileHandleForReading.close()
            try outputPipe.fileHandleForWriting.close()
        } catch {
            throw CodexAppServerClient.ClientError.launchFailed(error.localizedDescription)
        }

        let timeoutDate = Date().addingTimeInterval(60)
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + 60)
        timer.setEventHandler { [weak self] in
            self?.terminateProcessIfNeeded()
        }
        timer.resume()

        defer {
            timer.cancel()
            try? inputPipe.fileHandleForWriting.close()
            terminateProcessIfNeeded()
        }

        try send([
            "method": "initialize",
            "id": 0,
            "params": [
                "clientInfo": [
                    "name": "capture_codex",
                    "title": "Capture Codex",
                    "version": "0.1.0"
                ]
            ]
        ])

        var threadID: String?
        while let line = readLine() {
            guard let message = Self.message(from: line) else { continue }

            if let error = message["error"] as? [String: Any] {
                let detail = error["message"] as? String ?? "不明なプロトコルエラー"
                throw CodexAppServerClient.ClientError.protocolFailure(detail)
            }

            let id = (message["id"] as? NSNumber)?.intValue
            if id == 0 {
                try send(["method": "initialized", "params": [:]])
                try send([
                    "method": "thread/start",
                    "id": 1,
                    "params": [
                        "model": modelID,
                        "cwd": imageURL.deletingLastPathComponent().path,
                        "approvalPolicy": "never",
                        "sandbox": "read-only",
                        "ephemeral": true,
                        "baseInstructions": "あなたは画面キャプチャ専用の画像回答アシスタントです。添付画像とユーザーの質問だけを確認し、日本語で簡潔に直接回答してください。ツール、コマンド、ファイル操作、Web検索は使用しません。画像で確認できる事実と推測を分けてください。"
                    ]
                ])
            } else if id == 1,
                      let result = message["result"] as? [String: Any],
                      let thread = result["thread"] as? [String: Any],
                      let value = thread["id"] as? String {
                threadID = value
                try send([
                    "method": "turn/start",
                    "id": 2,
                    "params": [
                        "threadId": value,
                        "approvalPolicy": "never",
                        "sandboxPolicy": ["type": "readOnly", "networkAccess": false],
                        "effort": reasoningEffort,
                        "summary": "none",
                        "input": [
                            ["type": "text", "text": question],
                            ["type": "localImage", "path": imageURL.path]
                        ]
                    ]
                ])
            }

            if message["method"] as? String == "item/agentMessage/delta",
               let params = message["params"] as? [String: Any],
               let delta = params["delta"] as? String {
                answerChunks.append(delta)
                publishPartialAnswerIfNeeded()
            }

            if message["method"] as? String == "turn/completed", threadID != nil {
                var completedAnswer = answerChunks.joined()
                if completedAnswer.isEmpty {
                    completedAnswer = Self.finalMessage(in: message) ?? ""
                }
                let result = completedAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !result.isEmpty else { throw CodexAppServerClient.ClientError.emptyResponse }
                return result
            }
        }

        if Date() >= timeoutDate { throw CodexAppServerClient.ClientError.timedOut }
        throw CodexAppServerClient.ClientError.connectionClosed("")
    }

    private func terminateProcessIfNeeded() {
        processLock.lock()
        defer { processLock.unlock() }
        guard process.isRunning else { return }
        let pid = process.processIdentifier
        if pid > 0 { Darwin.kill(pid, SIGTERM) }
    }

    private func publishPartialAnswerIfNeeded() {
        let now = Date()
        guard now.timeIntervalSince(lastPartialPublish) >= 0.2 else { return }
        lastPartialPublish = now
        onPartialAnswer(answerChunks.joined())
    }

    private func send(_ object: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(0x0A)
        try inputPipe.fileHandleForWriting.write(contentsOf: data)
    }

    private func readLine() -> String? {
        while true {
            if let newline = outputBuffer.firstIndex(of: 0x0A) {
                let data = outputBuffer.prefix(upTo: newline)
                outputBuffer.removeSubrange(outputBuffer.startIndex...newline)
                return String(data: data, encoding: .utf8)
            }
            let chunk = outputPipe.fileHandleForReading.availableData
            if chunk.isEmpty { return nil }
            outputBuffer.append(chunk)
        }
    }

    private static func message(from line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return object as? [String: Any]
    }

    private static func finalMessage(in message: [String: Any]) -> String? {
        guard let params = message["params"] as? [String: Any],
              let turn = params["turn"] as? [String: Any],
              let items = turn["items"] as? [[String: Any]] else { return nil }
        return items.reversed().first { $0["type"] as? String == "agentMessage" }?["text"] as? String
    }

    private static func codexExecutableURL() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "\(home)/.local/bin/codex",
            "\(home)/.codex/bin/codex"
        ]
        return candidates.first(where: FileManager.default.isExecutableFile(atPath:))
            .map { URL(fileURLWithPath: $0) }
    }

    private static func processEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let existingPath = environment["PATH"] ?? ""
        environment["PATH"] = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/.local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
            existingPath
        ].filter { !$0.isEmpty }.joined(separator: ":")
        environment["RUST_LOG"] = "error"
        return environment
    }
}
