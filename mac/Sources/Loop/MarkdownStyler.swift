import AppKit

enum MarkdownStyler {
    static let bodyFont = NSFont.systemFont(ofSize: 15)
    static var paragraph: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 6
        style.paragraphSpacing = 4
        return style
    }
    static var base: [NSAttributedString.Key: Any] {
        [.font: bodyFont, .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph]
    }

    static func apply(to storage: NSTextStorage, comments: [Comment], activeID: UUID?, draft: Comment?) {
        let text = storage.string
        let full = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.setAttributes(base, range: full)
        matches("(?m)^(#{1,6})[ \\t]+(.+)$", text: text) { match in
            let level = match.range(at: 1).length
            let size: CGFloat = level == 1 ? 27 : (level == 2 ? 21 : 17)
            storage.addAttribute(.font, value: NSFont.systemFont(ofSize: size, weight: .semibold), range: match.range)
            storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: match.range(at: 1))
        }
        matches("(?m)^[ \\t]*(?:[-*+] |[0-9]+[.)] ).*$", text: text) { match in
            let style = paragraph.mutableCopy() as! NSMutableParagraphStyle
            style.headIndent = 18
            storage.addAttribute(.paragraphStyle, value: style, range: match.range)
        }
        matches("\\*\\*([^\\n]+?)\\*\\*", text: text) { match in
            storage.addAttribute(.font, value: NSFont.systemFont(ofSize: 15, weight: .bold), range: match.range)
        }
        matches("`([^`\\n]+)`", text: text) { match in
            storage.addAttributes([
                .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular),
                .foregroundColor: NSColor.systemIndigo,
                .backgroundColor: NSColor.quaternaryLabelColor.withAlphaComponent(0.08)
            ], range: match.range)
        }
        // Paint inactive ranges first so overlapping active ranges remain visible.
        let ranges = comments.filter { $0.id != activeID && $0.id != draft?.id }
            + comments.filter { $0.id == activeID && $0.id != draft?.id }
            + (draft.map { [$0] } ?? [])
        for comment in ranges where CommentRanges.valid(comment.range, in: text) {
            let active = comment.id == activeID
            storage.addAttribute(.backgroundColor,
                                 value: NSColor.systemYellow.withAlphaComponent(active ? 0.48 : 0.22),
                                 range: comment.range)
        }
        storage.endEditing()
    }

    private static func matches(_ pattern: String, text: String, apply: (NSTextCheckingResult) -> Void) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        for match in regex.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length)) { apply(match) }
    }
}
