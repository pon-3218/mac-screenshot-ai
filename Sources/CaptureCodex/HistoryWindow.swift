import AppKit
import SwiftUI

@MainActor
final class HistoryWindowController: NSWindowController {
    init(store: HistoryStore) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 560),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Capture Codex 履歴"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 680, height: 440)
        window.titlebarAppearsTransparent = true
        window.contentView = NSHostingView(rootView: HistoryView(store: store))
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct HistoryView: View {
    @ObservedObject var store: HistoryStore
    @State private var selectedID: UUID?

    var body: some View {
        Group {
            if store.entries.isEmpty {
                emptyView
            } else {
                HSplitView {
                    sidebar
                    detail
                }
            }
        }
        .frame(minWidth: 680, minHeight: 440)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            if selectedEntry == nil {
                selectedID = store.entries.first?.id
            }
        }
        .onChange(of: store.entries) {
            if selectedEntry == nil {
                selectedID = store.entries.first?.id
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("履歴")
                    .font(.system(size: 20, weight: .semibold))
                Text("直近\(store.entries.count)件")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 12)

            List(selection: $selectedID) {
                ForEach(store.entries) { entry in
                    HistoryRow(entry: entry)
                        .tag(entry.id)
                }
            }
            .listStyle(.sidebar)
        }
        .frame(minWidth: 248, idealWidth: 272, maxWidth: 320)
    }

    @ViewBuilder
    private var detail: some View {
        if let entry = selectedEntry {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(entry.question.isEmpty ? "質問なし" : entry.question)
                            .font(.system(size: 22, weight: .semibold))
                            .textSelection(.enabled)

                        Text(metadata(for: entry))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("回答")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button(action: { copy(entry.answer) }) {
                                Label("回答をコピー", systemImage: "doc.on.doc")
                            }
                            .buttonStyle(.borderless)
                        }

                        Text(entry.answer)
                            .font(.system(size: 14))
                            .lineSpacing(4)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minWidth: 420)
        } else {
            Text("履歴を選択してください")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var emptyView: some View {
        ContentUnavailableView(
            "履歴はまだありません",
            systemImage: "clock.arrow.circlepath",
            description: Text("キャプチャについて質問すると、回答がここに保存されます。")
        )
    }

    private var selectedEntry: AnswerHistoryEntry? {
        guard let selectedID else { return nil }
        return store.entries.first(where: { $0.id == selectedID })
    }

    private func metadata(for entry: AnswerHistoryEntry) -> String {
        let modelName = ResponseModelOption.all.first(where: { $0.id == entry.modelID })?.name
            ?? entry.modelID
        let effortName = (ReasoningEffortOption.standard + [.maximum])
            .first(where: { $0.id == entry.reasoningEffort })?.name
            ?? entry.reasoningEffort
        return "\(entry.createdAt.formatted(date: .abbreviated, time: .shortened))  ·  \(modelName) / \(effortName)"
    }

    private func copy(_ answer: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(answer, forType: .string)
    }
}

private struct HistoryRow: View {
    let entry: AnswerHistoryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(entry.question.isEmpty ? "質問なし" : entry.question)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(2)
            Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
    }
}
