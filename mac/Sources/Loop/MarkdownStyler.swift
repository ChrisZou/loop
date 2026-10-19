import AppKit

extension NSAttributedString.Key {
    /// Markdown syntax characters the layout manager hides (or draws as a bullet) while reviewing.
    static let loopMarkup = NSAttributedString.Key("LoopMarkup")
    /// Block decorations the text view draws behind the text: a card for code, a bar for quotes.
    static let loopBlock = NSAttributedString.Key("LoopBlock")
}

enum MarkdownStyler {
    enum Markup: String { case hidden, bullet }
    enum Block: String { case code, quote }

    static let bodyFont = NSFont.systemFont(ofSize: 16)
    static let accent = NSColor(srgbRed: 0.24, green: 0.38, blue: 0.68, alpha: 1)
    /// Space reserved after a commented range's last character for each inline marker.
    static let markerAdvance: CGFloat = 21
    /// Reading column; wider windows get centered margins instead of longer lines.
    static let columnWidth: CGFloat = 700
    static var paragraph: NSParagraphStyle { paragraphStyle() }
    static var base: [NSAttributedString.Key: Any] {
        [.font: bodyFont, .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph]
    }

    private static func paragraphStyle(before: CGFloat = 0, after: CGFloat = 10, indent: CGFloat = 0,
                                       firstLine: CGFloat? = nil, tail: CGFloat = 0, lineSpacing: CGFloat = 7,
                                       lineHeight: CGFloat? = nil) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        style.paragraphSpacingBefore = before
        style.paragraphSpacing = after
        style.headIndent = indent
        style.firstLineHeadIndent = firstLine ?? indent
        style.tailIndent = tail
        if let lineHeight {
            style.minimumLineHeight = lineHeight
            style.maximumLineHeight = lineHeight
        }
        return style
    }

    /// Styles the text with attributes only, so comment ranges stay valid. Returns the hidden character indexes.
    @discardableResult
    static func apply(to storage: NSTextStorage, comments: [Comment], activeID: UUID?, draft: Comment?,
                      hideMarkup: Bool) -> IndexSet {
        let text = storage.string
        let full = NSRange(location: 0, length: storage.length)
        var hidden = IndexSet()
        var code = IndexSet()
        func markup(_ range: NSRange, _ kind: Markup = .hidden) {
            guard range.location != NSNotFound, range.length > 0 else { return }
            if hideMarkup {
                storage.addAttribute(.loopMarkup, value: kind.rawValue, range: range)
                if kind == .hidden { hidden.insert(integersIn: range.location..<NSMaxRange(range)) }
            } else {
                storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: range)
            }
        }
        func outsideCode(_ range: NSRange) -> Bool { !code.intersects(integersIn: range.location..<NSMaxRange(range)) }

        storage.beginEditing()
        storage.setAttributes(base, range: full)

        matches("(?ms)^(```[^\\n]*\\n)(.*?)^(```)[ \\t]*$", text: text) { match in
            code.insert(integersIn: match.range.location..<NSMaxRange(match.range))
            storage.addAttributes([
                .font: NSFont.monospacedSystemFont(ofSize: 13.5, weight: .regular),
                .paragraphStyle: paragraphStyle(after: 0, indent: 16, tail: -16, lineSpacing: 4),
                .loopBlock: Block.code.rawValue
            ], range: match.range)
            for (index, fence) in [match.range(at: 1), match.range(at: 3)].enumerated() {
                markup(fence)
                // A hidden fence becomes the card's top or bottom padding.
                if hideMarkup {
                    storage.addAttributes([
                        .font: NSFont.systemFont(ofSize: 2),
                        .paragraphStyle: paragraphStyle(after: index == 1 ? 16 : 0, lineSpacing: 0, lineHeight: index == 0 ? 14 : 10)
                    ], range: fence)
                }
            }
        }
        // Blank lines only separate markdown blocks; paragraph spacing already does that visually.
        // While editing they keep a little height so the caret can still land on them.
        matches("(?m)^[ \\t]*\\n", text: text) { match in
            guard outsideCode(match.range) else { return }
            storage.addAttribute(.paragraphStyle, value: paragraphStyle(after: 0, lineSpacing: 0, lineHeight: hideMarkup ? 1 : 6),
                                 range: match.range)
        }
        matches("(?m)^(#{1,6})([ \\t]+)(.+)$", text: text) { match in
            guard outsideCode(match.range) else { return }
            let level = match.range(at: 1).length
            let (size, weight, before): (CGFloat, NSFont.Weight, CGFloat) =
                level == 1 ? (28, .bold, 6) : level == 2 ? (21, .semibold, 30) : (17.5, .semibold, 18)
            storage.addAttributes([
                .font: NSFont.systemFont(ofSize: size, weight: weight),
                .paragraphStyle: paragraphStyle(before: match.range.location == 0 ? 0 : before, after: level == 1 ? 14 : 8)
            ], range: match.range)
            markup(NSRange(location: match.range(at: 1).location,
                           length: match.range(at: 1).length + match.range(at: 2).length))
        }
        let bulletWidth = (("• " as NSString).size(withAttributes: [.font: bodyFont])).width
        matches("(?m)^([ \\t]*)([-*+])([ \\t]+).*$", text: text) { match in
            guard outsideCode(match.range) else { return }
            let nesting = CGFloat(match.range(at: 1).length) * 8
            storage.addAttribute(.paragraphStyle, value: paragraphStyle(after: 6, indent: nesting + 6 + bulletWidth,
                                                                       firstLine: nesting + 6), range: match.range)
            markup(match.range(at: 1))
            markup(match.range(at: 2), .bullet)
            if !hideMarkup { storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: match.range(at: 2)) }
        }
        matches("(?m)^([ \\t]*)([0-9]+[.)])([ \\t]+).*$", text: text) { match in
            guard outsideCode(match.range) else { return }
            let prefix = (text as NSString).substring(with: NSRange(location: match.range(at: 2).location,
                                                                    length: match.range(at: 2).length + match.range(at: 3).length))
            let width = (prefix as NSString).size(withAttributes: [.font: bodyFont]).width
            let nesting = CGFloat(match.range(at: 1).length) * 8
            storage.addAttribute(.paragraphStyle, value: paragraphStyle(after: 6, indent: nesting + 6 + width,
                                                                       firstLine: nesting + 6), range: match.range)
            storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: match.range(at: 2))
            markup(match.range(at: 1))
        }
        matches("(?m)^(>[ \\t]?)(.*)$", text: text) { match in
            guard outsideCode(match.range) else { return }
            storage.addAttributes([.foregroundColor: NSColor.secondaryLabelColor,
                                   .paragraphStyle: paragraphStyle(indent: hideMarkup ? 18 : 0)], range: match.range)
            if hideMarkup { storage.addAttribute(.loopBlock, value: Block.quote.rawValue, range: match.range) }
            markup(match.range(at: 1))
        }
        matches("(\\*\\*)([^\\n]+?)(\\*\\*)", text: text) { match in
            guard outsideCode(match.range) else { return }
            let inner = match.range(at: 2)
            storage.enumerateAttribute(.font, in: inner) { value, range, _ in
                let font = value as? NSFont ?? bodyFont
                storage.addAttribute(.font, value: NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask), range: range)
            }
            markup(match.range(at: 1))
            markup(match.range(at: 3))
        }
        matches("(`)([^`\\n]+)(`)", text: text) { match in
            guard outsideCode(match.range) else { return }
            storage.addAttributes([
                .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular),
                .foregroundColor: NSColor.systemIndigo,
                .backgroundColor: NSColor.quaternaryLabelColor.withAlphaComponent(0.12)
            ], range: match.range(at: 2))
            markup(match.range(at: 1))
            markup(match.range(at: 3))
        }

        // Paint inactive ranges first so overlapping active ranges remain visible.
        let ranges = comments.filter { $0.id != activeID && $0.id != draft?.id }
            + comments.filter { $0.id == activeID && $0.id != draft?.id }
            + (draft.map { [$0] } ?? [])
        for comment in ranges where CommentRanges.valid(comment.range, in: text) {
            let active = comment.id == activeID
            storage.addAttribute(.backgroundColor,
                                 value: NSColor.systemYellow.withAlphaComponent(active ? 0.42 : 0.2),
                                 range: comment.range)
        }
        // Kerning makes room for markers without inserting characters, so ranges stay valid.
        for (marker, count) in markerCounts(comments, in: text, hidden: hidden) {
            storage.addAttribute(.kern, value: markerAdvance * CGFloat(count), range: marker)
        }
        storage.endEditing()
        return hidden
    }

    static func markerCounts(_ comments: [Comment], in text: String, hidden: IndexSet = IndexSet()) -> [NSRange: Int] {
        comments.reduce(into: [:]) { counts, comment in
            if let marker = CommentRanges.markerRange(of: comment.range, in: text, hidden: hidden) {
                counts[marker, default: 0] += 1
            }
        }
    }

    private static func matches(_ pattern: String, text: String, apply: (NSTextCheckingResult) -> Void) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        for match in regex.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length)) { apply(match) }
    }
}

/// Hides markup glyphs and draws list markers as bullets; the underlying string never changes.
final class MarkupLayoutDelegate: NSObject, NSLayoutManagerDelegate {
    func layoutManager(_ layoutManager: NSLayoutManager,
                       shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
                       properties props: UnsafePointer<NSLayoutManager.GlyphProperty>,
                       characterIndexes charIndexes: UnsafePointer<Int>,
                       font aFont: NSFont,
                       forGlyphRange glyphRange: NSRange) -> Int {
        guard let storage = layoutManager.textStorage, glyphRange.length > 0 else { return 0 }
        var newGlyphs = Array(UnsafeBufferPointer(start: glyphs, count: glyphRange.length))
        var newProps = Array(UnsafeBufferPointer(start: props, count: glyphRange.length))
        var changed = false
        for index in 0..<glyphRange.length {
            let character = charIndexes[index]
            guard character < storage.length,
                  let kind = (storage.attribute(.loopMarkup, at: character, effectiveRange: nil) as? String)
                    .flatMap(MarkdownStyler.Markup.init) else { continue }
            switch kind {
            case .hidden:
                newProps[index] = .null
            case .bullet:
                var bullet: UniChar = 0x2022
                var glyph: CGGlyph = 0
                if CTFontGetGlyphsForCharacters(aFont as CTFont, &bullet, &glyph, 1) { newGlyphs[index] = glyph }
            }
            changed = true
        }
        guard changed else { return 0 }
        layoutManager.setGlyphs(newGlyphs, properties: newProps, characterIndexes: charIndexes,
                                font: aFont, forGlyphRange: glyphRange)
        return glyphRange.length
    }
}
