import SwiftUI

/// Cold-start home: past submissions, Mac-local first (web merge deferred).
final class HistoryBrowser: ObservableObject {
    @Published private(set) var entries: [HistoryEntry] = []
    private let store: HistoryStore

    init(store: HistoryStore = .shared) {
        self.store = store
        reload()
    }

    func reload() {
        entries = store.load()
    }

    /// Prefer keeping the current selection; otherwise open the newest entry.
    func preferredSelection(current: HistoryEntry.ID?) -> HistoryEntry.ID? {
        if let current, entries.contains(where: { $0.id == current }) { return current }
        return entries.first?.id
    }
}

struct HistoryHomeView: View {
    @StateObject private var browser = HistoryBrowser()
    @State private var selection: HistoryEntry.ID?

    var body: some View {
        NavigationSplitView {
            list
                .navigationSplitViewColumnWidth(min: 240, ideal: 300, max: 400)
        } detail: {
            detail
        }
        .background(Color(Theme.ground).ignoresSafeArea())
        .frame(minWidth: 720, minHeight: 480)
        .onAppear {
            browser.reload()
            selection = browser.preferredSelection(current: selection)
        }
    }

    private var list: some View {
        Group {
            if browser.entries.isEmpty {
                VStack(spacing: 12) {
                    Text("还没有批注记录")
                        .font(Font(Theme.serif(18)))
                        .foregroundStyle(Color(Theme.heading))
                    Text("用 loop review 打开方案并提交后，会出现在这里。")
                        .font(.system(size: 13))
                        .foregroundStyle(Color(Theme.secondary))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(24)
                .background(Color(Theme.ground))
            } else {
                List(selection: $selection) {
                    ForEach(browser.entries) { entry in
                        HistoryRow(entry: entry)
                            .tag(entry.id)
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .navigationTitle("批注记录")
    }

    @ViewBuilder private var detail: some View {
        if let entry = browser.entries.first(where: { $0.id == selection }) {
            HistoryDetailView(entry: entry)
        } else {
            VStack(spacing: 10) {
                Text(browser.entries.isEmpty ? "提交后可在此回看全文与反馈" : "选择一条记录")
                    .font(Font(Theme.serif(20)))
                    .foregroundStyle(Color(Theme.heading))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(Theme.ground))
        }
    }
}

private struct HistoryRow: View {
    let entry: HistoryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.title)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(Color(Theme.heading))
                .lineLimit(2)
            Text("\(entry.agentName) · \(entry.channel.label)")
                .font(.system(size: 12))
                .foregroundStyle(Color(Theme.secondary))
                .lineLimit(1)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.title)，\(entry.agentName)，\(entry.channel.label)")
    }
}

private struct HistoryDetailView: View {
    let entry: HistoryEntry

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                section(title: "方案", body: entry.document)
                section(title: "反馈", body: entry.feedback)
            }
            .frame(maxWidth: Theme.sheetWidth, alignment: .leading)
            .padding(.horizontal, 36)
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(Color(Theme.ground))
        .navigationTitle(entry.title)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(entry.title)
                .font(Font(Theme.serif(26)))
                .foregroundStyle(Color(Theme.heading))
            Text("\(entry.agentName) · \(entry.channel.label)")
                .font(.system(size: 13))
                .foregroundStyle(Color(Theme.secondary))
        }
    }

    private func section(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(Font(Theme.serif(15)))
                .foregroundStyle(Color(Theme.vermilion))
            Text(body)
                .font(.system(size: 14))
                .lineSpacing(6)
                .foregroundStyle(Color(Theme.ink))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(Theme.sheet))
                )
        }
    }
}
