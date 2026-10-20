import AppKit
import Combine

final class SessionStore: ObservableObject {
    @Published var comments: [Comment] { didSet { scheduleSave() } }
    @Published var general: String { didSet { scheduleSave() } }
    @Published var selection = NSRange(location: 0, length: 0)
    @Published var activeID: UUID?
    @Published var draft: Comment?
    @Published var draftBody = ""
    @Published var navigationRequest: UUID?
    @Published var preview = false
    @Published var confirmSubmit = false
    @Published var persistenceError: String?
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
        let hidden = MarkdownStyler.apply(to: NSTextStorage(string: text), comments: [], activeID: nil, draft: nil)
        self.hidden = hidden
        comments = restored.comments.filter { CommentRanges.valid($0.range, in: text) }.map {
            var comment = $0
            comment.quote = CommentRanges.visibleText(of: comment.range, in: text, hidden: hidden)
            return comment
        }
        general = restored.general
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

    /// Keeps a comment that is still being typed, then asks before approving a plan without feedback.
    func requestSubmit() {
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
