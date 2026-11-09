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

    /// Entries under the day they were submitted, newest first.
    var days: [(label: String, entries: [HistoryEntry])] {
        entries.reduce(into: []) { days, entry in
            let label = entry.dayLabel()
            if days.last?.label == label { days[days.count - 1].entries.append(entry) } else { days.append((label, [entry])) }
        }
    }
}

/// An index down the desk on the left and the selected review as one sheet on the right; the selected row is the
/// sheet's own tab, so the list and the paper read as a single object.
struct HistoryHomeView: View {
    @StateObject private var browser = HistoryBrowser()
    @State private var selection: HistoryEntry.ID?
    @Namespace private var tab
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let indexWidth: CGFloat = 276

    var body: some View {
        HStack(spacing: 0) {
            index
                .frame(width: indexWidth)
                .zIndex(1)
            sheet
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    Color(Theme.sheet)
                        .shadow(color: Color.black.opacity(0.07), radius: 14, x: -2, y: 0)
                )
        }
        .ignoresSafeArea()
        .background(Color(Theme.ground).ignoresSafeArea())
        .frame(minWidth: 720, minHeight: 480)
        .onAppear {
            browser.reload()
            selection = browser.preferredSelection(current: selection)
        }
    }

    private var index: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(browser.days, id: \.label) { day in
                    Text(day.label)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Color(Theme.secondary))
                        .padding(.leading, 26)
                        .padding(.top, 20)
                        .padding(.bottom, 8)
                    ForEach(day.entries) { entry in
                        IndexRow(entry: entry, isSelected: selection == entry.id, tab: tab) {
                            withAnimation(reduceMotion ? nil : .spring(duration: 0.3, bounce: 0)) { selection = entry.id }
                        }
                    }
                }
            }
            .padding(.top, 34)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.never)
    }

    @ViewBuilder private var sheet: some View {
        if let entry = browser.entries.first(where: { $0.id == selection }) {
            HistoryPaper(entry: entry).id(entry.id)
        } else {
            LoopMark()
                .stroke(Color(Theme.vermilion).opacity(0.22), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                .frame(width: 72, height: 72)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityHidden(true)
        }
    }
}

private struct IndexRow: View {
    let entry: HistoryEntry
    let isSelected: Bool
    let tab: Namespace.ID
    let onSelect: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 5) {
                Text(entry.title)
                    .font(Font(Theme.song(15)))
                    .foregroundStyle(Color(isSelected ? Theme.heading : Theme.ink))
                    .lineLimit(2)
                    .lineSpacing(2)
                    .multilineTextAlignment(.leading)
                Text("\(entry.agentName) · \(entry.channel.label)")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color(Theme.secondary))
                    .lineLimit(1)
            }
            .padding(.leading, 16)
            .padding(.trailing, 22)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background { background }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.leading, 10)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityLabel("\(entry.title)，\(entry.agentName)，\(entry.channel.label)")
    }

    @ViewBuilder private var background: some View {
        if isSelected {
            IndexTab(radius: 10)
                .fill(Color(Theme.sheet))
                .padding(.vertical, -10)
                .matchedGeometryEffect(id: "tab", in: tab)
        } else if hovering {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(Theme.sheet).opacity(0.5))
                .padding(.trailing, 10)
        }
    }
}

/// A file tab: rounded towards the desk, flaring into the sheet it belongs to. `rect` includes `radius` of room
/// above and below the row for the two flares.
private struct IndexTab: Shape {
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let top = rect.minY + radius, bottom = rect.maxY - radius
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: top), tangent2End: CGPoint(x: rect.maxX - radius, y: top), radius: radius)
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: top), tangent2End: CGPoint(x: rect.minX, y: bottom), radius: radius)
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: bottom), tangent2End: CGPoint(x: rect.maxX, y: bottom), radius: radius)
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: bottom), tangent2End: CGPoint(x: rect.maxX, y: rect.maxY), radius: radius)
        path.closeSubpath()
        return path
    }
}
