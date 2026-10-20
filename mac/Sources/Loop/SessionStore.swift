import AppKit
import Combine

final class SessionStore: ObservableObject {
    @Published var comments: [Comment] { didSet { scheduleSave() } }
    /// The saved 总评; `generalDraft` holds it while it is being edited.
    @Published var general: String { didSet { scheduleSave() } }
    @Published var generalDraft = ""
    @Published var editingGeneral = false
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
        let hidden = MarkdownStyler.apply(to: NSTextStorage(string: text), comments: [])
        self.hidden = hidden
        comments = restored.comments.filter { CommentRanges.valid($0.range, in: text) }.map {
            var comment = $0
            comment.quote = CommentRanges.visibleText(of: comment.range, in: text, hidden: hidden)
            return comment
        }
        general = restored.general
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
    var exported: String { FeedbackExporter.export(text: text, comments: comments, general: general, hidden: hidden) }
    var hasFeedback: Bool { !comments.isEmpty || !general.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
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

    func beginGeneral() {
        guard !editingGeneral else { return }
        generalDraft = general
        editingGeneral = true
    }

    func saveGeneral() {
        guard editingGeneral else { return }
        general = generalDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        editingGeneral = false
    }

    func cancelGeneral() {
        generalDraft = general
        editingGeneral = false
    }

    /// ⌘↩ saves whatever is being written — a comment, or the 总评 — and otherwise starts a comment.
    func commitShortcut() {
        if draft != nil { saveDraft() } else if editingGeneral { saveGeneral() } else { addComment() }
    }

    var canCommitShortcut: Bool {
        if draft != nil { return !draftBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return editingGeneral || canAdd
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
        let session = Session(text: text, comments: comments, general: general)
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
