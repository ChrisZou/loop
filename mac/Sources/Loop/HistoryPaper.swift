import AppKit
import SwiftUI

/// A submitted review as a marked paper: the plan set exactly as it was reviewed, the commented passages still
/// underlined in red, and the reviewer's remarks at the end.
struct HistoryPaper: View {
    let entry: HistoryEntry

    private var notes: FeedbackNotes { FeedbackNotes(entry.feedback) }
    private var folder: URL? { entry.sourcePath.map { URL(fileURLWithPath: $0).deletingLastPathComponent() } }

    var body: some View {
        GeometryReader { pane in
            // A settled width, the same as the review sheet's when there's room: the text is measured against it.
            let column = max(240, min(MarkdownStyler.textWidth, pane.size.width - 88))
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(entry.title)
                        .font(Font(Theme.song(30, bold: true)))
                        .foregroundStyle(Color(Theme.heading))
                        .lineSpacing(4)
                        .textSelection(.enabled)
                    Text(meta)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Color(Theme.secondary))
                        .padding(.top, 10)
                    PaperText(text: entry.documentBody, notes: notes, folder: folder, width: column)
                        .padding(.top, 36)
                    if notes.hasRemarks {
                        Remarks(notes: notes).padding(.top, 44)
                    }
                }
                .frame(width: column, alignment: .leading)
                .padding(.top, 72)
                .padding(.bottom, 96)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.never)
        }
    }

    private var meta: String {
        ([entry.agentName, entry.channel.label] + (entry.timeLabel().map { [$0] } ?? [])).joined(separator: " · ")
    }
}

private struct Remarks: View {
    let notes: FeedbackNotes

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(Color(Theme.rule)).frame(height: 1)
            if let plain = notes.plain {
                Text(plain)
                    .font(.system(size: 15))
                    .lineSpacing(6)
                    .foregroundStyle(Color(Theme.ink))
                    .textSelection(.enabled)
                    .padding(.top, 36)
            }
            VStack(alignment: .leading, spacing: 30) {
                ForEach(Array(notes.marks.enumerated()), id: \.offset) { _, mark in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(mark.quote)
                            .font(.system(size: 13.5))
                            .lineSpacing(4)
                            .foregroundStyle(Color(Theme.secondary))
                        if !mark.body.isEmpty { remark(mark.body, size: 16.5) }
                        attachments(mark.images)
                    }
                }
                if notes.approved {
                    HStack(alignment: .top, spacing: 14) {
                        TickShape()
                            .stroke(Color(Theme.vermilion), style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
                            .frame(width: 30, height: 24)
                            .padding(.top, 2)
                            .accessibilityHidden(true)
                        remark(ReviewRequest.approval, size: 18)
                    }
                }
                if let closing = notes.closing {
                    VStack(alignment: .leading, spacing: 10) {
                        remark(closing, size: 18)
                        attachments(notes.closingImages)
                    }
                    .padding(.top, notes.marks.isEmpty ? 0 : 8)
                }
            }
            .padding(.top, 36)
            .textSelection(.enabled)
        }
    }

    private func remark(_ text: String, size: CGFloat) -> some View {
        Text(text)
            .font(Font(Theme.song(size)))
            .lineSpacing(6)
            .foregroundStyle(Color(Theme.vermilion))
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private func attachments(_ paths: [String]) -> some View {
        ForEach(paths, id: \.self) { path in
            if let image = NSImage(contentsOfFile: path) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 360, maxHeight: 260, alignment: .leading)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
    }
}

/// The review sheet's own text system, read-only and as tall as its content so the page scrolls as one.
private struct PaperText: NSViewRepresentable {
    let text: String
    let notes: FeedbackNotes
    let folder: URL?
    let width: CGFloat

    final class Coordinator {
        let markup = MarkupLayoutDelegate()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> PlanTextView {
        let storage = NSTextStorage()
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: MarkdownStyler.textWidth, height: CGFloat.greatestFiniteMagnitude))
        storage.addLayoutManager(manager)
        manager.addTextContainer(container)
        manager.delegate = context.coordinator.markup
        container.lineFragmentPadding = 0

        let view = PlanTextView(frame: .zero, textContainer: container)
        view.drawsSheet = false
        view.drawsBackground = false
        view.isRichText = false
        view.isEditable = false
        view.isSelectable = true
        view.textContainerInset = .zero
        view.font = MarkdownStyler.bodyFont
        view.selectedTextAttributes = [.backgroundColor: Theme.selection]
        view.setAccessibilityLabel("方案正文")
        view.string = text
        view.source = text as NSString

        let hidden = MarkdownStyler.apply(to: storage, source: text, comments: [], folder: folder)
        view.highlights = PaperText.ranges(of: notes.marks.map(\.quote), in: text, hidden: hidden)
            .map { Highlight(range: $0, active: false) }
        view.taskBoxes = MarkdownStyler.tasks(in: storage, text: text, hidden: hidden).map { task in
            let change = notes.checks.first { $0.text == task.text }
            return TaskBox(location: task.location, labelStart: task.labelStart, checked: change?.checked ?? task.checked, changed: change != nil)
        }
        return view
    }

    func updateNSView(_ view: PlanTextView, context: Context) {}

    func sizeThatFits(_ proposal: ProposedViewSize, nsView view: PlanTextView, context: Context) -> CGSize? {
        guard let manager = view.layoutManager, let container = view.textContainer, let storage = view.textStorage else { return nil }
        if abs(width - container.size.width) > 0.5 {
            container.size = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
            if let range = MarkdownStyler.fitTables(in: storage, width: width) {
                storage.beginEditing()
                storage.edited(.editedAttributes, range: range, changeInLength: 0)
                storage.endEditing()
            }
        }
        manager.ensureLayout(for: container)
        return CGSize(width: width, height: ceil(manager.usedRect(for: container).height))
    }

    /// Where each quote sits in the plan. Quotes are the text as it looked on screen, without its markdown, and come
    /// in document order, so each search starts after the last hit. A quote that isn't found is simply not underlined.
    static func ranges(of quotes: [String], in text: String, hidden: IndexSet) -> [NSRange] {
        let source = text as NSString
        var units: [unichar] = []
        var positions: [Int] = []
        for index in 0..<source.length where !hidden.contains(index) {
            units.append(source.character(at: index))
            positions.append(index)
        }
        let visible = NSString(characters: units, length: units.count)
        var start = 0
        return quotes.compactMap { quote in
            guard !quote.isEmpty else { return nil }
            let found = visible.range(of: quote, options: [], range: NSRange(location: start, length: visible.length - start))
            guard found.location != NSNotFound else { return nil }
            start = NSMaxRange(found)
            return NSRange(location: positions[found.location], length: positions[NSMaxRange(found) - 1] - positions[found.location] + 1)
        }
    }
}
