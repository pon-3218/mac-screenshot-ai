import Foundation

final class FirstPartialTiming: @unchecked Sendable {
    private let lock = NSLock()
    private var elapsed: TimeInterval?

    func record(_ value: TimeInterval) {
        lock.lock()
        if elapsed == nil {
            elapsed = value
        }
        lock.unlock()
    }

    func value(or fallback: TimeInterval) -> TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return elapsed ?? fallback
    }
}

@main
struct CodexClientSmoke {
    static func main() async {
        guard CommandLine.arguments.count == 2 else {
            fputs("usage: CodexClientSmoke <image-path>\n", stderr)
            exit(2)
        }
        let imageURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let started = Date()
        let firstPartialTiming = FirstPartialTiming()
        do {
            let answer = try await CodexAppServerClient().ask(
                question: "この画像に何が写っているか一文で答えてください。",
                imageURL: imageURL
            ) { _ in
                firstPartialTiming.record(Date().timeIntervalSince(started))
            }
            let elapsed = Date().timeIntervalSince(started)
            let firstPartialAt = firstPartialTiming.value(or: elapsed)
            print("first=\(String(format: "%.2f", firstPartialAt)) completed=\(String(format: "%.2f", elapsed)) chars=\(answer.count)")
        } catch {
            fputs("\(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}
