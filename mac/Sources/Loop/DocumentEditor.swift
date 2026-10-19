import SwiftUI
import AppKit

final class PlanTextView: NSTextView {
    override func paste(_ sender: Any?) { pasteAsPlainText(sender) }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty else { return }
        let placeholder = "在此粘贴 AI 生成的方案 / 计划…\n选中文字后按 ⌘↩ 或点击「批注」添加意见，⇧⌘C 一键导出反馈。"
        let origin = textContainerOrigin
        (placeholder as NSString).draw(
            with: NSRect(x: origin.x, y: origin.y,
                         width: max(0, bounds.width - origin.x - textContainerInset.width),
                         height: max(0, bounds.height - origin.y)),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: MarkdownStyler.bodyFont,
                         .foregroundColor: NSColor.secondaryLabelColor,
                         .paragraphStyle: MarkdownStyler.paragraph]
        )
    }

    override func didChangeText() {
        super.didChangeText()
        needsDisplay = true
    }

    /// Code cards and quote bars, drawn beneath highlights and text.
    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard let storage = textStorage, let manager = layoutManager, let container = textContainer else { return }
        let origin = textContainerOrigin
        storage.enumerateAttribute(.loopBlock, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard let kind = (value as? String).flatMap(MarkdownStyler.Block.init) else { return }
            var used = NSRect.null
            let glyphs = manager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            manager.enumerateLineFragments(forGlyphRange: glyphs) { _, usedRect, _, _, _ in used = used.union(usedRect) }
            guard !used.isNull else { return }
            let block = NSRect(x: origin.x, y: used.minY + origin.y, width: container.size.width, height: used.height)
            guard block.intersects(rect) else { return }
            switch kind {
            case .code:
                NSColor.labelColor.withAlphaComponent(0.045).setFill()
                NSBezierPath(roundedRect: block, xRadius: 8, yRadius: 8).fill()
            case .quote:
                MarkdownStyler.accent.withAlphaComponent(0.35).setFill()
                NSBezierPath(roundedRect: NSRect(x: block.minX + 2, y: block.minY + 2, width: 3, height: block.height - 4),
                             xRadius: 1.5, yRadius: 1.5).fill()
            }
        }
    }
}

/// Numbered badge after a commented range's last character; hover previews the comment, click edits it.
/// The number matches the item's position in the exported feedback.
final class CommentMarker: NSView {
    static let size: CGFloat = 17
    let id: UUID
    var active = false { didSet { if active != oldValue { needsDisplay = true } } }
    var number = 0 { didSet { if number != oldValue { needsDisplay = true } } }
    var onHover: ((CommentMarker, Bool) -> Void)?
    var onPress: ((CommentMarker) -> Void)?

    init(id: UUID) {
        self.id = id
        super.init(frame: NSRect(x: 0, y: 0, width: Self.size, height: Self.size))
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                                       owner: self, userInfo: nil))
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
    override func mouseEntered(with event: NSEvent) { onHover?(self, true) }
    override func mouseExited(with event: NSEvent) { onHover?(self, false) }
    override func mouseDown(with event: NSEvent) { onPress?(self) }
    override func accessibilityPerformPress() -> Bool { onPress?(self); return true }

    override func draw(_ dirtyRect: NSRect) {
        let badge = NSBezierPath(ovalIn: bounds.insetBy(dx: 0.5, dy: 0.5))
        (active ? MarkdownStyler.accent : MarkdownStyler.accent.withAlphaComponent(0.78)).setFill()
        badge.fill()
        let label = "\(number)" as NSString
        var font = NSFont.systemFont(ofSize: number >= 10 ? 8.5 : 10.5, weight: .bold)
        if let rounded = font.fontDescriptor.withDesign(.rounded) { font = NSFont(descriptor: rounded, size: font.pointSize) ?? font }
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
        let size = label.size(withAttributes: attributes)
        label.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2),
                   withAttributes: attributes)
    }
}

final class EditorContainer: NSView {
    let scrollView = NSScrollView()
    let textView: PlanTextView
    let addButton = NSButton(title: "批注", target: nil, action: nil)
    private let markupDelegate = MarkupLayoutDelegate()
    var onAdd: (() -> Void)?
    var onLayout: (() -> Void)?
    var canAdd = false
    private var scrollObserver: NSObjectProtocol?
    private var frameObserver: NSObjectProtocol?

    override init(frame frameRect: NSRect) {
        let storage = NSTextStorage()
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        storage.addLayoutManager(manager)
        manager.addTextContainer(container)
        textView = PlanTextView(frame: .zero, textContainer: container)
        super.init(frame: frameRect)
        manager.delegate = markupDelegate
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.borderType = .noBorder
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 40, height: 44)
        textView.font = MarkdownStyler.bodyFont
        textView.typingAttributes = MarkdownStyler.base
        textView.backgroundColor = .textBackgroundColor
        textView.setAccessibilityLabel("方案正文")
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        scrollView.documentView = textView
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        addButton.bezelStyle = .push
        addButton.bezelColor = MarkdownStyler.accent
        addButton.controlSize = .regular
        addButton.image = NSImage(systemSymbolName: "text.bubble.fill", accessibilityDescription: nil)
        addButton.imagePosition = .imageLeading
        addButton.toolTip = "添加批注（⌘↩）"
        addButton.target = self
        addButton.action = #selector(addComment)
        addButton.isHidden = true
        addButton.sizeToFit()
        addSubview(addButton)
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification, object: scrollView.contentView, queue: .main
        ) { [weak self] _ in self?.positionButton() }
        // Rewrapping after a width change moves every marker.
        textView.postsFrameChangedNotifications = true
        frameObserver = NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification, object: textView, queue: .main
        ) { [weak self] _ in self?.onLayout?() }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit {
        for observer in [scrollObserver, frameObserver].compactMap({ $0 }) { NotificationCenter.default.removeObserver(observer) }
    }
    @objc private func addComment() { onAdd?() }

    override func layout() {
        super.layout()
        // Center a fixed reading column; wide windows get margins instead of long lines.
        let inset = max(40, floor((scrollView.contentSize.width - MarkdownStyler.columnWidth) / 2))
        if textView.textContainerInset.width != inset {
            textView.textContainerInset = NSSize(width: inset, height: textView.textContainerInset.height)
        }
        // Keep enough drawable space for the multiline placeholder in an empty document.
        textView.minSize = NSSize(width: 0, height: scrollView.contentSize.height)
        if textView.frame.height < scrollView.contentSize.height {
            textView.setFrameSize(NSSize(width: textView.frame.width, height: scrollView.contentSize.height))
        }
        textView.needsDisplay = true
        positionButton()
        onLayout?()
    }

    /// The last visible character of a range and its baseline, in text view coordinates.
    func markerPlacement(for range: NSRange, hidden: IndexSet) -> (rect: NSRect, baseline: CGFloat)? {
        guard let marker = CommentRanges.markerRange(of: range, in: textView.string, hidden: hidden),
              let manager = textView.layoutManager, let container = textView.textContainer else { return nil }
        let glyphs = manager.glyphRange(forCharacterRange: marker, actualCharacterRange: nil)
        guard glyphs.length > 0 else { return nil }
        let origin = textView.textContainerOrigin
        let rect = manager.boundingRect(forGlyphRange: glyphs, in: container).offsetBy(dx: origin.x, dy: origin.y)
        let last = NSMaxRange(glyphs) - 1
        let line = manager.lineFragmentRect(forGlyphAt: last, effectiveRange: nil)
        return (rect, origin.y + line.minY + manager.location(forGlyphAt: last).y)
    }

    func positionButton() {
        let selected = textView.selectedRange()
        guard canAdd, selected.length > 0, !textView.hasMarkedText(),
              let manager = textView.layoutManager, let container = textView.textContainer else {
            addButton.isHidden = true
            return
        }
        let tail = NSRange(location: NSMaxRange(selected) - 1, length: 1)
        let glyph = manager.glyphRange(forCharacterRange: tail, actualCharacterRange: nil)
        var rect = manager.boundingRect(forGlyphRange: glyph, in: container)
        rect.origin.x += textView.textContainerOrigin.x
        rect.origin.y += textView.textContainerOrigin.y
        guard textView.visibleRect.intersects(rect) else { addButton.isHidden = true; return }
        let anchor = convert(rect, from: textView)
        let width = max(80, addButton.frame.width)
        let height: CGFloat = 28
        // Prefer the right margin beside the selection's last line, where it never covers text.
        let columnRight = convert(NSPoint(x: textView.textContainerOrigin.x + container.size.width, y: 0), from: textView).x
        if bounds.width - columnRight >= width + 36 {
            addButton.frame = NSRect(x: columnRight + 20, y: max(8, min(bounds.height - height - 4, anchor.midY - height / 2)),
                                     width: width, height: height)
        } else {
            addButton.frame = NSRect(x: max(8, min(bounds.width - width - 18, anchor.maxX + 8)),
                                     y: max(8, min(bounds.height - height - 4, anchor.minY - height - 4)), width: width, height: height)
        }
        addButton.isHidden = false
    }
}

struct DocumentEditor: NSViewRepresentable {
    @ObservedObject var store: SessionStore

    func makeCoordinator() -> Coordinator { Coordinator(store) }
    func makeNSView(context: Context) -> EditorContainer {
        let view = EditorContainer(frame: .zero)
        view.textView.delegate = context.coordinator
        // A plan under review is the agent's text: comment on it, don't edit it.
        view.textView.isEditable = store.review == nil
        view.onAdd = { [weak store] in store?.addComment() }
        view.onLayout = { [weak coordinator = context.coordinator] in coordinator?.layoutMarkers() }
        context.coordinator.container = view
        return view
    }

    func updateNSView(_ view: EditorContainer, context: Context) {
        let coordinator = context.coordinator
        coordinator.updating = true
        defer { coordinator.updating = false }
        if view.textView.string != store.text {
            let oldSelection = view.textView.selectedRange()
            view.textView.string = store.text
            view.textView.needsDisplay = true
            let length = (store.text as NSString).length
            view.textView.setSelectedRange(NSRange(location: min(oldSelection.location, length), length: 0))
            view.textView.undoManager?.removeAllActions()
        }
        coordinator.styleIfNeeded()
        if coordinator.lastNavigation != store.navigationRequest {
            coordinator.lastNavigation = store.navigationRequest
            view.textView.setSelectedRange(store.selection)
            view.textView.scrollRangeToVisible(store.selection)
            view.window?.makeFirstResponder(view.textView)
        }
        view.canAdd = store.canAdd
        view.positionButton()
        coordinator.layoutMarkers()
        coordinator.syncEditorPopover()
    }

    final class Coordinator: NSObject, NSTextViewDelegate, NSPopoverDelegate {
        let store: SessionStore
        weak var container: EditorContainer?
        var updating = false
        var lastNavigation: UUID?
        private var lastText: String?
        private var lastComments: [Comment] = []
        private var lastActive: UUID?
        private var lastDraft: Comment?
        private var hidden = IndexSet()
        private var markers: [UUID: CommentMarker] = [:]
        private var editorPopoverID: UUID?
        private let previewPopover: NSPopover = {
            let popover = NSPopover()
            popover.behavior = .applicationDefined
            popover.animates = false
            return popover
        }()
        private lazy var editorPopover: NSPopover = {
            let popover = NSPopover()
            popover.behavior = .transient
            popover.delegate = self
            return popover
        }()

        init(_ store: SessionStore) { self.store = store }

        func layoutMarkers() {
            guard let container, let storage = container.textView.textStorage else { return }
            let text = container.textView.string
            let counts = MarkdownStyler.markerCounts(store.comments, in: text, hidden: hidden)
            var slots: [NSRange: Int] = [:]
            var placed = Set<UUID>()
            for (index, comment) in store.sortedComments.enumerated() {
                guard let marker = CommentRanges.markerRange(of: comment.range, in: text, hidden: hidden),
                      let (rect, baseline) = container.markerPlacement(for: comment.range, hidden: hidden) else { continue }
                let slot = slots[marker, default: 0]
                slots[marker] = slot + 1
                // The glyph's advance includes the kerning reserved for its markers.
                let reserved = MarkdownStyler.markerAdvance * CGFloat(counts[marker] ?? 1)
                let font = storage.attribute(.font, at: marker.location, effectiveRange: nil) as? NSFont ?? MarkdownStyler.bodyFont
                let view = markers[comment.id] ?? makeMarker(comment.id, in: container.textView)
                // Centered on the middle of CJK glyphs, which sit higher than Latin x-height.
                view.frame = NSRect(x: rect.maxX - reserved + 2 + CGFloat(slot) * MarkdownStyler.markerAdvance,
                                    y: baseline - font.pointSize * 0.36 - CommentMarker.size / 2,
                                    width: CommentMarker.size, height: CommentMarker.size).integral
                view.number = index + 1
                view.active = store.activeID == comment.id
                view.setAccessibilityLabel("第 \(index + 1) 条批注：\(comment.body)")
                placed.insert(comment.id)
            }
            for (id, marker) in markers where !placed.contains(id) {
                marker.removeFromSuperview()
                markers[id] = nil
            }
        }

        private func makeMarker(_ id: UUID, in textView: NSTextView) -> CommentMarker {
            let marker = CommentMarker(id: id)
            marker.onHover = { [weak self] marker, inside in self?.hover(marker, inside) }
            marker.onPress = { [weak self] marker in self?.press(marker) }
            textView.addSubview(marker)
            markers[id] = marker
            return marker
        }

        private func hover(_ marker: CommentMarker, _ inside: Bool) {
            guard inside else {
                previewPopover.close()
                if store.draft == nil && store.activeID == marker.id { store.activeID = nil }
                return
            }
            guard store.draft == nil, let comment = store.comments.first(where: { $0.id == marker.id }) else { return }
            let host = NSHostingController(rootView: CommentPreview(comment: comment))
            host.sizingOptions = .preferredContentSize
            previewPopover.contentViewController = host
            previewPopover.show(relativeTo: marker.frame, of: container?.textView ?? marker, preferredEdge: .maxY)
            store.activeID = comment.id
        }

        private func press(_ marker: CommentMarker) {
            previewPopover.close()
            guard let comment = store.comments.first(where: { $0.id == marker.id }) else { return }
            if store.draft?.id == comment.id { return }
            store.edit(comment)
        }

        func syncEditorPopover() {
            guard let container else { return }
            guard let draft = store.draft else {
                if editorPopover.isShown { editorPopoverID = nil; editorPopover.close() }
                return
            }
            if editorPopover.isShown && editorPopoverID == draft.id { return }
            if editorPopover.isShown { editorPopoverID = nil; editorPopover.close() }
            // A fresh editor per comment so focus and scroll state never carry over.
            let host = NSHostingController(rootView: CommentEditorPopover(store: store))
            host.sizingOptions = .preferredContentSize
            editorPopover.contentViewController = host
            // Anchored to the text view (not the marker) so the popover joins its accessibility tree.
            if let marker = markers[draft.id] {
                editorPopoverID = draft.id
                editorPopover.show(relativeTo: marker.frame, of: container.textView, preferredEdge: .maxY)
            } else if let (rect, _) = container.markerPlacement(for: draft.range, hidden: hidden) {
                editorPopoverID = draft.id
                editorPopover.show(relativeTo: rect, of: container.textView, preferredEdge: .maxY)
            }
            // A popover opened from a shortcut stays non-key; typing must go straight into the comment.
            DispatchQueue.main.async { [weak host] in
                guard let view = host?.view, let window = view.window else { return }
                window.makeKey()
                if !(window.firstResponder is NSTextView), let editor = Self.firstTextView(in: view) {
                    window.makeFirstResponder(editor)
                }
            }
        }

        private static func firstTextView(in view: NSView) -> NSTextView? {
            if let text = view as? NSTextView, text.isEditable { return text }
            for subview in view.subviews { if let text = firstTextView(in: subview) { return text } }
            return nil
        }

        func popoverDidClose(_ notification: Notification) {
            guard let id = editorPopoverID else { return }
            editorPopoverID = nil
            // Clicking elsewhere keeps what was typed; Esc and 取消 discard explicitly.
            DispatchQueue.main.async { [store] in
                guard store.draft?.id == id else { return }
                if store.draftBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { store.cancelDraft() }
                else { store.saveDraft() }
            }
        }

        func styleIfNeeded() {
            guard let view = container?.textView, let storage = view.textStorage,
                  !view.hasMarkedText() else { return }
            guard lastText != view.string || lastComments != store.comments || lastActive != store.activeID || lastDraft != store.draft else { return }
            lastText = view.string
            lastComments = store.comments
            lastActive = store.activeID
            lastDraft = store.draft
            let selections = view.selectedRanges
            // Reviewing reads like a document; pasting and editing keep the markdown visible.
            hidden = MarkdownStyler.apply(to: storage, comments: store.comments, activeID: store.activeID,
                                          draft: store.draft, hideMarkup: store.review != nil)
            view.selectedRanges = selections
            view.typingAttributes = MarkdownStyler.base
        }

        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            guard !updating, let replacementString else { return true }
            store.willReplace(affectedCharRange, with: replacementString)
            return true
        }

        func textDidChange(_ notification: Notification) {
            guard !updating, let view = notification.object as? NSTextView else { return }
            store.textChanged(view.string)
            store.selection = view.selectedRange()
            updating = true
            styleIfNeeded()
            updating = false
            container?.canAdd = store.canAdd
            container?.positionButton()
            layoutMarkers()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !updating, let view = notification.object as? NSTextView else { return }
            store.selection = view.selectedRange()
            container?.canAdd = store.canAdd
            container?.positionButton()
        }
    }
}
