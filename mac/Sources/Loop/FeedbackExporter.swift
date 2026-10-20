import Foundation

enum FeedbackExporter {
    /// Quotes leave out `hidden` markdown syntax, so they read the way the plan looked on screen.
    static func export(text: String, comments: [Comment], general: String, hidden: IndexSet = IndexSet()) -> String {
        let sorted = comments.enumerated().sorted {
            $0.element.location == $1.element.location
                ? $0.offset < $1.offset : $0.element.location < $1.element.location
        }.map(\.element)
        var sections = ["以下是我对你方案的逐条反馈，请据此修改出下一版："]
        for (index, comment) in sorted.enumerated() {
            let quote = CommentRanges.valid(comment.range, in: text)
                ? CommentRanges.visibleText(of: comment.range, in: text, hidden: hidden) : comment.quote
            var quoteLines = lines(quote)
            // A selection that ran past a line end must not leave an empty quote line.
            while quoteLines.count > 1, quoteLines.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { quoteLines.removeLast() }
            while quoteLines.count > 1, quoteLines.first?.trimmingCharacters(in: .whitespaces).isEmpty == true { quoteLines.removeFirst() }
            let quoted = quoteLines.map { "   > " + $0 }.joined(separator: "\n")
            let body = lines(comment.body).joined(separator: "\n   ")
            sections.append("\(index + 1). 原文：\n\(quoted)\n   意见：\(body)")
        }
        let general = general.trimmingCharacters(in: .whitespacesAndNewlines)
        if !general.isEmpty { sections.append("总体意见：\(general)") }
        return sections.joined(separator: "\n\n")
    }

    private static func lines(_ value: String) -> [String] {
        value.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n")
    }
}
