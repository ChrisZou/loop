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

    private let sidebarWidth: CGFloat = 300

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: sidebarWidth)
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(Theme.ground).ignoresSafeArea())
        .frame(minWidth: 720, minHeight: 480)
        .onAppear {
            browser.reload()
            selection = browser.preferredSelection(current: selection)
        }
    }

    @ViewBuilder private var sidebar: some View {
        if browser.entries.isEmpty {
            Color(Theme.ground)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(browser.entries) { entry in
                        HistoryRow(
                            entry: entry,
                            isSelected: selection == entry.id,
                            onSelect: { selection = entry.id }
                        )
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
            }
            .background(Color(Theme.sheet))
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(Color(Theme.rule))
                    .frame(width: 1)
            }
        }
    }

    @ViewBuilder private var detail: some View {
        if let entry = browser.entries.first(where: { $0.id == selection }) {
            HistoryDetailView(entry: entry)
        } else {
            // Empty history, or list present but nothing selected: pure ground, no copy.
            Color(Theme.ground)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct HistoryRow: View {
    let entry: HistoryEntry
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(isSelected ? Color(Theme.vermilion) : Color.clear)
                    .frame(width: 2.5)
                    .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.title)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(Color(Theme.ink))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text("\(entry.agentName) · \(entry.channel.label)")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color(Theme.secondary))
                        .lineLimit(1)
                }
                .padding(.leading, 11)
                .padding(.trailing, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(rowFill)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityLabel("\(entry.title)，\(entry.agentName)，\(entry.channel.label)")
    }

    private var rowFill: Color {
        if isSelected { return Color(Theme.selection) }
        if hovering { return Color(Theme.rule) }
        return Color.clear
    }
}

private struct HistoryDetailView: View {
    let entry: HistoryEntry

    private let contentWidth: CGFloat = 680

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                Color.clear.frame(height: 24)
                paperStack(label: "方案", body: entry.document)
                if hasFeedback {
                    Color.clear.frame(height: 18)
                    paperStack(label: "反馈", body: entry.feedback)
                }
            }
            .frame(maxWidth: contentWidth, alignment: .leading)
            .padding(.horizontal, 36)
            .padding(.top, 28)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(Color(Theme.ground))
    }

    private var hasFeedback: Bool {
        !entry.feedback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.title)
                .font(Font(Theme.serif(24)))
                .foregroundStyle(Color(Theme.heading))
            Text("\(entry.agentName) · \(entry.channel.label)")
                .font(.system(size: 12.5))
                .foregroundStyle(Color(Theme.secondary))
        }
    }

    private func paperStack(label: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(Font(Theme.serif(13)))
                .foregroundStyle(Color(Theme.vermilion))
                .tracking(1.5)
            Text(body)
                .font(.system(size: 14))
                .lineSpacing(6)
                .foregroundStyle(Color(Theme.ink))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(30)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(Theme.sheet))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color(Theme.rule), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
                )
        }
    }
}
