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
    @Published var editorFocus = UUID()
    @Published var navigationRequest: UUID?
    @Published var preview = false
    @Published var confirmNew = false
    @Published var toast: String?
    @Published var persistenceError: String?
    let demo: Bool
    private var saveWork: DispatchWorkItem?
    private var toastWork: DispatchWorkItem?
    private let writer = DispatchQueue(label: "com.chris.loop.session")
    private let sessionURL: URL

    init(session: Session? = nil) {
        let env = ProcessInfo.processInfo.environment
        demo = session != nil || env["LOOP_DEMO"] == "1"
        sessionURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Loop/session.json")
        var restored = Session()
        var loadError: String?
        if let session {
            restored = session
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
        draft == nil && CommentRanges.valid(selection, in: text)
            && !comments.contains { $0.range == selection }
    }
    var hasContent: Bool { !text.isEmpty || !comments.isEmpty || !general.isEmpty || draft != nil }
    var exported: String { FeedbackExporter.export(text: text, comments: comments, general: general) }

    func addComment() {
        guard canAdd else { return }
        draft = Comment(location: selection.location, length: selection.length,
                        quote: (text as NSString).substring(with: selection), body: "")
        draftBody = ""
        activeID = draft?.id
        editorFocus = UUID()
    }

    func edit(_ comment: Comment) {
        draft = comment
        draftBody = comment.body
        activeID = comment.id
        editorFocus = UUID()
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

    func navigate(to comment: Comment) {
        activeID = comment.id
        selection = comment.range
        navigationRequest = UUID()
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

    func requestNew() { if hasContent { confirmNew = true } else { clear() } }
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
            toast = "还没有批注"
        } else {
            pasteboard.clearContents()
            pasteboard.setString(exported, forType: .string)
            toast = "已复制 \(comments.count) 条批注到剪贴板" + (hasGeneral ? "（含总体意见）" : "")
        }
        toastWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.toast = nil }
        toastWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: work)
    }

    private var snapshot: Session { Session(text: text, comments: comments, general: general) }
    private func scheduleSave() {
        guard !demo else { return }
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    func saveNow() {
        guard !demo else { return }
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
