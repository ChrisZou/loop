import SwiftUI
import AppKit

/// A commented range as the text view paints it: a faint wash with a red-pen underline.
struct Highlight: Equatable {
    let range: NSRange
    let active: Bool
}

/// A task item's checkbox as drawn. Boxes the reviewer changed are marked in vermilion, like everything else they mark.
struct TaskBox: Equatable {
    let location: Int
    let labelStart: Int
    let checked: Bool
    let changed: Bool
}

final class PlanTextView: NSTextView {
    /// Mouse position in view coordinates while over the text, nil once it leaves.
    var onHover: ((NSPoint?) -> Void)?
    var highlights: [Highlight] = [] { didSet { if highlights != oldValue { needsDisplay = true } } }
    /// Horizontal padding between the sheet's edge and the text column.
    var sheetPadding = Theme.sheetPadding
    /// The plan's markdown. The text view's own string differs where tables swap pipes for paragraph breaks.
    var source: NSString?
    var taskBoxes: [TaskBox] = [] { didSet { if taskBoxes != oldValue { needsDisplay = true } } }
    /// A checkbox was clicked; passes its `TaskBox.location`.
    var onToggleTask: ((Int) -> Void)?
    private var hoverArea: NSTrackingArea?
    private var resizing = false

    /// A width change rewraps the plan; NSTextView would then scroll to keep the (invisible) caret in view,
    /// which drops the reader somewhere below the top. Reading position stays put instead.
    override func setFrameSize(_ newSize: NSSize) {
        resizing = true
        defer { resizing = false }
        super.setFrameSize(newSize)
    }

    override func scrollToVisible(_ rect: NSRect) -> Bool {
        resizing ? false : super.scrollToVisible(rect)
    }

    /// Copying hands out the plan's markdown, pipes included.
    override func writeSelection(to pboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> Bool {
        guard let source, source.length == (string as NSString).length else { return super.writeSelection(to: pboard, types: types) }
        let text = selectedRanges.map { source.substring(with: $0.rangeValue) }.joined(separator: "\n")
        pboard.clearContents()
        return pboard.setString(text, forType: .string)
    }

    func trackHover() {
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        let point = convert(event.locationInWindow, from: nil)
        if taskBox(at: point) != nil { NSCursor.pointingHand.set() }
        onHover?(point)
    }

    /// A click on a checkbox ticks it instead of starting a selection.
    override func mouseDown(with event: NSEvent) {
        if let box = taskBox(at: convert(event.locationInWindow, from: nil)) {
            onToggleTask?(box.location)
            return
        }
        super.mouseDown(with: event)
    }

    func taskBox(at point: NSPoint) -> TaskBox? {
        taskBoxes.first { taskRect($0)?.insetBy(dx: -5, dy: -5).contains(point) == true }
    }

    /// The checkbox sits in the room the paragraph indent leaves before the item's text, centered on its first line.
    func taskRect(_ box: TaskBox) -> NSRect? {
        guard let manager = layoutManager, let storage = textStorage, storage.length > 0 else { return nil }
        let index = min(box.labelStart, storage.length - 1)
        let glyph = manager.glyphIndexForCharacter(at: index)
        let line = manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        let location = manager.location(forGlyphAt: glyph)
        let font = storage.attribute(.font, at: index, effectiveRange: nil) as? NSFont ?? MarkdownStyler.bodyFont
        let size = MarkdownStyler.taskBox
        let origin = textContainerOrigin
        let center = origin.y + line.minY + location.y - font.pointSize * 0.36
        return NSRect(x: origin.x + line.minX + location.x - MarkdownStyler.taskBoxRoom, y: (center - size / 2).rounded(),
                      width: size, height: size)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        if event.trackingArea === hoverArea { onHover?(nil) }
    }

    /// The sheet, code cards, quote bars and comment highlights, all beneath the text.
    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard let storage = textStorage, let manager = layoutManager, let container = textContainer else { return }
        let origin = textContainerOrigin
        drawSheet(in: rect, origin: origin, width: container.size.width)
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
                Theme.codeBackground.setFill()
                NSBezierPath(roundedRect: block, xRadius: 6, yRadius: 6).fill()
            case .quote:
                Theme.secondary.withAlphaComponent(0.3).setFill()
                NSBezierPath(roundedRect: NSRect(x: block.minX + 2, y: block.minY + 2, width: 3, height: block.height - 4),
                             xRadius: 1.5, yRadius: 1.5).fill()
            }
        }
        drawInlineCode(in: rect, storage: storage, manager: manager, container: container, origin: origin)
        drawHighlights(in: rect, storage: storage, manager: manager, container: container, origin: origin)
        drawTasks(in: rect)
    }

    /// Unticked boxes are a quiet outline and the plan's own ticks are ink; the reviewer's changes are vermilion.
    private func drawTasks(in rect: NSRect) {
        for box in taskBoxes {
            guard let frame = taskRect(box), frame.insetBy(dx: -2, dy: -2).intersects(rect) else { continue }
            let path = NSBezierPath(roundedRect: frame.insetBy(dx: 0.75, dy: 0.75), xRadius: 3.5, yRadius: 3.5)
            let pen = box.changed ? Theme.vermilion : Theme.ink
            guard box.checked else {
                (box.changed ? pen : Theme.secondary.withAlphaComponent(0.55)).setStroke()
                path.lineWidth = box.changed ? 1.5 : 1.3
                path.stroke()
                continue
            }
            pen.setFill()
            NSBezierPath(roundedRect: frame, xRadius: 3.5, yRadius: 3.5).fill()
            let tick = NSBezierPath()
            tick.move(to: NSPoint(x: frame.minX + 3.6, y: frame.minY + 7.3))
            tick.line(to: NSPoint(x: frame.minX + 6.1, y: frame.minY + 9.8))
            tick.line(to: NSPoint(x: frame.minX + 10.6, y: frame.minY + 4.6))
            tick.lineWidth = 1.7
            tick.lineCapStyle = .round
            tick.lineJoinStyle = .round
            (box.changed ? Theme.onVermilion : Theme.sheet).setStroke()
            tick.stroke()
        }
    }

    /// A rounded background centered on the code's glyphs: equal room above and below, and on both sides.
    private func drawInlineCode(in rect: NSRect, storage: NSTextStorage, manager: NSLayoutManager,
                                container: NSTextContainer, origin: NSPoint) {
        let pad = MarkdownStyler.codePadding
        storage.enumerateAttribute(.loopInlineCode, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard value != nil, let font = storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont else { return }
            let glyphs = manager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            manager.enumerateLineFragments(forGlyphRange: glyphs) { line, used, _, lineGlyphs, _ in
                let part = NSIntersectionRange(lineGlyphs, glyphs)
                guard part.length > 0 else { return }
                let start = manager.location(forGlyphAt: part.location)
                let endGlyph = NSMaxRange(part) - 1
                var endX = min(manager.boundingRect(forGlyphRange: NSRange(location: endGlyph, length: 1), in: container).maxX,
                               used.maxX)
                // The last character's kern is the code's own padding plus any comment markers after it.
                if endGlyph == NSMaxRange(glyphs) - 1 {
                    let kern = storage.attribute(.kern, at: manager.characterIndexForGlyph(at: endGlyph), effectiveRange: nil) as? CGFloat ?? 0
                    endX -= max(0, kern - pad)
                }
                let startX = line.minX + start.x - (part.location == glyphs.location ? pad : 0)
                let baseline = origin.y + line.minY + start.y
                let box = NSRect(x: origin.x + startX, y: baseline - font.ascender - 1,
                                 width: endX - startX, height: font.ascender - font.descender + 2)
                guard box.intersects(rect) else { return }
                Theme.codeBackground.setFill()
                NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4).fill()
            }
        }
    }

    /// The white sheet behind the text column.
    var sheetRect: NSRect {
        let width = textContainer?.size.width ?? 0
        return NSRect(x: textContainerOrigin.x - sheetPadding, y: Theme.sheetTop, width: width + sheetPadding * 2,
                      height: bounds.height - Theme.sheetTop - Theme.sheetBottom)
    }

    private func drawSheet(in rect: NSRect, origin: NSPoint, width: CGFloat) {
        let sheet = sheetRect
        guard sheet.insetBy(dx: -40, dy: -40).intersects(rect) else { return }
        let path = NSBezierPath(roundedRect: sheet, xRadius: 6, yRadius: 6)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(srgbRed: 20 / 255, green: 30 / 255, blue: 50 / 255, alpha: 0.09)
        shadow.shadowBlurRadius = 24
        shadow.shadowOffset = NSSize(width: 0, height: -8)
        shadow.set()
        Theme.sheet.setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()
        Theme.rule.withAlphaComponent(0.06).setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    private func drawHighlights(in rect: NSRect, storage: NSTextStorage, manager: NSLayoutManager,
                                container: NSTextContainer, origin: NSPoint) {
        for highlight in highlights where CommentRanges.valid(highlight.range, in: storage.string) {
            let glyphs = manager.glyphRange(forCharacterRange: highlight.range, actualCharacterRange: nil)
            guard glyphs.length > 0 else { continue }
            let last = NSMaxRange(glyphs) - 1
            // The last glyph's advance includes the room kerned for markers; the underline stops before them.
            let reserved = storage.attribute(.kern, at: manager.characterIndexForGlyph(at: last), effectiveRange: nil) as? CGFloat ?? 0
            manager.enumerateLineFragments(forGlyphRange: glyphs) { line, used, _, lineGlyphs, _ in
                let part = NSIntersectionRange(lineGlyphs, glyphs)
                guard part.length > 0 else { return }
                let start = manager.location(forGlyphAt: part.location)
                let endGlyph = NSMaxRange(part) - 1
                var endX = min(manager.boundingRect(forGlyphRange: NSRange(location: endGlyph, length: 1), in: container).maxX,
                               used.maxX)
                if endGlyph == last { endX -= reserved }
                let startX = line.minX + start.x
                guard endX > startX else { return }
                let font = storage.attribute(.font, at: manager.characterIndexForGlyph(at: part.location), effectiveRange: nil) as? NSFont
                let size = font?.pointSize ?? MarkdownStyler.bodyFont.pointSize
                let baseline = origin.y + line.minY + start.y
                let x = origin.x + startX
                let band = NSRect(x: x - 1, y: baseline - size, width: endX - startX + 2, height: size * 1.3)
                guard band.intersects(rect) else { return }
                Theme.vermilion.withAlphaComponent(highlight.active ? 0.13 : 0.06).setFill()
                NSBezierPath(roundedRect: band, xRadius: 2, yRadius: 2).fill()
                Theme.vermilion.withAlphaComponent(highlight.active ? 0.95 : 0.65).setFill()
                NSRect(x: x, y: baseline + size * 0.2, width: endX - startX, height: 2).fill()
            }
        }
    }
}

/// A red-pen circled number after a commented range's last character; hover previews the comment,
/// click edits it. The number matches the item's position in the submitted feedback.
final class CommentMarker: NSView {
    /// The frame leaves room around the 16pt badge for the hover ring.
    static let size: CGFloat = 22
    static let badge: CGFloat = 16
    let id: UUID
    var active = false { didSet { if active != oldValue { needsDisplay = true } } }
    var number = 0 { didSet { if number != oldValue { needsDisplay = true } } }
    var onHover: ((CommentMarker, Bool) -> Void)?
    var onPress: ((CommentMarker) -> Void)?

    init(id: UUID) {
        self.id = id
        super.init(frame: NSRect(x: 0, y: 0, width: Self.size, height: Self.size))
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
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
        let badge = NSRect(x: (bounds.width - Self.badge) / 2, y: (bounds.height - Self.badge) / 2,
                           width: Self.badge, height: Self.badge)
        if active {
            Theme.vermilion.withAlphaComponent(0.16).setFill()
            NSBezierPath(ovalIn: badge.insetBy(dx: -3, dy: -3)).fill()
        }
        let circle = NSBezierPath(ovalIn: badge.insetBy(dx: 0.75, dy: 0.75))
        Theme.sheet.setFill()
        circle.fill()
        Theme.vermilion.setStroke()
        circle.lineWidth = 1.5
        circle.stroke()
        let base = NSFont.systemFont(ofSize: number >= 10 ? 8 : 10, weight: .bold)
        let font = base.fontDescriptor.withDesign(.serif).flatMap { NSFont(descriptor: $0, size: base.pointSize) } ?? base
        let label = "\(number)" as NSString
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: Theme.vermilion]
        let size = label.size(withAttributes: attributes)
        label.draw(at: NSPoint(x: badge.midX - size.width / 2, y: badge.midY - size.height / 2), withAttributes: attributes)
    }
}

/// The floating 批注 pill above a selection.
struct AddCommentButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "pencil").font(.system(size: 12, weight: .semibold))
                Text("批注").fontWeight(.semibold)
                Text("⌘↩").font(.system(size: 11.5)).opacity(0.75)
            }
            .font(.system(size: 12.5))
            .foregroundStyle(Color(Theme.onVermilion))
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(Capsule().fill(Color(Theme.vermilion)))
            .shadow(color: Color(Theme.vermilion).opacity(0.3), radius: 8, y: 4)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("添加批注（⌘↩）")
        // Room for the shadow inside the hosting view.
        .padding(AddCommentButton.shadowRoom)
    }

    static let shadowRoom: CGFloat = 12
}

final class EditorContainer: NSView {
    let scrollView = NSScrollView()
    let textView: PlanTextView
    let addButton = NSHostingView(rootView: AddCommentButton(action: {}))
    let previewCard = CardView(rootView: AnyView(EmptyView()))
    let editorCard = CardView(rootView: AnyView(EmptyView()))
    private let markupDelegate = MarkupLayoutDelegate()
    var onAdd: (() -> Void)?
    var onLayout: (() -> Void)?
    var onScroll: (() -> Void)?
    var onSheetLayout: ((SheetLayout) -> Void)?
    /// The text column's width changed, which reflows tables.
    var onTextWidth: ((CGFloat) -> Void)?
    private var textWidth: CGFloat = 0
    var canAdd = false
    private var scrollOrigin = NSPoint.zero
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
        scrollView.backgroundColor = Theme.ground
        scrollView.borderType = .noBorder
        // The plan is the agent's text: comment on it, don't edit it.
        textView.isRichText = false
        textView.isEditable = false
        textView.isSelectable = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 40, height: Theme.sheetTop + 58)
        textView.font = MarkdownStyler.bodyFont
        textView.backgroundColor = Theme.ground
        textView.selectedTextAttributes = [.backgroundColor: Theme.selection]
        textView.setAccessibilityLabel("方案正文")
        textView.trackHover()
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
        addButton.rootView = AddCommentButton { [weak self] in self?.onAdd?() }
        addButton.isHidden = true
        addSubview(addButton)
        previewCard.passesClicks = true
        for card in [previewCard, editorCard] {
            card.isHidden = true
            addSubview(card)
        }
        clipsToBounds = true
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification, object: scrollView.contentView, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.positionButton()
            let origin = self.scrollView.contentView.bounds.origin
            if origin != self.scrollOrigin { self.scrollOrigin = origin; self.onScroll?() }
        }
        // Rewrapping after a width change moves every marker.
        textView.postsFrameChangedNotifications = true
        frameObserver = NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification, object: textView, queue: .main
        ) { [weak self] _ in
            self?.onLayout?()
            self?.reportSheet()
            self?.reportTextWidth()
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit {
        for observer in [scrollObserver, frameObserver].compactMap({ $0 }) { NotificationCenter.default.removeObserver(observer) }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        // Any toolbar content inset arrives after the text is laid out; start reading at the very top.
        DispatchQueue.main.async { [weak self] in
            guard let clip = self?.scrollView.contentView else { return }
            clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: -clip.contentInsets.top))
            self?.scrollView.reflectScrolledClipView(clip)
        }
    }

    override func layout() {
        super.layout()
        // A fixed-width sheet centered on the desk; narrow windows shrink the sheet and its margins.
        let available = scrollView.contentSize.width
        let sheet = min(Theme.sheetWidth, available - 48)
        let padding = min(Theme.sheetPadding, max(28, floor(sheet * 0.11)))
        let inset = floor((available - sheet) / 2) + padding
        if textView.textContainerInset.width != inset || textView.sheetPadding != padding {
            textView.sheetPadding = padding
            textView.textContainerInset = NSSize(width: inset, height: textView.textContainerInset.height)
        }
        // The sheet always reaches the bottom of the window, even for a short plan.
        textView.minSize = NSSize(width: 0, height: scrollView.contentSize.height)
        if textView.frame.height < scrollView.contentSize.height {
            textView.setFrameSize(NSSize(width: textView.frame.width, height: scrollView.contentSize.height))
        }
        textView.needsDisplay = true
        positionButton()
        onLayout?()
        reportSheet()
        reportTextWidth()
    }

    private func reportTextWidth() {
        let width = textView.textContainer?.size.width ?? 0
        guard width > 0, width != textWidth else { return }
        textWidth = width
        onTextWidth?(width)
    }

    /// Measured from what the text view draws, which a legacy scroller can make narrower than planned.
    private func reportSheet() {
        let sheet = convert(textView.sheetRect, from: textView)
        onSheetLayout?(SheetLayout(width: sheet.width, offset: sheet.midX - bounds.midX))
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

    /// The character drawn under a point in text view coordinates; nil over margins and blank space.
    func characterIndex(at point: NSPoint) -> Int? {
        guard let manager = textView.layoutManager, let container = textView.textContainer,
              manager.numberOfGlyphs > 0 else { return nil }
        let origin = textView.textContainerOrigin
        let local = NSPoint(x: point.x - origin.x, y: point.y - origin.y)
        let glyph = manager.glyphIndex(for: local, in: container)
        guard manager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container).contains(local) else { return nil }
        return manager.characterIndexForGlyph(at: glyph)
    }

    func positionButton() {
        let selected = textView.selectedRange()
        guard canAdd, selected.length > 0, !textView.hasMarkedText(),
              let manager = textView.layoutManager, let container = textView.textContainer else {
            addButton.isHidden = true
            return
        }
        let glyphs = manager.glyphRange(forCharacterRange: selected, actualCharacterRange: nil)
        var lines: [NSRect] = []
        manager.enumerateEnclosingRects(forGlyphRange: glyphs, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                                        in: container) { rect, _ in lines.append(rect) }
        let origin = textView.textContainerOrigin
        guard let firstLine = lines.first?.offsetBy(dx: origin.x, dy: origin.y),
              let lastLine = lines.last?.offsetBy(dx: origin.x, dy: origin.y),
              textView.visibleRect.intersects(firstLine.union(lastLine)) else {
            addButton.isHidden = true
            return
        }
        // This view is unflipped: maxY is the visual top of a line.
        let first = convert(firstLine, from: textView)
        let last = convert(lastLine, from: textView)
        let size = addButton.fittingSize
        let room = AddCommentButton.shadowRoom
        let pill = NSSize(width: size.width - room * 2, height: size.height - room * 2)
        // Centered just above the selection's first line; below its last line when scrolled against the top edge.
        let above = first.maxY + 6
        let y = above + pill.height <= bounds.height - 4 ? above : max(8, last.minY - pill.height - 6)
        let x = max(8, min(bounds.width - pill.width - 18, first.midX - pill.width / 2))
        addButton.frame = NSRect(x: x - room, y: y - room, width: size.width, height: size.height)
        addButton.isHidden = false
    }
}

struct DocumentEditor: NSViewRepresentable {
    @ObservedObject var store: SessionStore

    func makeCoordinator() -> Coordinator { Coordinator(store) }
    func makeNSView(context: Context) -> EditorContainer {
        let view = EditorContainer(frame: .zero)
        view.textView.delegate = context.coordinator
        view.textView.string = store.text
        view.textView.source = store.text as NSString
        view.textView.onToggleTask = { [weak store] location in store?.toggleTask(at: location) }
        view.onAdd = { [weak store] in store?.addComment() }
        view.onLayout = { [weak coordinator = context.coordinator] in coordinator?.layoutMarkers() }
        view.onScroll = { [weak coordinator = context.coordinator] in coordinator?.scrolled() }
        view.onSheetLayout = { [weak store] layout in
            // Published after the layout pass, never during a SwiftUI update.
            DispatchQueue.main.async { if store?.sheet != layout { store?.sheet = layout } }
        }
        view.textView.onHover = { [weak coordinator = context.coordinator] point in coordinator?.hoverText(at: point) }
        // After the layout pass that reported it: the text storage can't change mid-layout.
        view.onTextWidth = { [weak coordinator = context.coordinator] width in
            DispatchQueue.main.async { coordinator?.refitTables(width) }
        }
        context.coordinator.container = view
        return view
    }

    func updateNSView(_ view: EditorContainer, context: Context) {
        let coordinator = context.coordinator
        coordinator.updating = true
        defer { coordinator.updating = false }
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
        coordinator.syncEditorCard()
    }

    static func dismantleNSView(_ view: EditorContainer, coordinator: Coordinator) {
        coordinator.closeCards()
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let store: SessionStore
        weak var container: EditorContainer?
        var updating = false
        var lastNavigation: UUID?
        private var styled = false
        private var fittedWidth: CGFloat = 0
        private var lastComments: [Comment] = []
        private var markers: [UUID: CommentMarker] = [:]
        private var hoveredMarker: UUID?
        private var hoveredText: UUID?
        private var previewID: UUID?
        private var editorID: UUID?
        private var clickMonitor: Any?
        private var previewCard: CardView? { container?.previewCard }
        private var editorCard: CardView? { container?.editorCard }

        init(_ store: SessionStore) { self.store = store }

        func layoutMarkers() {
            guard let container, let storage = container.textView.textStorage else { return }
            let text = container.textView.string
            let counts = MarkdownStyler.markerCounts(store.comments, in: text, hidden: store.hidden)
            var slots: [NSRange: Int] = [:]
            var placed = Set<UUID>()
            for (index, comment) in store.sortedComments.enumerated() {
                guard let marker = CommentRanges.markerRange(of: comment.range, in: text, hidden: store.hidden),
                      let (rect, baseline) = container.markerPlacement(for: comment.range, hidden: store.hidden) else { continue }
                let slot = slots[marker, default: 0]
                slots[marker] = slot + 1
                // The glyph's advance includes the kerning reserved for its markers.
                let reserved = MarkdownStyler.markerAdvance * CGFloat(counts[marker] ?? 1)
                let font = storage.attribute(.font, at: marker.location, effectiveRange: nil) as? NSFont ?? MarkdownStyler.bodyFont
                let view = markers[comment.id] ?? makeMarker(comment.id, in: container.textView)
                let slotStart = rect.maxX - reserved + CGFloat(slot) * MarkdownStyler.markerAdvance
                // Raised like a footnote mark, centered in the room kerned for it.
                view.frame = NSRect(x: slotStart + (MarkdownStyler.markerAdvance - CommentMarker.size) / 2 + 1,
                                    y: baseline - font.pointSize * 0.62 - CommentMarker.size / 2,
                                    width: CommentMarker.size, height: CommentMarker.size).integral
                view.number = index + 1
                view.active = store.activeID == comment.id
                view.setAccessibilityLabel("第 \(index + 1) 条批注：\(comment.body)" + (comment.images.isEmpty ? "" : "（附图 \(comment.images.count) 张）"))
                placed.insert(comment.id)
            }
            for (id, marker) in markers where !placed.contains(id) {
                marker.removeFromSuperview()
                markers[id] = nil
            }
            placeCards()
        }

        private func makeMarker(_ id: UUID, in textView: NSTextView) -> CommentMarker {
            let marker = CommentMarker(id: id)
            marker.onHover = { [weak self] marker, inside in self?.hover(marker, inside) }
            marker.onPress = { [weak self] marker in self?.press(marker) }
            textView.addSubview(marker)
            markers[id] = marker
            return marker
        }

        /// The comment's position in the submitted feedback; a new draft counts where it will land.
        private func number(of comment: Comment) -> Int {
            if let index = store.sortedComments.firstIndex(where: { $0.id == comment.id }) { return index + 1 }
            return store.comments.filter { $0.location <= comment.location }.count + 1
        }

        private func hover(_ marker: CommentMarker, _ inside: Bool) {
            if inside { hoveredMarker = marker.id } else if hoveredMarker == marker.id { hoveredMarker = nil }
            updatePreview()
        }

        /// Hovering highlighted text previews its comment too; nested ranges prefer the innermost.
        func hoverText(at point: NSPoint?) {
            let index = point.flatMap { container?.characterIndex(at: $0) }
            hoveredText = index.flatMap { index in
                store.comments.filter { NSLocationInRange(index, $0.range) }.min { $0.range.length < $1.range.length }?.id
            }
            updatePreview()
        }

        func endHover() {
            hoveredMarker = nil
            hoveredText = nil
            updatePreview()
        }

        func scrolled() {
            endHover()
            placeCards()
        }

        private func updatePreview() {
            let id = store.draft == nil ? hoveredMarker ?? hoveredText : nil
            guard id != previewID else { return }
            if let old = previewID {
                previewCard?.dismiss()
                previewID = nil
                if store.draft == nil && store.activeID == old { store.activeID = nil }
            }
            guard let id, let comment = store.comments.first(where: { $0.id == id }),
                  let textView = container?.textView, let marker = markers[id] else { return }
            previewCard?.show(CommentPreview(comment: comment, number: number(of: comment)), below: marker.frame, in: textView)
            previewID = id
            store.activeID = id
        }

        private func press(_ marker: CommentMarker) {
            previewCard?.dismiss()
            previewID = nil
            guard let comment = store.comments.first(where: { $0.id == marker.id }) else { return }
            if store.draft?.id == comment.id { return }
            store.edit(comment)
        }

        /// Where the editor card hangs: under the comment's marker, or under the end of a new selection.
        private func editorAnchor(for draft: Comment) -> NSRect? {
            if let marker = markers[draft.id] { return marker.frame }
            return container?.markerPlacement(for: draft.range, hidden: store.hidden)?.rect
        }

        private func placeCards() {
            guard let textView = container?.textView else { return }
            if let id = editorID, let draft = store.draft, draft.id == id, let anchor = editorAnchor(for: draft) {
                editorCard?.place(below: anchor, in: textView)
            }
        }

        func syncEditorCard() {
            guard let container else { return }
            guard let draft = store.draft else {
                if editorID != nil { closeEditor() }
                return
            }
            if previewID != nil { previewCard?.dismiss(); previewID = nil }
            if editorID == draft.id { return }
            guard let anchor = editorAnchor(for: draft) else { return }
            // A fresh editor per comment so focus and scroll state never carry over.
            editorID = draft.id
            container.editorCard.show(CommentEditorCard(store: store, number: number(of: draft)), below: anchor, in: container.textView)
            container.editorCard.focusFirstTextView()
            watchOutsideClicks()
        }

        /// Clicking anywhere outside the editor keeps what was typed; Esc and 取消 discard explicitly.
        private func watchOutsideClicks() {
            guard clickMonitor == nil else { return }
            clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                // Picking images happens in a sheet, which is not outside the card.
                guard let self, !(event.window is NSSavePanel),
                      self.editorCard?.contains(windowPoint: event.locationInWindow) != true || event.window !== self.container?.window,
                      let id = self.editorID, self.store.draft?.id == id else { return event }
                if self.store.draftIsEmpty { self.store.cancelDraft() }
                else { self.store.saveDraft() }
                return event
            }
        }

        private func closeEditor() {
            editorID = nil
            if let monitor = clickMonitor { NSEvent.removeMonitor(monitor) }
            clickMonitor = nil
            let typing = (container?.window?.firstResponder as? NSView).map { view in editorCard.map(view.isDescendant(of:)) ?? false } ?? false
            editorCard?.dismiss()
            // Hand the keyboard back to the plan, so ⌘↩ and selection keys keep working.
            if typing, let textView = container?.textView { textView.window?.makeFirstResponder(textView) }
        }

        func closeCards() {
            previewCard?.dismiss()
            closeEditor()
        }

        func styleIfNeeded() {
            guard let view = container?.textView, let storage = view.textStorage else { return }
            if !styled || lastComments != store.comments {
                styled = true
                lastComments = store.comments
                let selections = view.selectedRanges
                // Before the first layout the container has no width yet; a full sheet's is close.
                let width = view.textContainer.map(\.size.width).flatMap { $0 > 0 ? $0 : nil } ?? MarkdownStyler.textWidth
                fittedWidth = width
                MarkdownStyler.apply(to: storage, source: store.text, comments: store.comments, width: width)
                view.selectedRanges = selections
            }
            // Inactive first, so an active range paints over the ones it overlaps.
            let draftID = store.draft?.id
            view.highlights = store.comments.filter { $0.id != draftID }
                .map { Highlight(range: $0.range, active: $0.id == store.activeID) }
                .sorted { !$0.active && $1.active }
                + (store.draft.map { [Highlight(range: $0.range, active: true)] } ?? [])
            view.taskBoxes = store.tasks.map {
                TaskBox(location: $0.location, labelStart: $0.labelStart, checked: store.isChecked($0),
                        changed: store.toggled.contains($0.location))
            }
        }

        /// A new text width only shares table columns out again; nothing is measured or restyled.
        func refitTables(_ width: CGFloat) {
            guard abs(width - fittedWidth) > 0.5, let storage = container?.textView.textStorage else { return }
            fittedWidth = width
            guard let range = MarkdownStyler.fitTables(in: storage, width: width) else { return }
            storage.beginEditing()
            storage.edited(.editedAttributes, range: range, changeInLength: 0)
            storage.endEditing()
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
