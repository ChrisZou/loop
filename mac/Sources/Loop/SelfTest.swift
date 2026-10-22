import AppKit
import SwiftUI

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

        // Tables: one NSTextTable cell per markdown cell, while ranges, quotes and copies stay on the markdown.
        let table = """
        前言
        | 周 | 日期 | 备注 |
        | --- | :---: | ---: |
        | W0 | 10/21 | **加粗** \\| 竖线 |
        | W1 | 10/28 |

        后记 | 不是表格
        """
        let source = table as NSString
        let tableStorage = NSTextStorage(string: table)
        let tableHidden = MarkdownStyler.apply(to: tableStorage, comments: [])
        let display = tableStorage.string as NSString
        func cell(_ text: String) -> NSTextTableBlock? {
            (tableStorage.attribute(.paragraphStyle, at: source.range(of: text).location, effectiveRange: nil) as? NSParagraphStyle)?
                .textBlocks.first as? NSTextTableBlock
        }
        func alignment(_ text: String) -> NSTextAlignment? {
            (tableStorage.attribute(.paragraphStyle, at: source.range(of: text).location, effectiveRange: nil) as? NSParagraphStyle)?.alignment
        }
        check(display.length == source.length, "table swaps keep every index")
        check(cell("日期").map { ($0.startingRow, $0.startingColumn, $0.table.numberOfColumns) } ?? (-1, -1, -1) == (0, 1, 3)
              && cell("W1").map { ($0.startingRow, $0.startingColumn) } ?? (-1, -1) == (2, 0),
              "each markdown cell is its own table cell, the |---| row is not a row")
        check(alignment("10/21") == .center && alignment("竖线") == .right, "delimiter colons set column alignment")
        let firstPipe = source.range(of: "周 |").location + 2
        check(display.character(at: firstPipe) == 0x2029 && tableHidden.contains(firstPipe), "a pipe between cells becomes a paragraph break")
        let delimiter = source.range(of: "| --- | :---: | ---: |")
        check(tableHidden.contains(integersIn: delimiter.location..<NSMaxRange(delimiter)), "the |---| row is hidden")
        let after = source.range(of: "后记 | 不是表格")
        check(cell("后记") == nil && !tableHidden.contains(after.location + 3), "a pipe line without a header stays text")
        let fenced = NSTextStorage(string: "```\n| a | b |\n| --- | --- |\n```")
        MarkdownStyler.apply(to: fenced, comments: [])
        check((fenced.attribute(.paragraphStyle, at: 5, effectiveRange: nil) as? NSParagraphStyle)?.textBlocks.isEmpty != false,
              "a table inside a code block stays code")
        let acrossCells = NSRange(location: source.range(of: "W0").location,
                                  length: NSMaxRange(source.range(of: "10/21")) - source.range(of: "W0").location)
        check(CommentRanges.visibleText(of: acrossCells, in: table, hidden: tableHidden) == "W0 | 10/21",
              "a quote across cells keeps them apart")
        let escaped = NSRange(location: source.range(of: "**加粗**").location,
                              length: NSMaxRange(source.range(of: "竖线")) - source.range(of: "**加粗**").location)
        check(CommentRanges.visibleText(of: escaped, in: table, hidden: tableHidden) == "加粗 | 竖线", "an escaped pipe shows as a pipe")

        let dateComment = Comment(location: source.range(of: "10/21").location, length: 5, quote: "10/21", body: "提前")
        let tableStore = reviewing(Session(text: table, comments: [dateComment]))
        tableStore.selection = acrossCells
        tableStore.addComment()
        check(tableStore.draft?.quote == "W0 | 10/21", "a new comment across cells quotes both")
        tableStore.cancelDraft()
        let tableEditor = EditorContainer(frame: NSRect(x: 0, y: 0, width: 900, height: 500))
        let tableWindow = NSWindow(contentRect: tableEditor.frame, styleMask: [.titled], backing: .buffered, defer: true)
        tableWindow.contentView = tableEditor
        let tableCoordinator = DocumentEditor.Coordinator(tableStore)
        tableCoordinator.container = tableEditor
        tableEditor.textView.string = table
        tableEditor.textView.source = source
        tableCoordinator.styleIfNeeded()
        tableEditor.layoutSubtreeIfNeeded()
        tableCoordinator.layoutMarkers()
        func tableCenter(of text: String) -> NSPoint {
            guard let manager = tableEditor.textView.layoutManager, let container = tableEditor.textView.textContainer else { return .zero }
            let glyphs = manager.glyphRange(forCharacterRange: NSRange(location: source.range(of: text).location, length: 1),
                                            actualCharacterRange: nil)
            let rect = manager.boundingRect(forGlyphRange: glyphs, in: container)
            let origin = tableEditor.textView.textContainerOrigin
            return NSPoint(x: rect.midX + origin.x, y: rect.midY + origin.y)
        }
        let headers = ["周", "日期", "备注"].map(tableCenter)
        check(abs(headers[0].y - headers[2].y) < 1 && headers[0].x < headers[1].x && headers[1].x < headers[2].x,
              "a row's cells sit side by side")
        tableCoordinator.hoverText(at: tableCenter(of: "10/21"))
        check(tableStore.activeID == dateComment.id, "hovering a commented cell previews its comment")
        tableEditor.textView.setSelectedRange(acrossCells)
        let board = NSPasteboard(name: NSPasteboard.Name("loop-selftest-\(UUID().uuidString)"))
        _ = tableEditor.textView.writeSelection(to: board, types: [.string])
        check(board.string(forType: .string) == "W0 | 10/21", "copying cells copies their markdown")
        board.releaseGlobally()

        // Task items: the reviewer's ticks are feedback; the plan itself never changes.
        let todo = "- [ ] 定资金止损线 N\n- [x] 通知厂商\n- [ ] **我来做** 加检查\n后记\n"
        let todoSource = todo as NSString
        let todoStore = reviewing(Session(text: todo))
        check(todoStore.tasks.map(\.text) == ["定资金止损线 N", "通知厂商", "我来做 加检查"]
              && todoStore.tasks.map(\.checked) == [false, true, false], "task items and their ticks are found")
        check(todoStore.hidden.contains(integersIn: 0..<6) && !todoStore.hidden.contains(6), "`- [ ] ` is hidden")
        todoStore.toggleTask(at: todoStore.tasks[0].location)
        todoStore.toggleTask(at: todoStore.tasks[1].location)
        check(todoStore.hasFeedback && todoStore.isChecked(todoStore.tasks[0]) && !todoStore.isChecked(todoStore.tasks[1]),
              "clicking flips a box")
        check(todoStore.exported == "以下是我对你方案的逐条反馈，请据此修改出下一版：\n\n待办的勾选状态改为：\n- [x] 定资金止损线 N\n- [ ] 通知厂商",
              "changed ticks are exported with their new state")
        todoStore.toggleTask(at: todoStore.tasks[1].location)
        check(todoStore.toggled == [todoStore.tasks[0].location], "clicking again changes a box back")
        let ticked = Session(text: todo, toggled: [todoStore.tasks[0].location, 1])
        let reloaded = (try? JSONEncoder().encode(ticked)).flatMap { try? JSONDecoder().decode(Session.self, from: $0) }
        check(reloaded.map { reviewing($0).toggled } == [todoStore.tasks[0].location], "ticks survive in the draft, stale ones are dropped")

        let todoEditor = EditorContainer(frame: NSRect(x: 0, y: 0, width: 900, height: 400))
        let todoWindow = NSWindow(contentRect: todoEditor.frame, styleMask: [.titled], backing: .buffered, defer: true)
        todoWindow.contentView = todoEditor
        let todoCoordinator = DocumentEditor.Coordinator(todoStore)
        todoCoordinator.container = todoEditor
        todoEditor.textView.string = todo
        todoEditor.textView.onToggleTask = { todoStore.toggleTask(at: $0) }
        todoCoordinator.styleIfNeeded()
        todoEditor.layoutSubtreeIfNeeded()
        if let manager = todoEditor.textView.layoutManager {
            // The last item is followed by plain text, which never lost its spacing.
            let heights = ["定资金", "加检查"].map {
                manager.lineFragmentRect(forGlyphAt: manager.glyphIndexForCharacter(at: todoSource.range(of: $0).location),
                                         effectiveRange: nil).height
            }
            check(heights[0] == heights[1], "an item followed by another keeps its spacing")
        }
        let third = todoStore.tasks[2]
        if let box = todoEditor.textView.taskBoxes.first(where: { $0.location == third.location }),
           let frame = todoEditor.textView.taskRect(box),
           let event = NSEvent.mouseEvent(with: .leftMouseDown, location: todoEditor.textView.convert(NSPoint(x: frame.midX, y: frame.midY), to: nil),
                                          modifierFlags: [], timestamp: 0, windowNumber: todoWindow.windowNumber, context: nil,
                                          eventNumber: 0, clickCount: 1, pressure: 1),
           todoEditor.textView.taskBox(at: NSPoint(x: frame.midX, y: frame.midY)) == box {
            todoEditor.textView.mouseDown(with: event)
            check(todoStore.isChecked(third), "clicking a checkbox in the editor ticks it")
            check(todoEditor.textView.taskBox(at: NSPoint(x: frame.maxX + 40, y: frame.midY)) == nil, "the item's text is not the box")
        } else {
            check(false, "checkbox is laid out where it can be clicked")
        }

        // Placeholders give way to pinyin still being composed, which SwiftUI keeps out of the binding until a
        // candidate is picked. Rendered offscreen and read back: the placeholder's run must be blank while composing.
        func composing<Content: View>(_ content: Content, size: NSSize, label: String, draft: () -> String) {
            let host = NSHostingView(rootView: content)
            host.frame = NSRect(origin: .zero, size: size)
            let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
            window.contentView = host
            func settle() { RunLoop.current.run(until: Date().addingTimeInterval(0.15)) }
            func editor(in view: NSView) -> NSTextView? {
                if let text = view as? NSTextView, text.isEditable { return text }
                return view.subviews.lazy.compactMap(editor).first
            }
            settle()
            guard let field = editor(in: host) else { return check(false, "\(label): editor is hosted") }
            window.makeFirstResponder(field)
            settle()
            // Past where three letters of pinyin end, on the first line: where the placeholder runs on.
            let line = host.convert(field.bounds, from: field)
            let run = NSRect(x: line.minX + 50, y: line.minY + 2, width: 60, height: 16)
            func placeholderShows() -> Bool {
                guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return false }
                host.cacheDisplay(in: host.bounds, to: rep)
                let scale = CGFloat(rep.pixelsWide) / host.bounds.width
                for y in stride(from: run.minY, to: run.maxY, by: 0.5) {
                    for x in stride(from: run.minX, to: run.maxX, by: 0.5) {
                        let row = host.isFlipped ? y : host.bounds.height - y
                        if let color = rep.colorAt(x: Int(x * scale), y: Int(row * scale))?.usingColorSpace(.sRGB),
                           color.brightnessComponent < 0.8 { return true }
                    }
                }
                return false
            }
            check(placeholderShows(), "\(label): placeholder shows while empty")
            field.setMarkedText("xin", selectedRange: NSRange(location: 3, length: 0),
                                replacementRange: NSRange(location: NSNotFound, length: 0))
            settle()
            check(draft().isEmpty && !placeholderShows(), "\(label): composing pinyin hides the placeholder")
            field.setMarkedText("", selectedRange: NSRange(location: 0, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
            field.unmarkText()
            settle()
            check(placeholderShows(), "\(label): dropping the composition brings the placeholder back")
            field.setMarkedText("xin", selectedRange: NSRange(location: 3, length: 0),
                                replacementRange: NSRange(location: NSNotFound, length: 0))
            field.insertText("新", replacementRange: field.markedRange())
            settle()
            check(draft() == "新" && !placeholderShows(), "\(label): picking a candidate keeps it hidden")
        }
        let barStore = reviewing(Session(text: text))
        composing(FeedbackBar(store: barStore), size: NSSize(width: 700, height: 120), label: "总评") { barStore.generalDraft }
        let cardStore = reviewing(Session(text: text))
        cardStore.selection = NSRange(location: 0, length: 3)
        cardStore.addComment()
        composing(CommentEditorCard(store: cardStore, number: 1), size: NSSize(width: 340, height: 220), label: "批注") {
            cardStore.draftBody
        }

        // Images: each goes into the feedback as a path the agent can open.
        let pictured = FeedbackExporter.export(text: text, comments: [
            Comment(location: 0, length: 3, quote: "", body: "看图", images: ["/x/1.png"]),
            Comment(location: 4, length: 3, quote: "", body: " ", images: ["/x/2.png", "/x/3.png"])
        ], generals: [GeneralNote(text: "范围再收", images: ["/x/4.png"]), GeneralNote(text: " ", images: ["/x/5.png"])])
        check(pictured == """
        以下是我对你方案的逐条反馈，请据此修改出下一版：
        （「附图」是本机上的图片文件，请打开查看。）

        1. 原文：
           > 第一行
           意见：看图
           附图：/x/1.png

        2. 原文：
           > 第二行
           附图：/x/2.png
           附图：/x/3.png

        总体意见：
        1. 范围再收
           附图：/x/4.png
        2. 附图：/x/5.png
        """, "images export as 附图 paths, after the comment or note they belong to")
        check(FeedbackExporter.export(text: text, comments: [], generals: [GeneralNote(text: "", images: ["/x/5.png"])])
              .hasSuffix("总体意见：\n附图：/x/5.png"), "a 总评 of only an image")
        let plainNotes = (try? JSONEncoder().encode(Session(text: "a", generals: ["只有字"]))).map { String(decoding: $0, as: UTF8.self) }
        check(plainNotes?.contains(#""generals":["只有字"]"#) == true, "notes without images save as plain strings, as before")
        let withImages = Session(text: "a", comments: [Comment(location: 0, length: 1, quote: "a", body: "", images: ["/x/1.png"])],
                                 generals: [GeneralNote(text: "看图", images: ["/x/2.png"])])
        let reread = (try? JSONEncoder().encode(withImages)).flatMap { try? JSONDecoder().decode(Session.self, from: $0) }
        check(reread?.comments == withImages.comments && reread?.generals == withImages.generals, "images survive in the draft")
        let oldComment = try? JSONDecoder().decode(Session.self, from: Data(
            #"{"text":"abc","comments":[{"id":"7D0B2A52-5B8E-4E59-9C1E-1D4B8E9E0A11","location":0,"length":1,"quote":"a","body":"旧"}],"generals":["旧"]}"#.utf8))
        check(oldComment?.comments.first?.images == [] && oldComment?.generals == ["旧"], "drafts from before images still load")

        let images = NSPasteboard(name: NSPasteboard.Name("loop-selftest-\(UUID().uuidString)"))
        defer { images.releaseGlobally() }
        let pixel = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 3, bitsPerSample: 8, samplesPerPixel: 4,
                                     hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let png = pixel.representation(using: .png, properties: [:])!
        let imageStore = reviewing(Session(text: text))
        defer { try? FileManager.default.removeItem(at: imageStore.attachmentFolder) }
        imageStore.selection = NSRange(location: 0, length: 3)
        imageStore.addComment()
        images.clearContents()
        images.setData(png, forType: .png)
        check(imageStore.pasteImages(from: images, to: .comment) && imageStore.draftImages.count == 1
              && imageStore.draftImages[0].hasPrefix(imageStore.attachmentFolder.path) && imageStore.draftImages[0].hasSuffix(".png")
              && FileManager.default.contents(atPath: imageStore.draftImages[0]) == png, "pasting a screenshot saves it into the review's folder")
        images.clearContents()
        images.setData(pixel.tiffRepresentation!, forType: .tiff)
        check(imageStore.pasteImages(from: images, to: .comment) && imageStore.draftImages.last?.hasSuffix(".png") == true,
              "a TIFF on the pasteboard is saved as PNG")
        images.clearContents()
        images.setString("一段文字", forType: .string)
        check(!imageStore.pasteImages(from: images, to: .comment) && imageStore.draftImages.count == 2, "pasting text is left to the editor")
        let loose = FileManager.default.temporaryDirectory.appendingPathComponent("loop-selftest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: loose) }
        try? FileManager.default.createDirectory(at: loose, withIntermediateDirectories: true)
        let photo = loose.appendingPathComponent("照片.jpg")
        let note = loose.appendingPathComponent("说明.txt")
        try? pixel.representation(using: .jpeg, properties: [:])?.write(to: photo)
        try? "不是图片".write(to: note, atomically: true, encoding: .utf8)
        images.clearContents()
        images.writeObjects([photo as NSURL])
        check(imageStore.pasteImages(from: images, to: .comment) && imageStore.draftImages.last?.hasSuffix(".jpeg") == true,
              "a copied image file is attached as a copy")
        imageStore.attachImages(files: [note], to: .comment)
        check(imageStore.draftImages.count == 3, "files that are not images are ignored")
        imageStore.saveDraft()
        check(imageStore.comments.last?.images.count == 3 && imageStore.comments.last?.body == "", "a comment can be just images")
        if let saved = imageStore.comments.last {
            imageStore.edit(saved)
            imageStore.removeImage(saved.images[0], from: .comment)
            imageStore.cancelDraft()
            check(imageStore.comments.last?.images == saved.images, "removing an image and cancelling keeps the saved comment")
        }
        imageStore.composingGeneral = true
        imageStore.attachImages(files: [photo], to: .general)
        check(imageStore.canCommitShortcut, "an image alone can be filed as a 总评")
        imageStore.commitShortcut()
        check(imageStore.generals.last?.text == "" && imageStore.generals.last?.images.count == 1 && imageStore.generalImages.isEmpty,
              "⌘↩ files the composer's images with its text")
        imageStore.editGeneral(at: 0)
        check(imageStore.generalImages.count == 1, "changing a 总评 brings its images back into the composer")
        imageStore.cancelGeneral()

        // ⌘V and drag-and-drop through the real card in a window.
        Attachments.pasteboard = images
        defer { Attachments.pasteboard = .general }
        let pasteStore = reviewing(Session(text: text))
        defer { try? FileManager.default.removeItem(at: pasteStore.attachmentFolder) }
        pasteStore.selection = NSRange(location: 0, length: 3)
        pasteStore.addComment()
        let holder = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 500))
        let pasteWindow = NSWindow(contentRect: holder.frame, styleMask: [.titled], backing: .buffered, defer: false)
        pasteWindow.contentView = holder
        let card = CardView(rootView: AnyView(EmptyView()))
        holder.addSubview(card)
        card.show(CommentEditorCard(store: pasteStore, number: 1), below: NSRect(x: 300, y: 420, width: 1, height: 16), in: holder)
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        func cardEditor(in view: NSView) -> NSTextView? {
            if let text = view as? NSTextView, text.isEditable { return text }
            return view.subviews.lazy.compactMap(cardEditor).first
        }
        let before = card.frame.height
        if let field = cardEditor(in: card) {
            pasteWindow.makeFirstResponder(field)
            check(!field.registeredDraggedTypes.contains(.fileURL), "image files dropped on the text go to the card, not in as paths")
            images.clearContents()
            images.setData(png, forType: .png)
            let commandV = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
                                            windowNumber: pasteWindow.windowNumber, context: nil, characters: "v",
                                            charactersIgnoringModifiers: "v", isARepeat: false, keyCode: 9)!
            NSApp.sendEvent(commandV)
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
            check(pasteStore.draftImages.count == 1 && field.string.isEmpty, "⌘V in the card attaches a screenshot")
            check(card.frame.height > before + 40, "the card grows to show the image")
        } else {
            check(false, "the card's editor is hosted")
        }

        let pruneRoot = loose.appendingPathComponent("support")
        let monthAgo = Date(timeIntervalSinceNow: -40 * 24 * 3600)
        for name in ["old", "kept", "fresh"] {
            let folder = pruneRoot.appendingPathComponent("attachments/\(name)")
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if name != "fresh" { try? FileManager.default.setAttributes([.modificationDate: monthAgo], ofItemAtPath: folder.path) }
        }
        try? FileManager.default.createDirectory(at: pruneRoot.appendingPathComponent("reviews"), withIntermediateDirectories: true)
        try? Data("{}".utf8).write(to: pruneRoot.appendingPathComponent("reviews/kept.json"))
        Attachments.prune(pruneRoot)
        let left = (try? FileManager.default.contentsOfDirectory(atPath: pruneRoot.appendingPathComponent("attachments").path))?.sorted()
        check(left == ["fresh", "kept"], "old images go once their review is over for 30 days")

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
