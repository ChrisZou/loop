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
        check(CommentRanges.valid(lastRange, in: text), "UTF-16 range")
        check(!CommentRanges.valid(NSRange(location: Int.max, length: 1), in: text), "reject invalid range without overflow")
        let demo = Demo.session
        check(demo.comments.count == 3 && demo.comments.allSatisfy { CommentRanges.valid($0.range, in: demo.text) && (demo.text as NSString).substring(with: $0.range) == $0.quote }, "demo quotes match")
        do {
            let restored = try JSONDecoder().decode(Session.self, from: JSONEncoder().encode(demo))
            check(restored.text == demo.text && restored.comments == demo.comments && restored.generals == demo.generals, "JSON round trip")
        } catch { check(false, "JSON round trip: \(error)") }

        // Restored sessions are never saved, which keeps self-tests away from the user's drafts.
        func reviewing(_ session: Session) -> SessionStore {
            SessionStore(review: ReviewRequest(source: URL(fileURLWithPath: "方案.md"), output: nil, text: session.text),
                         restoring: session)
        }
        let store = reviewing(Session(text: text, comments: [first, last]))
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

        let trailing = Comment(location: 0, length: 4, quote: "", body: "意见")
        check(!FeedbackExporter.export(text: "第一行\n", comments: [trailing], general: "").contains("   > \n"),
              "selection past a line end leaves no empty quote line")
        check(CommentRanges.trimmed(NSRange(location: 0, length: 6), in: " 第一行\n\n") == NSRange(location: 1, length: 3),
              "new comments trim surrounding whitespace")
        check(CommentRanges.trimmed(NSRange(location: 0, length: 2), in: " \n第") == nil, "whitespace-only selection cannot be commented")
        check(CommentRanges.trimmed(NSRange(location: 0, length: 6), in: "**粗体**", hidden: IndexSet([0, 1, 4, 5]))
              == NSRange(location: 2, length: 2), "new comments trim hidden markdown at the edges")
        let literal = "保留？** 普通，多出来的 `**` 是"
        let literalCode = (literal as NSString).range(of: "`**`")
        check(MarkdownStyler.apply(to: NSTextStorage(string: literal), comments: [])
              == IndexSet([literalCode.location, NSMaxRange(literalCode) - 1]), "literal ** in prose and code spans is not bold")
        check(MarkdownStyler.apply(to: NSTextStorage(string: "**粗体** 和 `代码`"), comments: [])
              == IndexSet([0, 1, 4, 5, 9, 12]), "bold and code spans still hide their markers")
        let across = Comment(location: 2, length: 6, quote: "", body: "意见")
        check(FeedbackExporter.export(text: "**粗体**后文", comments: [across], general: "", hidden: IndexSet([0, 1, 4, 5]))
              .contains("   > 粗体后文\n"), "quotes leave out hidden markdown inside the selection")

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

        // Hover previews, driven through the editor's own hit testing in an offscreen window.
        _ = NSApplication.shared
        let hoverText = "前言部分，被批注的原文，结尾"
        let outer = Comment(location: 5, length: 6, quote: "", body: "外层")
        let inner = Comment(location: 8, length: 3, quote: "", body: "内层")
        let hoverStore = reviewing(Session(text: hoverText, comments: [outer, inner]))
        let editor = EditorContainer(frame: NSRect(x: 0, y: 0, width: 900, height: 400))
        let window = NSWindow(contentRect: editor.frame, styleMask: [.titled], backing: .buffered, defer: true)
        window.contentView = editor
        let coordinator = DocumentEditor.Coordinator(hoverStore)
        coordinator.container = editor
        editor.textView.string = hoverText
        coordinator.styleIfNeeded()
        editor.layoutSubtreeIfNeeded()
        coordinator.layoutMarkers()
        func center(of index: Int) -> NSPoint {
            guard let manager = editor.textView.layoutManager, let container = editor.textView.textContainer else { return .zero }
            let glyphs = manager.glyphRange(forCharacterRange: NSRange(location: index, length: 1), actualCharacterRange: nil)
            let rect = manager.boundingRect(forGlyphRange: glyphs, in: container)
            let origin = editor.textView.textContainerOrigin
            return NSPoint(x: rect.midX + origin.x, y: rect.midY + origin.y)
        }
        coordinator.hoverText(at: center(of: 6))
        check(hoverStore.activeID == outer.id, "hovering highlighted text previews its comment")
        coordinator.hoverText(at: center(of: 9))
        check(hoverStore.activeID == inner.id, "nested highlights preview the innermost comment")
        coordinator.hoverText(at: center(of: 1))
        check(hoverStore.activeID == nil, "plain text closes the preview")
        coordinator.hoverText(at: center(of: 9))
        coordinator.hoverText(at: NSPoint(x: center(of: 13).x + 200, y: center(of: 13).y))
        check(hoverStore.activeID == nil, "blank space after the line closes the preview")
        coordinator.hoverText(at: center(of: 6))
        coordinator.endHover()
        check(hoverStore.activeID == nil, "scrolling closes the preview")

        // Review mode: the agent gets the export, or an explicit approval when there is nothing to say.
        let reviewStore = reviewing(Session(text: text))
        check(!reviewStore.hasFeedback && reviewStore.submission == ReviewRequest.approval, "empty review submits approval")
        reviewStore.composingGeneral = true
        reviewStore.generalDraft = "  范围再收一收 \n"
        check(!reviewStore.hasFeedback, "a 总评 still being written is not feedback until saved")
        reviewStore.commitShortcut()
        check(reviewStore.generals == ["范围再收一收"] && reviewStore.generalDraft.isEmpty,
              "⌘↩ files the 总评, trimmed, and empties the composer")
        reviewStore.generalDraft = "标签放到第二版"
        reviewStore.commitShortcut()
        reviewStore.editGeneral(at: 0)
        reviewStore.generalDraft = "范围再收"
        reviewStore.commitShortcut()
        check(reviewStore.generals == ["范围再收", "标签放到第二版"], "changing a 总评 keeps its place")
        reviewStore.editGeneral(at: 1)
        reviewStore.generalDraft = "改了又不要"
        reviewStore.cancelGeneral()
        check(reviewStore.generals.count == 2 && reviewStore.editingGeneral == nil && reviewStore.generalDraft.isEmpty,
              "Esc leaves saved 总评 untouched")
        check(reviewStore.exported.hasSuffix("总体意见：\n1. 范围再收\n2. 标签放到第二版"), "several 总评 are numbered")
        let legacy = try? JSONDecoder().decode(Session.self, from: Data(#"{"text":"a","comments":[],"general":"旧总评"}"#.utf8))
        check(legacy?.generals == ["旧总评"], "drafts with a single general opinion still load")
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
