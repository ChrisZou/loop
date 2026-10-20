import AppKit

extension NSAttributedString.Key {
    /// Markdown syntax characters the layout manager hides (or draws as a bullet).
    static let loopMarkup = NSAttributedString.Key("LoopMarkup")
    /// Block decorations the text view draws behind the text: a card for code, a bar for quotes.
    static let loopBlock = NSAttributedString.Key("LoopBlock")
    /// Inline code, whose rounded background the text view draws centered on the glyphs.
    static let loopInlineCode = NSAttributedString.Key("LoopInlineCode")
}

enum MarkdownStyler {
    enum Markup: String { case hidden, bullet }
    enum Block: String { case code, quote }

    static let bodyFont = NSFont.systemFont(ofSize: 15.5)
    /// Space reserved after a commented range's last character for each inline marker.
    static let markerAdvance: CGFloat = 21
    /// Room kerned on each side of inline code for its background.
    static let codePadding: CGFloat = 4
    static var base: [NSAttributedString.Key: Any] {
        [.font: bodyFont, .foregroundColor: Theme.ink, .paragraphStyle: paragraphStyle()]
    }

    private static func paragraphStyle(before: CGFloat = 0, after: CGFloat = 12, indent: CGFloat = 0,
                                       firstLine: CGFloat? = nil, tail: CGFloat = 0, lineSpacing: CGFloat = 8,
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
    /// Comment highlights are drawn by the text view; here comments only reserve room for their markers.
    @discardableResult
    static func apply(to storage: NSTextStorage, comments: [Comment]) -> IndexSet {
        let text = storage.string
        let full = NSRange(location: 0, length: storage.length)
        var hidden = IndexSet()
        var code = IndexSet()
        var spans = IndexSet()
        func markup(_ range: NSRange, _ kind: Markup = .hidden) {
            guard range.location != NSNotFound, range.length > 0 else { return }
            storage.addAttribute(.loopMarkup, value: kind.rawValue, range: range)
            if kind == .hidden { hidden.insert(integersIn: range.location..<NSMaxRange(range)) }
        }
        func outsideCode(_ range: NSRange) -> Bool { !code.intersects(integersIn: range.location..<NSMaxRange(range)) }

        storage.beginEditing()
        storage.setAttributes(base, range: full)

        matches("(?ms)^(```[^\\n]*\\n)(.*?)^(```)[ \\t]*$", text: text) { match in
            code.insert(integersIn: match.range.location..<NSMaxRange(match.range))
            storage.addAttributes([
                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                .foregroundColor: Theme.codeText,
                .paragraphStyle: paragraphStyle(after: 0, indent: 18, tail: -18, lineSpacing: 5),
                .loopBlock: Block.code.rawValue
            ], range: match.range)
            for (index, fence) in [match.range(at: 1), match.range(at: 3)].enumerated() {
                markup(fence)
                // A hidden fence becomes the card's top or bottom padding.
                storage.addAttributes([
                    .font: NSFont.systemFont(ofSize: 2),
                    .paragraphStyle: paragraphStyle(after: index == 1 ? 16 : 0, lineSpacing: 0, lineHeight: index == 0 ? 14 : 10)
                ], range: fence)
            }
        }
        // Blank lines only separate markdown blocks; paragraph spacing already does that visually.
        matches("(?m)^[ \\t]*\\n", text: text) { match in
            guard outsideCode(match.range) else { return }
            storage.addAttribute(.paragraphStyle, value: paragraphStyle(after: 0, lineSpacing: 0, lineHeight: 1), range: match.range)
        }
        matches("(?m)^(#{1,6})([ \\t]+)(.+)$", text: text) { match in
            guard outsideCode(match.range) else { return }
            let level = match.range(at: 1).length
            let (font, before, after): (NSFont, CGFloat, CGFloat) =
                level == 1 ? (Theme.serif(30), 26, 22)
                : level == 2 ? (Theme.serif(19), 30, 8)
                : level == 3 ? (Theme.serif(16.5), 20, 6)
                : (NSFont.systemFont(ofSize: 15.5, weight: .semibold), 16, 4)
            storage.addAttributes([
                .font: font,
                .foregroundColor: Theme.heading,
                .paragraphStyle: paragraphStyle(before: match.range.location == 0 ? 0 : before, after: after, lineSpacing: 4)
            ], range: match.range)
            markup(NSRange(location: match.range(at: 1).location,
                           length: match.range(at: 1).length + match.range(at: 2).length))
            // Section numbers are marked in red, like a corrected paper.
            let content = match.range(at: 3)
            if let number = try? NSRegularExpression(pattern: "^(?:\\d+(?:\\.\\d+)*[.、)]?|[一二三四五六七八九十]+[、.．])"),
               let found = number.firstMatch(in: text, range: content) {
                storage.addAttribute(.foregroundColor, value: Theme.vermilion, range: found.range)
            }
        }
        let bulletWidth = (("• " as NSString).size(withAttributes: [.font: bodyFont])).width
        matches("(?m)^([ \\t]*)([-*+])([ \\t]+).*$", text: text) { match in
            guard outsideCode(match.range) else { return }
            let nesting = CGFloat(match.range(at: 1).length) * 8
            storage.addAttribute(.paragraphStyle, value: paragraphStyle(after: 6, indent: nesting + 6 + bulletWidth,
                                                                       firstLine: nesting + 6), range: match.range)
            markup(match.range(at: 1))
            markup(match.range(at: 2), .bullet)
            storage.addAttribute(.foregroundColor, value: Theme.secondary, range: match.range(at: 2))
        }
        matches("(?m)^([ \\t]*)([0-9]+[.)])([ \\t]+).*$", text: text) { match in
            guard outsideCode(match.range) else { return }
            let prefix = (text as NSString).substring(with: NSRange(location: match.range(at: 2).location,
                                                                    length: match.range(at: 2).length + match.range(at: 3).length))
            let width = (prefix as NSString).size(withAttributes: [.font: bodyFont]).width
            let nesting = CGFloat(match.range(at: 1).length) * 8
            storage.addAttribute(.paragraphStyle, value: paragraphStyle(after: 6, indent: nesting + 6 + width,
                                                                       firstLine: nesting + 6), range: match.range)
            storage.addAttribute(.foregroundColor, value: Theme.secondary, range: match.range(at: 2))
            markup(match.range(at: 1))
        }
        matches("(?m)^(>[ \\t]?)(.*)$", text: text) { match in
            guard outsideCode(match.range) else { return }
            storage.addAttributes([.foregroundColor: Theme.secondary,
                                   .paragraphStyle: paragraphStyle(indent: 18),
                                   .loopBlock: Block.quote.rawValue], range: match.range)
            markup(match.range(at: 1))
        }
        matches("(`)([^`\\n]+)(`)", text: text) { match in
            guard outsideCode(match.range) else { return }
            spans.insert(integersIn: match.range.location..<NSMaxRange(match.range))
            let content = match.range(at: 2)
            storage.addAttributes([
                .font: NSFont.monospacedSystemFont(ofSize: 13.5, weight: .regular),
                .foregroundColor: Theme.codeText,
                .loopInlineCode: true
            ], range: content)
            markup(match.range(at: 1))
            markup(match.range(at: 3))
            // The backticks are hidden, so kerning makes the room the background needs on either side.
            storage.addAttribute(.kern, value: codePadding, range: NSRange(location: NSMaxRange(content) - 1, length: 1))
            let before = match.range.location - 1
            if before >= 0, (text as NSString).character(at: before) != 0x0A {
                storage.addAttribute(.kern, value: codePadding, range: NSRange(location: before, length: 1))
            }
        }
        // Code spans win over emphasis, and bold markers hug their words (CommonMark flanking),
        // so a literal `**` in prose or code never starts a bold run.
        matches("(\\*\\*)(?=\\S)([^\\n]+?)(?<=\\S)(\\*\\*)", text: text) { match in
            let delimiters = [match.range(at: 1), match.range(at: 3)]
            guard outsideCode(match.range),
                  !delimiters.contains(where: { spans.intersects(integersIn: $0.location..<NSMaxRange($0)) }) else { return }
            let inner = match.range(at: 2)
            storage.enumerateAttribute(.font, in: inner) { value, range, _ in
                let font = value as? NSFont ?? bodyFont
                let bold = NSFont(descriptor: font.fontDescriptor.withSymbolicTraits(.bold), size: font.pointSize) ?? font
                storage.addAttribute(.font, value: bold, range: range)
            }
            markup(match.range(at: 1))
            markup(match.range(at: 3))
        }

        // Kerning makes room for markers without inserting characters, so ranges stay valid.
        for (marker, count) in markerCounts(comments, in: text, hidden: hidden) {
            let existing = storage.attribute(.kern, at: marker.location, effectiveRange: nil) as? CGFloat ?? 0
            storage.addAttribute(.kern, value: existing + markerAdvance * CGFloat(count), range: marker)
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
