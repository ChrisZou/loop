import AppKit

extension NSAttributedString.Key {
    /// Markdown syntax characters the layout manager hides (or draws as a bullet).
    static let loopMarkup = NSAttributedString.Key("LoopMarkup")
    /// Block decorations the text view draws behind the text: a card for code, a bar for quotes.
    static let loopBlock = NSAttributedString.Key("LoopBlock")
    /// Inline code, whose rounded background the text view draws centered on the glyphs.
    static let loopInlineCode = NSAttributedString.Key("LoopInlineCode")
    /// A task item's hidden `[ ]` or `[x]`; the value says whether the plan ticks it.
    static let loopTask = NSAttributedString.Key("LoopTask")
}

enum MarkdownStyler {
    enum Markup: String { case hidden, bullet }
    enum Block: String { case code, quote }

    static let bodyFont = NSFont.systemFont(ofSize: 15.5)
    /// Space reserved after a commented range's last character for each inline marker.
    static let markerAdvance: CGFloat = 21
    /// A task item's checkbox, and the room before its text that holds it.
    static let taskBox: CGFloat = 14
    static let taskBoxRoom: CGFloat = 23
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

    /// Styles the text with attributes, so comment ranges stay valid. Returns the hidden character indexes.
    /// Comment highlights are drawn by the text view; here comments only reserve room for their markers.
    /// Tables also swap a few characters for paragraph breaks (see `MarkdownTable`), so pass the plan's markdown as
    /// `source` once the storage has been styled before. Table columns are shared out for a text column `width` wide.
    @discardableResult
    static func apply(to storage: NSTextStorage, source: String? = nil, comments: [Comment],
                      width: CGFloat = textWidth) -> IndexSet {
        let text = source ?? storage.string
        let full = NSRange(location: 0, length: storage.length)
        var hidden = IndexSet()
        var code = IndexSet()
        var spans = IndexSet()
        func markup(_ range: NSRange, _ kind: Markup = .hidden) {
            guard range.location != NSNotFound, range.length > 0 else { return }
            storage.addAttribute(.loopMarkup, value: kind.rawValue, range: range)
            if kind == .hidden { hidden.insert(integersIn: range.location..<NSMaxRange(range)) }
        }
        var tableLines = IndexSet()
        func outsideCode(_ range: NSRange) -> Bool { !code.intersects(integersIn: range.location..<NSMaxRange(range)) }
        /// Block rules (headings, lists, quotes) never apply inside code or tables.
        func plain(_ range: NSRange) -> Bool {
            outsideCode(range) && !tableLines.intersects(integersIn: range.location..<NSMaxRange(range))
        }

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
        var swaps: [(index: Int, character: String)] = []
        var tables: [(table: MarkdownTable, grid: MeasuredTable)] = []
        for table in MarkdownTable.all(in: text, skipping: code) {
            tableLines.insert(integersIn: table.range.location..<NSMaxRange(table.range))
            let grid = style(table, in: storage, source: text as NSString, markup: { markup($0) },
                             hide: { hidden.insert(integersIn: $0.location..<NSMaxRange($0)) }, swap: { swaps.append(($0, $1)) })
            tables.append((table, grid))
        }
        // Blank lines only separate markdown blocks; paragraph spacing already does that visually.
        matches("(?m)^[ \\t]*\\n", text: text) { match in
            guard plain(match.range) else { return }
            storage.addAttribute(.paragraphStyle, value: paragraphStyle(after: 0, lineSpacing: 0, lineHeight: 1), range: match.range)
        }
        matches("(?m)^(#{1,6})([ \\t]+)(.+)$", text: text) { match in
            guard plain(match.range) else { return }
            let level = match.range(at: 1).length
            // No space before: the blank line and the previous paragraph's spacing already set a heading apart.
            let (font, after): (NSFont, CGFloat) =
                level == 1 ? (Theme.serif(30), 22)
                : level == 2 ? (Theme.serif(19), 8)
                : level == 3 ? (Theme.serif(16.5), 6)
                : (NSFont.systemFont(ofSize: 15.5, weight: .semibold), 4)
            storage.addAttributes([
                .font: font,
                .foregroundColor: Theme.heading,
                .paragraphStyle: paragraphStyle(after: after, lineSpacing: 4)
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
            guard plain(match.range) else { return }
            let nesting = CGFloat(match.range(at: 1).length) * 8
            storage.addAttribute(.paragraphStyle, value: paragraphStyle(after: 6, indent: nesting + 6 + bulletWidth,
                                                                       firstLine: nesting + 6), range: match.range)
            markup(match.range(at: 1))
            markup(match.range(at: 2), .bullet)
            storage.addAttribute(.foregroundColor, value: Theme.secondary, range: match.range(at: 2))
        }
        // Task items: `- [ ] ` is hidden, and the text view draws a checkbox in its place.
        matches("(?m)^([ \\t]*)[-*+][ \\t]+\\[([ xX])\\](?:[ \\t]+|$)", text: text) { match in
            guard plain(match.range) else { return }
            let line = (text as NSString).lineRange(for: match.range)
            let indent = CGFloat(match.range(at: 1).length) * 8 + 6 + taskBoxRoom
            storage.addAttribute(.paragraphStyle, value: paragraphStyle(after: 6, indent: indent), range: line)
            markup(match.range)
            let box = NSRange(location: match.range(at: 2).location - 1, length: 3)
            storage.addAttribute(.loopTask, value: (text as NSString).substring(with: match.range(at: 2)) != " ", range: box)
        }
        matches("(?m)^([ \\t]*)([0-9]+[.)])([ \\t]+).*$", text: text) { match in
            guard plain(match.range) else { return }
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
            guard plain(match.range) else { return }
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
        // Measured last, once bold, code and marker room have their final widths.
        for (table, grid) in tables {
            measure(table, into: grid, in: storage, hidden: hidden)
            spaceAfter(table, in: storage, text: text as NSString)
        }
        // A paragraph whose first glyph is null swallows the spacing after the paragraph before it, so a paragraph's
        // first hidden character becomes a zero-width space instead. Tables take care of their own cells.
        let lines = text as NSString
        var lineStart = 0
        while lineStart < lines.length {
            if hidden.contains(lineStart), !tableLines.contains(lineStart) {
                storage.removeAttribute(.loopMarkup, range: NSRange(location: lineStart, length: 1))
                swaps.append((lineStart, "\u{200B}"))
            }
            lineStart = NSMaxRange(lines.lineRange(for: NSRange(location: lineStart, length: 0)))
        }
        // Same-length swaps keep every index; each new character takes the attributes of the one it replaces.
        for swap in swaps where (storage.string as NSString).substring(with: NSRange(location: swap.index, length: 1)) != swap.character {
            storage.replaceCharacters(in: NSRange(location: swap.index, length: 1), with: swap.character)
        }
        fitTables(in: storage, width: width)
        storage.endEditing()
        return hidden
    }

    /// The text column of a full-width sheet.
    static let textWidth = Theme.sheetWidth - Theme.sheetPadding * 2
    static let tableFont = NSFont.systemFont(ofSize: 14)
    static let tableHeaderFont = NSFont.systemFont(ofSize: 14, weight: .semibold)

    /// Lays a table out as NSTextTable cells, ruled like a printed table: heavy rules above and below,
    /// a lighter one under the header and hairlines between rows, no vertical lines.
    private static func style(_ table: MarkdownTable, in storage: NSTextStorage, source: NSString, markup: (NSRange) -> Void,
                              hide: (NSRange) -> Void, swap: (Int, String) -> Void) -> MeasuredTable {
        let grid = MeasuredTable()
        grid.numberOfColumns = table.columns
        grid.layoutAlgorithm = .fixedLayoutAlgorithm
        grid.collapsesBorders = true
        grid.hidesEmptyCells = false
        grid.setContentWidth(100, type: .percentageValueType)
        // The heavy rules belong to the table, so a row with fewer cells than the header can't break them.
        grid.setWidth(1.2, type: .absoluteValueType, for: .border, edge: .minY)
        grid.setWidth(1.2, type: .absoluteValueType, for: .border, edge: .maxY)
        grid.setBorderColor(Theme.tableRule)
        for (number, row) in table.rows.enumerated() {
            let header = number == 0
            let last = number == table.rows.count - 1
            for (column, cell) in row.cells.enumerated() {
                let block = NSTextTableBlock(table: grid, startingRow: number, rowSpan: 1, startingColumn: column, columnSpan: 1)
                block.setWidth(tableCellPadding, type: .absoluteValueType, for: .padding)
                block.setWidth(header ? 7 : 8, type: .absoluteValueType, for: .padding, edge: .minY)
                block.setWidth(header ? 7 : 8, type: .absoluteValueType, for: .padding, edge: .maxY)
                if !last {
                    block.setWidth(header ? 1.2 : 0.5, type: .absoluteValueType, for: .border, edge: .maxY)
                    block.setBorderColor(header ? Theme.tableHeaderRule : Theme.rule, for: .maxY)
                }
                let style = NSMutableParagraphStyle()
                style.textBlocks = [block]
                style.alignment = table.alignments[column]
                style.lineSpacing = 4
                storage.addAttributes([
                    .paragraphStyle: style,
                    .font: header ? tableHeaderFont : tableFont,
                    .foregroundColor: header ? Theme.heading : Theme.ink
                ], range: cell.paragraph)
                // Everything around the content is syntax: pipes, padding spaces and, under the header, the |---| row.
                let content = cell.content
                for gap in [NSRange(location: cell.paragraph.location, length: content.location - cell.paragraph.location),
                            NSRange(location: NSMaxRange(content), length: cell.end - NSMaxRange(content))] where gap.length > 0 {
                    hide(gap)
                    var glyphless = IndexSet(integersIn: gap.location..<NSMaxRange(gap))
                    if let separator = cell.separator { glyphless.remove(separator) }
                    // A cell whose first glyph is null throws NSTextTable's layout off (every later cell stacks in
                    // one column), so the cell's first character becomes a zero-width space instead, as for paragraphs.
                    if gap.location == cell.paragraph.location {
                        glyphless.remove(gap.location)
                        swap(gap.location, "\u{200B}")
                    }
                    for run in glyphless.rangeView { markup(NSRange(location: run.lowerBound, length: run.count)) }
                }
                // `\|` is a pipe inside a cell; its backslash is syntax.
                for index in content.location..<NSMaxRange(content) where index > content.location
                    && source.character(at: index) == 0x7C && source.character(at: index - 1) == 0x5C {
                    hide(NSRange(location: index - 1, length: 1))
                    markup(NSRange(location: index - 1, length: 1))
                }
                // The pipe after a cell becomes its paragraph break; the layout manager needs that glyph as is.
                if let separator = cell.separator { swap(separator, "\u{2029}") }
            }
        }
        // The header's own line break would end the header cell early; the |---| row joins its last cell.
        swap(table.headerBreak, " ")
        return grid
    }

    static let tableCellPadding: CGFloat = 8

    /// How wide each column wants to be on one line, and how narrow it can get without breaking a word.
    /// A cell of up to 4.5 characters (a header, a short phrase) never breaks, unlike in a browser.
    private static func measure(_ table: MarkdownTable, into grid: MeasuredTable, in storage: NSTextStorage, hidden: IndexSet) {
        var natural = Array(repeating: CGFloat(14), count: table.columns)
        var minimum = Array(repeating: CGFloat(14), count: table.columns)
        let source = storage.string as NSString
        for row in table.rows {
            for (column, cell) in row.cells.enumerated() {
                var line: CGFloat = 0, word: CGFloat = 0, longest: CGFloat = 0
                let visible = IndexSet(integersIn: cell.content.location..<NSMaxRange(cell.content)).subtracting(hidden)
                for index in visible {
                    // Includes the room kerned for comment markers.
                    let advance = storage.attributedSubstring(from: NSRange(location: index, length: 1)).size().width
                    line += advance
                    let unit = source.character(at: index)
                    if unit == 0x20 || unit == 0x09 {
                        word = 0
                    } else if unit >= 0x2E80 {
                        // CJK text can break between any two characters.
                        word = advance
                    } else {
                        word += advance
                    }
                    longest = max(longest, word)
                }
                let font = storage.attribute(.font, at: cell.content.location, effectiveRange: nil) as? NSFont ?? tableFont
                // Summed glyph advances come out a little short of the typeset line; 3pt keeps a fitting cell on one line.
                natural[column] = max(natural[column], ceil(line) + 3)
                minimum[column] = max(minimum[column], ceil(longest) + 3, ceil(min(line, font.pointSize * 4.5)) + 3)
            }
        }
        grid.natural = natural
        grid.minimum = minimum
    }

    /// Shares a text column `width` wide among every table's columns the way browsers do: columns that fit keep
    /// their natural width, and when the text doesn't fit on one line each, the longer columns share what's left
    /// in proportion to how much they hold. Returns the characters to lay out again.
    @discardableResult
    static func fitTables(in storage: NSTextStorage, width: CGFloat) -> NSRange? {
        var tables: [ObjectIdentifier: (grid: MeasuredTable, blocks: [NSTextTableBlock])] = [:]
        var changed: NSRange?
        storage.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard let block = (value as? NSParagraphStyle)?.textBlocks.first as? NSTextTableBlock,
                  let grid = block.table as? MeasuredTable, grid.natural.count == grid.numberOfColumns else { return }
            tables[ObjectIdentifier(grid), default: (grid, [])].blocks.append(block)
            changed = changed.map { NSUnionRange($0, range) } ?? range
        }
        for (grid, blocks) in tables.values {
            let room = width - tableCellPadding * 2 * CGFloat(grid.numberOfColumns)
            let natural = grid.natural, minimum = grid.minimum
            let total = natural.reduce(0, +), least = minimum.reduce(0, +)
            let widths: [CGFloat]
            if total <= room {
                widths = natural.map { $0 * room / total }
            } else if least >= room {
                widths = minimum.map { $0 * room / least }
            } else {
                let spare = room - least, wanted = total - least
                widths = zip(minimum, natural).map { min, nat in min + (nat - min) * spare / wanted }
            }
            for block in blocks where block.startingColumn < widths.count {
                block.setValue(max(1, floor(widths[block.startingColumn])), type: .absoluteValueType, for: .width)
            }
        }
        return changed
    }

    /// Room between a table's bottom rule and whatever follows it.
    private static func spaceAfter(_ table: MarkdownTable, in storage: NSTextStorage, text: NSString) {
        let next = NSMaxRange(table.range)
        guard next < storage.length else { return }
        let paragraph = text.paragraphRange(for: NSRange(location: next, length: 0))
        let current = storage.attribute(.paragraphStyle, at: next, effectiveRange: nil) as? NSParagraphStyle ?? NSParagraphStyle()
        let style = current.mutableCopy() as! NSMutableParagraphStyle
        style.paragraphSpacingBefore = max(style.paragraphSpacingBefore, 22)
        storage.addAttribute(.paragraphStyle, value: style, range: paragraph)
    }

    /// The task items in a styled storage, with their text as shown.
    static func tasks(in storage: NSTextStorage, text: String, hidden: IndexSet) -> [TaskItem] {
        let source = text as NSString
        var items: [TaskItem] = []
        storage.enumerateAttribute(.loopTask, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard let checked = value as? Bool else { return }
            let line = source.lineRange(for: range)
            var start = NSMaxRange(range)
            while start < NSMaxRange(line), hidden.contains(start) { start += 1 }
            let label = CommentRanges.visibleText(of: NSRange(location: start, length: NSMaxRange(line) - start), in: text, hidden: hidden)
            items.append(TaskItem(location: range.location, labelStart: start, checked: checked,
                                  text: label.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        return items
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

/// A table that remembers how wide its columns want to be, so a new text width only shares them out again.
final class MeasuredTable: NSTextTable {
    var natural: [CGFloat] = []
    var minimum: [CGFloat] = []
}

/// A GitHub-style markdown table: a header row, a |---|---| delimiter row, then body rows until a line without a pipe.
///
/// NSTextTable needs one paragraph per cell, so the text view's copy of the plan swaps each pipe between
/// two cells for U+2029 (a paragraph break) and the header's newline for a space, folding the delimiter row
/// into the header's last cell. Every swap is one UTF-16 unit for one, so indexes match the markdown exactly.
struct MarkdownTable {
    struct Cell {
        /// The cell's paragraph once the swaps are made, from its first character through its paragraph break.
        let paragraph: NSRange
        /// The text inside the cell, without padding spaces.
        let content: NSRange
        /// Where the cell's hidden syntax ends: before a real newline, which stays one.
        let end: Int
        /// The pipe that becomes this cell's paragraph break; nil for a row's last cell.
        let separator: Int?
    }
    struct Row { let cells: [Cell] }

    let range: NSRange
    let rows: [Row]
    let alignments: [NSTextAlignment]
    /// The header line's newline.
    let headerBreak: Int
    var columns: Int { alignments.count }

    static func all(in text: String, skipping code: IndexSet) -> [MarkdownTable] {
        let source = text as NSString
        var lines: [(content: NSRange, enclosing: NSRange)] = []
        source.enumerateSubstrings(in: NSRange(location: 0, length: source.length), options: [.byLines, .substringNotRequired]) { _, content, enclosing, _ in
            lines.append((content, enclosing))
        }
        var tables: [MarkdownTable] = []
        var index = 0
        while index + 1 < lines.count {
            let head = lines[index], rule = lines[index + 1]
            guard !code.intersects(integersIn: head.enclosing.location..<NSMaxRange(rule.enclosing)),
                  NSMaxRange(head.content) < NSMaxRange(head.enclosing),
                  let alignments = delimiter(source.substring(with: rule.content)),
                  pipes(in: source, line: head.content).count > 0,
                  cellCount(in: source, line: head.content) == alignments.count else {
                index += 1
                continue
            }
            var rows = [row(in: source, line: head.content, paragraphEnd: NSMaxRange(rule.enclosing),
                            lineEnd: NSMaxRange(rule.content), columns: alignments.count)]
            var end = index + 2
            while end < lines.count, !code.contains(lines[end].content.location),
                  !pipes(in: source, line: lines[end].content).isEmpty {
                let line = lines[end]
                rows.append(row(in: source, line: line.content, paragraphEnd: NSMaxRange(line.enclosing),
                                lineEnd: NSMaxRange(line.content), columns: alignments.count))
                end += 1
            }
            let last = lines[end - 1]
            tables.append(MarkdownTable(range: NSRange(location: head.enclosing.location, length: NSMaxRange(last.enclosing) - head.enclosing.location),
                                rows: rows, alignments: alignments, headerBreak: NSMaxRange(head.content)))
            index = end
        }
        return tables
    }

    /// Alignments from a delimiter row like `| :--- | :---: | ---: |`; nil for any other line.
    private static func delimiter(_ line: String) -> [NSTextAlignment]? {
        var cells = line.trimmingCharacters(in: .whitespaces)
        guard cells.contains("|") else { return nil }
        if cells.hasPrefix("|") { cells.removeFirst() }
        if cells.hasSuffix("|") { cells.removeLast() }
        var alignments: [NSTextAlignment] = []
        for cell in cells.split(separator: "|", omittingEmptySubsequences: false) {
            let spec = cell.trimmingCharacters(in: .whitespaces)
            let dashes = spec.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            guard !dashes.isEmpty, dashes.allSatisfy({ $0 == "-" }), spec.count - dashes.count <= 2 else { return nil }
            let left = spec.hasPrefix(":"), right = spec.hasSuffix(":")
            alignments.append(left && right ? .center : right ? .right : .left)
        }
        return alignments
    }

    /// Unescaped pipes on a line.
    private static func pipes(in source: NSString, line: NSRange) -> [Int] {
        var found: [Int] = []
        var escaped = false
        for index in line.location..<NSMaxRange(line) {
            let unit = source.character(at: index)
            if unit == 0x7C, !escaped { found.append(index) }
            escaped = unit == 0x5C && !escaped
        }
        return found
    }

    private static func isPadding(_ unit: unichar) -> Bool { unit == 0x20 || unit == 0x09 }

    /// Pipes that start or end a line are borders; the ones in between separate cells.
    private static func separators(in source: NSString, line: NSRange) -> (leading: Int?, inner: [Int], trailing: Int?) {
        var inner = pipes(in: source, line: line)
        var start = line.location, end = NSMaxRange(line)
        while start < end, isPadding(source.character(at: start)) { start += 1 }
        while end > start, isPadding(source.character(at: end - 1)) { end -= 1 }
        let leading = inner.first == start ? inner.removeFirst() : nil
        let trailing = inner.last == end - 1 && end - 1 != leading ? inner.removeLast() : nil
        return (leading, inner, trailing)
    }

    private static func cellCount(in source: NSString, line: NSRange) -> Int {
        separators(in: source, line: line).inner.count + 1
    }

    /// A row's cells. Extra cells beyond the header's stay as text in the last one.
    private static func row(in source: NSString, line: NSRange, paragraphEnd: Int, lineEnd: Int, columns: Int) -> Row {
        let (leading, allInner, trailing) = separators(in: source, line: line)
        let inner = Array(allInner.prefix(columns - 1))
        var cells: [Cell] = []
        var start = line.location
        for (column, separator) in (inner.map(Optional.some) + [nil]).enumerated() {
            let lastCell = separator == nil
            var from = column == 0 ? (leading.map { $0 + 1 } ?? line.location) : start
            var to = separator ?? trailing ?? NSMaxRange(line)
            while from < to, isPadding(source.character(at: from)) { from += 1 }
            while to > from, isPadding(source.character(at: to - 1)) { to -= 1 }
            let paragraphEnd = separator.map { $0 + 1 } ?? paragraphEnd
            cells.append(Cell(paragraph: NSRange(location: start, length: paragraphEnd - start),
                              content: NSRange(location: from, length: to - from),
                              end: lastCell ? lineEnd : paragraphEnd, separator: separator))
            start = paragraphEnd
        }
        return Row(cells: cells)
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
