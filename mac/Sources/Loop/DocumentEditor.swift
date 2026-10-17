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
}

final class EditorContainer: NSView {
    let scrollView = NSScrollView()
    let textView: PlanTextView
    let addButton = NSButton(title: "批注", target: nil, action: nil)
    var onAdd: (() -> Void)?
    var canAdd = false
    private var scrollObserver: NSObjectProtocol?

    override init(frame frameRect: NSRect) {
        let storage = NSTextStorage()
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        storage.addLayoutManager(manager)
        manager.addTextContainer(container)
        textView = PlanTextView(frame: .zero, textContainer: container)
        super.init(frame: frameRect)
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
        textView.textContainerInset = NSSize(width: 32, height: 30)
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
        addButton.bezelStyle = .rounded
        addButton.controlSize = .small
        addButton.image = NSImage(systemSymbolName: "text.bubble", accessibilityDescription: nil)
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
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { if let scrollObserver { NotificationCenter.default.removeObserver(scrollObserver) } }
    @objc private func addComment() { onAdd?() }

    override func layout() {
        super.layout()
        // Keep enough drawable space for the multiline placeholder in an empty document.
        textView.minSize = NSSize(width: 0, height: scrollView.contentSize.height)
        if textView.frame.height < scrollView.contentSize.height {
            textView.setFrameSize(NSSize(width: textView.frame.width, height: scrollView.contentSize.height))
        }
        textView.needsDisplay = true
        positionButton()
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
        let width = max(76, addButton.frame.width)
        addButton.frame = NSRect(
            x: max(8, min(bounds.width - width - 18, anchor.maxX + 8)),
            y: max(8, min(bounds.height - 32, anchor.minY - 30)), width: width, height: 28)
        addButton.isHidden = false
    }
}

struct DocumentEditor: NSViewRepresentable {
    @ObservedObject var store: SessionStore

    func makeCoordinator() -> Coordinator { Coordinator(store) }
    func makeNSView(context: Context) -> EditorContainer {
        let view = EditorContainer(frame: .zero)
        view.textView.delegate = context.coordinator
        view.onAdd = { [weak store] in store?.addComment() }
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
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let store: SessionStore
        weak var container: EditorContainer?
        var updating = false
        var lastNavigation: UUID?
        private var lastText: String?
        private var lastComments: [Comment] = []
        private var lastActive: UUID?
        private var lastDraft: Comment?

        init(_ store: SessionStore) { self.store = store }

        func styleIfNeeded() {
            guard let view = container?.textView, let storage = view.textStorage,
                  !view.hasMarkedText() else { return }
            guard lastText != view.string || lastComments != store.comments || lastActive != store.activeID || lastDraft != store.draft else { return }
            lastText = view.string
            lastComments = store.comments
            lastActive = store.activeID
            lastDraft = store.draft
            let selections = view.selectedRanges
            MarkdownStyler.apply(to: storage, comments: store.comments, activeID: store.activeID, draft: store.draft)
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
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !updating, let view = notification.object as? NSTextView else { return }
            store.selection = view.selectedRange()
            container?.canAdd = store.canAdd
            container?.positionButton()
        }
    }
}
