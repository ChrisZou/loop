import AppKit

enum SelfTest {
    static func run() {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ description: String) {
            guard condition() else {
                FileHandle.standardError.write(Data("FAIL: \(description)\n".utf8))
                exit(1)
            }
            checks += 1
        }
        let text = "第一行\n第二行\n最后一段😀"
        let first = Comment(location: 0, length: 7, quote: "旧引文", body: "请简化\n保留重点")
        let lastRange = (text as NSString).range(of: "最后一段😀")
        let last = Comment(location: lastRange.location, length: lastRange.length, quote: "旧引文", body: "补充验收标准")
        let output = FeedbackExporter.export(text: text, comments: [last, first], general: " 控制范围 ")
        let expected = """
        以下是我对你方案的逐条反馈，请据此修改出下一版：

        1. 原文：
           > 第一行
           > 第二行
           意见：请简化
           保留重点

        2. 原文：
           > 最后一段😀
           意见：补充验收标准

        总体意见：控制范围
        """
        check(output == expected, "exact output, document order, multiline indentation, current quotes, emoji")
        check(!FeedbackExporter.export(text: text, comments: [first], general: " \n").contains("总体意见"), "omit blank general")
        let stale = Comment(location: 999, length: 3, quote: "缓存\r\n原文", body: "意见\r\n续行")
        check(FeedbackExporter.export(text: text, comments: [stale], general: "").contains("   > 缓存\n   > 原文\n   意见：意见\n   续行"), "fallback quote and normalized newlines")
        let range = NSRange(location: 5, length: 5)
        check(CommentRanges.adjusted(range, replacing: NSRange(location: 2, length: 0), withLength: 2) == NSRange(location: 7, length: 5), "insert before")
        check(CommentRanges.adjusted(range, replacing: NSRange(location: 5, length: 0), withLength: 2) == NSRange(location: 7, length: 5), "insert at start")
        check(CommentRanges.adjusted(range, replacing: NSRange(location: 7, length: 0), withLength: 2) == NSRange(location: 5, length: 7), "insert inside")
        check(CommentRanges.adjusted(range, replacing: NSRange(location: 10, length: 0), withLength: 2) == range, "insert at end")
        check(CommentRanges.adjusted(range, replacing: NSRange(location: 0, length: 2), withLength: 0) == NSRange(location: 3, length: 5), "delete before")
        check(CommentRanges.adjusted(range, replacing: NSRange(location: 6, length: 2), withLength: 0) == NSRange(location: 5, length: 3), "delete inside")
        check(CommentRanges.adjusted(range, replacing: NSRange(location: 3, length: 4), withLength: 0) == NSRange(location: 3, length: 3), "delete across start")
        check(CommentRanges.adjusted(range, replacing: NSRange(location: 8, length: 4), withLength: 0) == NSRange(location: 5, length: 3), "delete across end")
        check(CommentRanges.adjusted(range, replacing: NSRange(location: 4, length: 7), withLength: 0) == nil, "fully deleted comment")
        check(CommentRanges.adjusted(range, replacing: NSRange(location: 6, length: 2), withLength: 4) == NSRange(location: 5, length: 7), "replace inside")
        check(CommentRanges.valid(lastRange, in: text), "UTF-16 range")
        check(!CommentRanges.valid(NSRange(location: Int.max, length: 1), in: text), "reject invalid range without overflow")
        let demo = Demo.session
        check(demo.comments.count == 3 && demo.comments.allSatisfy { CommentRanges.valid($0.range, in: demo.text) && (demo.text as NSString).substring(with: $0.range) == $0.quote }, "demo quotes match")
        do {
            let restored = try JSONDecoder().decode(Session.self, from: JSONEncoder().encode(demo))
            check(restored.text == demo.text && restored.comments == demo.comments && restored.general == demo.general, "JSON round trip")
        } catch { check(false, "JSON round trip: \(error)") }

        // Isolated session and pasteboard keep self-tests away from the user's data.
        let store = SessionStore(session: Session(text: text, comments: [first, last]))
        store.selection = first.range
        check(!store.canAdd, "exact saved range hides add action")
        store.selection = NSRange(location: 1, length: 2)
        check(store.canAdd, "partial overlap with saved comment still allows a new comment")
        store.addComment()
        check(!store.canAdd, "draft selection hides add action")
        store.selection = NSRange(location: 2, length: 2)
        check(!store.canAdd, "overlapping draft selection hides add action")
        store.draftBody = " 新意见 "
        let navigation = store.navigationRequest
        store.saveDraft()
        check(store.selection == NSRange(location: 4, length: 0) && store.navigationRequest != navigation,
              "save collapses selection to its end and requests native editor update")
        check(store.draft == nil && store.comments.count == 3 && store.comments.last?.body == "新意见",
              "save persists trimmed draft")
        store.edit(first)
        store.draftBody = "已修改"
        store.saveDraft()
        check(store.comments.count == 3 && store.comments.first?.body == "已修改", "edit updates existing comment")

        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        store.comments.append(Comment(location: 0, length: 1, quote: "第", body: "第四条"))
        store.general = " 总体意见 "
        store.copyFeedback(to: pasteboard)
        check(store.toast == "已复制 4 条批注到剪贴板（含总体意见）", "general opinion does not inflate comment count")
        check(pasteboard.string(forType: .string) == store.exported, "clipboard keeps exact export format")
        store.general = " \n"
        store.copyFeedback(to: pasteboard)
        check(store.toast == "已复制 4 条批注到剪贴板", "blank general omits suffix")
        store.comments = []
        let clipboard = pasteboard.string(forType: .string)
        let changeCount = pasteboard.changeCount
        store.copyFeedback(to: pasteboard)
        check(store.toast == "还没有批注" && pasteboard.changeCount == changeCount
              && pasteboard.string(forType: .string) == clipboard, "empty export preserves clipboard")
        store.general = "只导出总体意见"
        store.copyFeedback(to: pasteboard)
        check(store.toast == "已复制 0 条批注到剪贴板（含总体意见）"
              && pasteboard.string(forType: .string) == store.exported, "general-only feedback can be copied")

        let trailing = Comment(location: 0, length: 4, quote: "", body: "意见")
        check(!FeedbackExporter.export(text: "第一行\n", comments: [trailing], general: "").contains("   > \n"),
              "selection past a line end leaves no empty quote line")
        check(CommentRanges.trimmed(NSRange(location: 0, length: 6), in: " 第一行\n\n") == NSRange(location: 1, length: 3),
              "new comments trim surrounding whitespace")
        check(CommentRanges.trimmed(NSRange(location: 0, length: 2), in: " \n第") == nil, "whitespace-only selection cannot be commented")

        // Inline markers sit on the last visible character and never change the text.
        let markerText = "保留重点  \n下一段😀"
        check(CommentRanges.markerRange(of: NSRange(location: 0, length: 7), in: markerText) == NSRange(location: 3, length: 1),
              "marker skips trailing whitespace")
        let emoji = (markerText as NSString).range(of: "😀")
        check(CommentRanges.markerRange(of: NSRange(location: 8, length: NSMaxRange(emoji) - 8), in: markerText) == emoji,
              "marker covers a whole emoji")
        let sameEnd = [Comment(location: 0, length: 4, quote: "", body: "a"), Comment(location: 2, length: 2, quote: "", body: "b")]
        check(MarkdownStyler.markerCounts(sameEnd, in: markerText) == [NSRange(location: 3, length: 1): 2],
              "comments ending together share one kerned marker slot")
        check(CommentRanges.markerRange(of: NSRange(location: 0, length: 6), in: "**粗体**", hidden: IndexSet([0, 1, 4, 5]))
              == NSRange(location: 3, length: 1), "marker skips hidden markdown syntax")

        // Review mode: the agent gets the export, or an explicit approval when there is nothing to say.
        let reviewStore = SessionStore(session: Session(text: text))
        check(!reviewStore.hasFeedback && reviewStore.submission == ReviewRequest.approval, "empty review submits approval")
        reviewStore.general = "范围再收一收"
        check(reviewStore.submission == reviewStore.exported, "general-only review submits the export")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("loop-selftest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let plan = folder.appendingPathComponent("方案.md")
            let out = folder.appendingPathComponent("feedback.txt")
            try text.write(to: plan, atomically: true, encoding: .utf8)
            let request = try ReviewRequest.parse(["Loop", "--review", plan.path, "--out", out.path])
            check(request?.text == text && request?.output == out.standardizedFileURL && request?.title == "方案.md",
                  "parse review arguments")
            let normal = try ReviewRequest.parse(["Loop"])
            check(normal == nil, "no review flag means normal mode")
            check((try? ReviewRequest.parse(["Loop", "--review"])) == nil, "missing review path is rejected")
            check((try? ReviewRequest.parse(["Loop", "--review", folder.appendingPathComponent("无").path])) == nil,
                  "unreadable plan is rejected")
            let again = try ReviewRequest.parse(["Loop", "--review", plan.path])
            check(request?.draftURL == again?.draftURL, "draft key depends only on plan text")
            try request?.deliver("反馈")
            let delivered = try String(contentsOf: out, encoding: .utf8)
            check(delivered == "反馈\n", "deliver writes feedback file")
        } catch { check(false, "review request: \(error)") }

        print(output)
        print("\nSELFTEST PASSED (\(checks) checks)")
    }
}
