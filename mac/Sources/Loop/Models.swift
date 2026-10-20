import Foundation

struct Comment: Identifiable, Codable, Equatable {
    var id = UUID()
    var location: Int
    var length: Int
    var quote: String
    var body: String

    var range: NSRange { NSRange(location: location, length: length) }
}

struct Session: Codable {
    var text = ""
    var comments: [Comment] = []
    /// 总评 notes, in the order they were written.
    var generals: [String] = []

    init(text: String = "", comments: [Comment] = [], generals: [String] = []) {
        self.text = text
        self.comments = comments
        self.generals = generals
    }

    private enum CodingKeys: String, CodingKey { case text, comments, generals, general }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        comments = try container.decodeIfPresent([Comment].self, forKey: .comments) ?? []
        // Drafts saved before 总评 became a list hold one `general` string.
        if let generals = try container.decodeIfPresent([String].self, forKey: .generals) {
            self.generals = generals
        } else if let general = try container.decodeIfPresent(String.self, forKey: .general), !general.isEmpty {
            generals = [general]
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(text, forKey: .text)
        try container.encode(comments, forKey: .comments)
        try container.encode(generals, forKey: .generals)
    }
}

/// Ranges are NSTextView's UTF-16 offsets, including emoji and composed text.
enum CommentRanges {
    /// The last visible character of a range, which carries the inline comment marker.
    static func markerRange(of range: NSRange, in text: String, hidden: IndexSet = IndexSet()) -> NSRange? {
        guard valid(range, in: text) else { return nil }
        let source = text as NSString
        var index = NSMaxRange(range) - 1
        while index > range.location, hidden.contains(index) || isSpace(source.character(at: index)) { index -= 1 }
        return source.rangeOfComposedCharacterSequence(at: index)
    }

    /// A selection without leading or trailing whitespace or hidden markdown, so highlights and quotes hug the words.
    static func trimmed(_ range: NSRange, in text: String, hidden: IndexSet = IndexSet()) -> NSRange? {
        guard valid(range, in: text) else { return nil }
        let source = text as NSString
        var start = range.location
        var end = NSMaxRange(range)
        while start < end, hidden.contains(start) || isSpace(source.character(at: start)) { start += 1 }
        while end > start, hidden.contains(end - 1) || isSpace(source.character(at: end - 1)) { end -= 1 }
        return end > start ? NSRange(location: start, length: end - start) : nil
    }

    /// The text of a range without the markdown syntax the editor hides.
    static func visibleText(of range: NSRange, in text: String, hidden: IndexSet) -> String {
        let source = text as NSString
        let visible = IndexSet(integersIn: range.location..<NSMaxRange(range)).subtracting(hidden)
        return visible.rangeView.map { source.substring(with: NSRange(location: $0.lowerBound, length: $0.count)) }.joined()
    }

    private static func isSpace(_ unit: unichar) -> Bool {
        UnicodeScalar(unit).map(CharacterSet.whitespacesAndNewlines.contains) ?? false
    }

    static func valid(_ range: NSRange, in text: String) -> Bool {
        let count = (text as NSString).length
        return range.location >= 0 && range.location != NSNotFound && range.length > 0
            && range.location <= count && range.length <= count - range.location
    }
}
