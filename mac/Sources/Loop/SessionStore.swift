import AppKit
import Combine

final class SessionStore: ObservableObject {
    @Published var text: String { didSet { scheduleSave() } }
    @Published var comments: [Comment] { didSet { scheduleSave() } }
    @Published var general: String { didSet { scheduleSave() } }
    @Published var selection = NSRange(location: 0, length: 0)
    @Published var activeID: UUID?
    @Published var draft: Comment?
    @Published var draftBody = ""
    @Published var navigationRequest: UUID?
    @Published var preview = false
    @Published var confirmNew = false
    @Published var confirmSubmit = false
    @Published var toast: String?
    @Published var persistenceError: String?
    let demo: Bool
    let review: ReviewRequest?
    private(set) var submitted = false
    private var saveWork: DispatchWorkItem?
    private var toastWork: DispatchWorkItem?
    private let writer = DispatchQueue(label: "com.chris.loop.session")
    private let sessionURL: URL

    init(session: Session? = nil, review: ReviewRequest? = nil) {
        let env = ProcessInfo.processInfo.environment
        self.review = review
        demo = review == nil && (session != nil || env["LOOP_DEMO"] == "1")
        sessionURL = review?.draftURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Loop/session.json")
        var restored = Session()
        var loadError: String?
        if let session {
            restored = session
        } else if let review {
            restored.text = review.text
            if let data = try? Data(contentsOf: sessionURL),
               let draft = try? JSONDecoder().decode(Session.self, from: data), draft.text == review.text {
                restored = draft
            }
        } else if demo {
            restored = Demo.session
        } else if FileManager.default.fileExists(atPath: sessionURL.path) {
            do {
                restored = try JSONDecoder().decode(Session.self, from: Data(contentsOf: sessionURL))
            } catch {
                loadError = "无法读取上次会话：\(error.localizedDescription)"
            }
        }
        text = restored.text
        comments = restored.comments.filter { CommentRanges.valid($0.range, in: restored.text) }.map {
            var comment = $0
            comment.quote = (restored.text as NSString).substring(with: comment.range)
            return comment
        }
        general = restored.general
        persistenceError = loadError
        preview = demo && env["LOOP_DEMO_PREVIEW"] == "1"
    }

    var sortedComments: [Comment] { comments.sorted { $0.location < $1.location } }
    var canAdd: Bool {
        guard draft == nil, let range = CommentRanges.trimmed(selection, in: text) else { return false }
        return !comments.contains { $0.range == range }
    }
    var hasContent: Bool { !text.isEmpty || !comments.isEmpty || !general.isEmpty || draft != nil }
    var exported: String { FeedbackExporter.export(text: text, comments: comments, general: general) }
    var hasFeedback: Bool { !comments.isEmpty || !general.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    /// What the reviewing agent receives; submitting with no feedback means the plan is approved.
    var submission: String { hasFeedback ? exported : ReviewRequest.approval }

    func addComment() {
        guard canAdd, let range = CommentRanges.trimmed(selection, in: text) else { return }
        draft = Comment(location: range.location, length: range.length,
                        quote: (text as NSString).substring(with: range), body: "")
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

    func willReplace(_ range: NSRange, with replacement: String) {
        let count = (replacement as NSString).length
        comments = comments.compactMap { comment in
            guard let adjusted = CommentRanges.adjusted(comment.range, replacing: range, withLength: count) else { return nil }
            var changed = comment
            changed.location = adjusted.location
            changed.length = adjusted.length
            return changed
        }
        if var pending = draft {
            if let adjusted = CommentRanges.adjusted(pending.range, replacing: range, withLength: count) {
                pending.location = adjusted.location
                pending.length = adjusted.length
                draft = pending
            } else { cancelDraft() }
        }
        if activeID != draft?.id && !comments.contains(where: { $0.id == activeID }) { activeID = nil }
    }

    func textChanged(_ value: String) {
        text = value
        comments = comments.compactMap { comment in
            guard CommentRanges.valid(comment.range, in: value) else { return nil }
            var changed = comment
            changed.quote = (value as NSString).substring(with: comment.range)
            return changed
        }
        if var pending = draft, CommentRanges.valid(pending.range, in: value) {
            pending.quote = (value as NSString).substring(with: pending.range)
            draft = pending
        }
    }

    func requestNew() {
        guard review == nil else { return }
        if hasContent { confirmNew = true } else { clear() }
    }
    func clear() {
        cancelDraft()
        activeID = nil
        selection = NSRange(location: 0, length: 0)
        text = ""
        comments = []
        general = ""
        navigationRequest = UUID()
    }

    func copyFeedback() {
        copyFeedback(to: .general)
    }

    func copyFeedback(to pasteboard: NSPasteboard) {
        let hasGeneral = !general.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if comments.isEmpty && !hasGeneral {
            show("还没有批注")
        } else {
            pasteboard.clearContents()
            pasteboard.setString(exported, forType: .string)
            show("已复制 \(comments.count) 条批注到剪贴板" + (hasGeneral ? "（含总体意见）" : ""))
        }
    }

    /// Keeps a comment that is still being typed, then asks before approving a plan without feedback.
    func requestSubmit() {
        guard review != nil else { return }
        if draft != nil {
            if draftBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { cancelDraft() } else { saveDraft() }
        }
        if hasFeedback { submit() } else { confirmSubmit = true }
    }

    func submit() {
        guard let review, !submitted else { return }
        do { try review.deliver(submission) } catch {
            persistenceError = "提交失败：\(error.localizedDescription)"
            return
        }
        submitted = true
        saveWork?.cancel()
        try? FileManager.default.removeItem(at: sessionURL)
        NSApp.terminate(nil)
    }

    private func show(_ message: String) {
        toast = message
        toastWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.toast = nil }
        toastWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: work)
    }

    private var snapshot: Session { Session(text: text, comments: comments, general: general) }
    private func scheduleSave() {
        guard !demo, !submitted else { return }
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    func saveNow() {
        guard !demo, !submitted else { return }
        saveWork?.cancel()
        let session = snapshot
        let url = sessionURL
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
