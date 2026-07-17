import Foundation

struct AnswerHistoryEntry: Codable, Identifiable, Hashable {
    let id: UUID
    let createdAt: Date
    let question: String
    let answer: String
    let modelID: String
    let reasoningEffort: String
}

@MainActor
final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()

    @Published private(set) var entries: [AnswerHistoryEntry] = []

    private let historyURL: URL
    private let maximumEntries = 100

    private init(fileManager: FileManager = .default) {
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.homeDirectoryForCurrentUser
        let directory = applicationSupport.appendingPathComponent("CaptureCodex", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        historyURL = directory.appendingPathComponent("history.json")
        load()
        importLastAnswerIfNeeded()
    }

    func add(
        question: String,
        answer: String,
        modelID: String,
        reasoningEffort: String
    ) {
        let entry = AnswerHistoryEntry(
            id: UUID(),
            createdAt: Date(),
            question: question,
            answer: answer,
            modelID: modelID,
            reasoningEffort: reasoningEffort
        )
        entries.insert(entry, at: 0)
        if entries.count > maximumEntries {
            entries.removeLast(entries.count - maximumEntries)
        }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: historyURL),
              let decoded = try? JSONDecoder().decode([AnswerHistoryEntry].self, from: data) else {
            return
        }
        entries = decoded.sorted { $0.createdAt > $1.createdAt }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: historyURL, options: .atomic)
    }

    private func importLastAnswerIfNeeded() {
        let defaults = UserDefaults.standard
        let migrationKey = "history.importedLastAnswer"
        guard !defaults.bool(forKey: migrationKey) else { return }
        defer { defaults.set(true, forKey: migrationKey) }

        guard entries.isEmpty,
              let answer = defaults.string(forKey: "lastResponse"),
              !answer.isEmpty else { return }

        entries = [
            AnswerHistoryEntry(
                id: UUID(),
                createdAt: Date(),
                question: defaults.string(forKey: "lastPrompt") ?? "",
                answer: answer,
                modelID: AppSettings.shared.modelID,
                reasoningEffort: AppSettings.shared.reasoningEffort
            )
        ]
        save()
    }
}
