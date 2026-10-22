import Foundation

enum FeedbackExporter {
    static func export(text: String, comments: [Comment], general: String, hidden: IndexSet = IndexSet()) -> String {
        export(text: text, comments: comments, generals: [GeneralNote(text: general)], hidden: hidden)
    }

    /// Quotes leave out `hidden` markdown syntax, so they read the way the plan looked on screen.
    /// `checks` are the task items whose box the reviewer changed, with their new state.
    /// Attached images go in as their paths, one `附图：` line each, for the agent to open.
    static func export(text: String, comments: [Comment], generals: [GeneralNote], hidden: IndexSet = IndexSet(),
                       checks: [(text: String, checked: Bool)] = []) -> String {
        let sorted = comments.enumerated().sorted {
            $0.element.location == $1.element.location
                ? $0.offset < $1.offset : $0.element.location < $1.element.location
        }.map(\.element)
        let notes = generals.map { GeneralNote(text: $0.text.trimmingCharacters(in: .whitespacesAndNewlines), images: $0.images) }
            .filter { !$0.isEmpty }
        var intro = "以下是我对你方案的逐条反馈，请据此修改出下一版："
        if comments.contains(where: { !$0.images.isEmpty }) || notes.contains(where: { !$0.images.isEmpty }) {
            intro += "\n（「附图」是本机上的图片文件，请打开查看。）"
        }
        var sections = [intro]
        for (index, comment) in sorted.enumerated() {
            let quote = CommentRanges.valid(comment.range, in: text)
                ? CommentRanges.visibleText(of: comment.range, in: text, hidden: hidden) : comment.quote
            var quoteLines = lines(quote)
            // A selection that ran past a line end must not leave an empty quote line.
            while quoteLines.count > 1, quoteLines.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { quoteLines.removeLast() }
            while quoteLines.count > 1, quoteLines.first?.trimmingCharacters(in: .whitespaces).isEmpty == true { quoteLines.removeFirst() }
            let quoted = quoteLines.map { "   > " + $0 }.joined(separator: "\n")
            var entry = "\(index + 1). 原文：\n\(quoted)"
            let body = comment.body.trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty { entry += "\n   意见：" + lines(body).joined(separator: "\n   ") }
            entry += images(comment.images, indent: "   ")
            sections.append(entry)
        }
        if !checks.isEmpty {
            let items = checks.map { "- [\($0.checked ? "x" : " ")] " + lines($0.text).joined(separator: " ") }
            sections.append((["待办的勾选状态改为："] + items).joined(separator: "\n"))
        }
        if notes.count == 1 {
            sections.append("总体意见：\(notes[0].text)" + images(notes[0].images, indent: ""))
        } else if notes.count > 1 {
            let numbered = notes.enumerated().map { index, note in
                let text = lines(note.text).joined(separator: "\n   ")
                let pictures = images(note.images, indent: "   ")
                // A note that is only images starts its first 附图 line right after the number.
                return "\(index + 1). " + (text.isEmpty ? String(pictures.dropFirst(4)) : text + pictures)
            }
            sections.append((["总体意见："] + numbered).joined(separator: "\n"))
        }
        return sections.joined(separator: "\n\n")
    }

    private static func images(_ paths: [String], indent: String) -> String {
        paths.map { "\n\(indent)附图：\($0)" }.joined()
    }

    private static func lines(_ value: String) -> [String] {
        value.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n")
    }
}
