import AppKit
import Combine

final class SessionStore: ObservableObject {
    @Published var comments: [Comment] { didSet { scheduleSave() } }
    /// Saved 总评 notes. The composer below the plan writes a new one into `generalDraft`,
    /// or changes the one at `editingGeneral`.
    @Published var generals: [String] { didSet { scheduleSave() } }
    /// Task items whose box the reviewer changed, by `TaskItem.location`. Clicking again changes it back.
    @Published var toggled: Set<Int> { didSet { scheduleSave() } }
    @Published var generalDraft = ""
    @Published var editingGeneral: Int?
    /// The composer has focus, so ⌘↩ saves the 总评 instead of starting a comment.
    @Published var composingGeneral = false
    @Published var selection = NSRange(location: 0, length: 0)
    @Published var activeID: UUID?
    @Published var draft: Comment?
    @Published var draftBody = ""
    @Published var navigationRequest: UUID?
    @Published var preview = false
    @Published var confirmSubmit = false
    @Published var persistenceError: String?
    /// Where the editor drew the sheet, so the 总评 bar can match its width and center.
    @Published var sheet = SheetLayout(width: Theme.sheetWidth, offset: 0)
    let review: ReviewRequest
    var text: String { review.text }
    /// Markdown syntax the editor hides; selections never start or end on it and quotes leave it out.
    let hidden: IndexSet
    /// The plan's `- [ ]` items, in order.
    let tasks: [TaskItem]
    private(set) var submitted = false
    /// Demo and self-test stores never touch drafts on disk.
    private let persists: Bool
    private var saveWork: DispatchWorkItem?
    private let writer = DispatchQueue(label: "com.chris.loop.session")

    init(review: ReviewRequest, restoring session: Session? = nil) {
        self.review = review
        persists = session == nil
        var restored = Session(text: review.text)
        if let session {
            restored = session
        } else if let data = try? Data(contentsOf: review.draftURL),
                  let draft = try? JSONDecoder().decode(Session.self, from: data), draft.text == review.text {
            restored = draft
        }
        let text = review.text
        let styled = NSTextStorage(string: text)
        let hidden = MarkdownStyler.apply(to: styled, comments: [])
        self.hidden = hidden
        tasks = MarkdownStyler.tasks(in: styled, text: text, hidden: hidden)
        toggled = Set(restored.toggled).intersection(tasks.map(\.location))
        comments = restored.comments.filter { CommentRanges.valid($0.range, in: text) }.map {
            var comment = $0
            comment.quote = CommentRanges.visibleText(of: comment.range, in: text, hidden: hidden)
            return comment
        }
        generals = restored.generals
    }

    /// The plan's first top-level heading, else its file name.
    var documentTitle: String {
        let heading = try? NSRegularExpression(pattern: "(?m)^#[ \\t]+(.+)$")
        if let match = heading?.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) {
            let title = CommentRanges.visibleText(of: match.range(at: 1), in: text, hidden: hidden)
                .trimmingCharacters(in: .whitespaces)
            if !title.isEmpty { return title }
        }
        return review.source.deletingPathExtension().lastPathComponent
    }

    var sortedComments: [Comment] { comments.sorted { $0.location < $1.location } }
    var canAdd: Bool {
        guard draft == nil, let range = CommentRanges.trimmed(selection, in: text, hidden: hidden) else { return false }
        return !comments.contains { $0.range == range }
    }
    var exported: String {
        FeedbackExporter.export(text: text, comments: comments, generals: generals, hidden: hidden,
                                checks: changedTasks.map { ($0.text, isChecked($0)) })
    }
    var hasFeedback: Bool { !comments.isEmpty || !generals.isEmpty || !toggled.isEmpty }

    /// Ticked on screen: the plan's state, flipped if the reviewer changed it.
    func isChecked(_ task: TaskItem) -> Bool { task.checked != toggled.contains(task.location) }
    var changedTasks: [TaskItem] { tasks.filter { toggled.contains($0.location) } }

    func toggleTask(at location: Int) {
        guard tasks.contains(where: { $0.location == location }) else { return }
        if toggled.contains(location) { toggled.remove(location) } else { toggled.insert(location) }
    }
    /// What the reviewing agent receives; submitting with no feedback means the plan is approved.
    var submission: String { hasFeedback ? exported : ReviewRequest.approval }

    func addComment() {
        guard canAdd, let range = CommentRanges.trimmed(selection, in: text, hidden: hidden) else { return }
        draft = Comment(location: range.location, length: range.length,
                        quote: CommentRanges.visibleText(of: range, in: text, hidden: hidden), body: "")
        draftBody = ""
        activeID = draft?.id
    }

    func edit(_ comment: Comment) {
        draft = comment
        draftBody = comment.body
        activeID = comment.id
    }

    func saveDraft() {
        guard var comment = draft else { return }
        let body = draftBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        comment.body = body
        if let index = comments.firstIndex(where: { $0.id == comment.id }) { comments[index] = comment }
        else { comments.append(comment) }
        draft = nil
        draftBody = ""
        selection = NSRange(location: NSMaxRange(selection), length: 0)
        navigationRequest = UUID()
    }

    func cancelDraft() {
        draft = nil
        draftBody = ""
        if !comments.contains(where: { $0.id == activeID }) { activeID = nil }
    }

    func remove(_ id: UUID) {
        comments.removeAll { $0.id == id }
        if draft?.id == id { cancelDraft() }
        if activeID == id { activeID = nil }
    }

    /// Files the composer's text as a 总评 note — a new one, or the one being changed — and empties the composer.
    func saveGeneral() {
        let note = generalDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if let index = editingGeneral, generals.indices.contains(index) {
            if note.isEmpty { generals.remove(at: index) } else { generals[index] = note }
        } else if !note.isEmpty {
            generals.append(note)
        }
        generalDraft = ""
        editingGeneral = nil
    }

    func editGeneral(at index: Int) {
        guard generals.indices.contains(index) else { return }
        editingGeneral = index
        generalDraft = generals[index]
    }

    func cancelGeneral() {
        generalDraft = ""
        editingGeneral = nil
    }

    func removeGeneral(at index: Int) {
        guard generals.indices.contains(index) else { return }
        generals.remove(at: index)
        if editingGeneral == index { cancelGeneral() } else if let editing = editingGeneral, editing > index { editingGeneral = editing - 1 }
    }

    /// ⌘↩ saves whatever is being written — a comment, or a 总评 — and otherwise starts a comment.
    func commitShortcut() {
        if draft != nil { saveDraft() } else if composingGeneral { saveGeneral() } else { addComment() }
    }

    var canCommitShortcut: Bool {
        if draft != nil { return !draftBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if composingGeneral { return editingGeneral != nil || !generalDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return canAdd
    }

    /// Keeps a comment or 总评 that is still being typed, then asks before approving a plan without feedback.
    func requestSubmit() {
        saveGeneral()
        if draft != nil {
            if draftBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { cancelDraft() } else { saveDraft() }
        }
        if hasFeedback { submit() } else { confirmSubmit = true }
    }

    func submit() {
        guard !submitted else { return }
        do { try review.deliver(submission) } catch {
            persistenceError = "提交失败：\(error.localizedDescription)"
            return
        }
        submitted = true
        saveWork?.cancel()
        if persists { try? FileManager.default.removeItem(at: review.draftURL) }
        NSApp.terminate(nil)
    }

    private func scheduleSave() {
        guard persists, !submitted else { return }
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    func saveNow() {
        guard persists, !submitted else { return }
        saveWork?.cancel()
        let session = Session(text: text, comments: comments, generals: generals, toggled: toggled.sorted())
        let url = review.draftURL
        // Synchronous serial writes guarantee the final quit save is durable and newest.
        do {
            try writer.sync {
                let data = try JSONEncoder().encode(session)
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: url, options: .atomic)
            }
            persistenceError = nil
        } catch { persistenceError = "保存失败：\(error.localizedDescription)" }
    }
}

struct SheetLayout: Equatable {
    var width: CGFloat
    /// The sheet's center relative to the window's center.
    var offset: CGFloat
}
