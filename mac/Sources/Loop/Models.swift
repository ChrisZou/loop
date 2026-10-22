import Foundation

struct Comment: Identifiable, Codable, Equatable {
    var id = UUID()
    var location: Int
    var length: Int
    var quote: String
    var body: String
    /// Absolute paths of the images attached to the comment.
    var images: [String] = []

    var range: NSRange { NSRange(location: location, length: length) }
}

extension Comment {
    private enum CodingKeys: String, CodingKey { case id, location, length, quote, body, images }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        location = try container.decode(Int.self, forKey: .location)
        length = try container.decode(Int.self, forKey: .length)
        quote = try container.decode(String.self, forKey: .quote)
        body = try container.decode(String.self, forKey: .body)
        // Drafts saved before images could be attached have none.
        images = try container.decodeIfPresent([String].self, forKey: .images) ?? []
    }
}

/// A 总评 note: text, images, or both.
struct GeneralNote: Codable, Equatable, ExpressibleByStringLiteral {
    var text: String
    /// Absolute paths of the attached images.
    var images: [String] = []

    init(text: String, images: [String] = []) {
        self.text = text
        self.images = images
    }

    init(stringLiteral text: String) { self.init(text: text) }

    var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && images.isEmpty }

    private enum CodingKeys: String, CodingKey { case text, images }

    // A note without images is stored as a bare string, as every note was before images.
    init(from decoder: Decoder) throws {
        if let text = try? decoder.singleValueContainer().decode(String.self) {
            self.init(text: text)
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(text: try container.decodeIfPresent(String.self, forKey: .text) ?? "",
                  images: try container.decodeIfPresent([String].self, forKey: .images) ?? [])
    }

    func encode(to encoder: Encoder) throws {
        if images.isEmpty {
            var container = encoder.singleValueContainer()
            try container.encode(text)
        } else {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(text, forKey: .text)
            try container.encode(images, forKey: .images)
        }
    }
}

/// A `- [ ]` or `- [x]` item in the plan.
struct TaskItem: Equatable {
    /// The `[`, which also keys the reviewer's toggles.
    let location: Int
    /// Where the item's text starts, after the hidden `- [ ] `.
    let labelStart: Int
    /// Ticked in the plan itself.
    let checked: Bool
    /// The item's text as shown, for the feedback.
    let text: String
}

struct Session: Codable {
    var text = ""
    var comments: [Comment] = []
    /// 总评 notes, in the order they were written.
    var generals: [GeneralNote] = []
    /// Task items the reviewer ticked or unticked, by `TaskItem.location`.
    var toggled: [Int] = []

    init(text: String = "", comments: [Comment] = [], generals: [GeneralNote] = [], toggled: [Int] = []) {
        self.text = text
        self.comments = comments
        self.generals = generals
        self.toggled = toggled
    }

    private enum CodingKeys: String, CodingKey { case text, comments, generals, general, toggled }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        comments = try container.decodeIfPresent([Comment].self, forKey: .comments) ?? []
        // Drafts saved before 总评 became a list hold one `general` string.
        if let generals = try container.decodeIfPresent([GeneralNote].self, forKey: .generals) {
            self.generals = generals
        } else if let general = try container.decodeIfPresent(String.self, forKey: .general), !general.isEmpty {
            generals = [GeneralNote(text: general)]
        }
        toggled = try container.decodeIfPresent([Int].self, forKey: .toggled) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(text, forKey: .text)
        try container.encode(comments, forKey: .comments)
        try container.encode(generals, forKey: .generals)
        try container.encode(toggled, forKey: .toggled)
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

    /// The text of a range without the markdown syntax the editor hides. Table cells on one line stay
    /// apart as `a | b`; rows keep their line breaks.
    static func visibleText(of range: NSRange, in text: String, hidden: IndexSet) -> String {
        let source = text as NSString
        let visible = IndexSet(integersIn: range.location..<NSMaxRange(range)).subtracting(hidden)
        var result = ""
        var previous: Range<Int>?
        for run in visible.rangeView {
            if let previous, previous.upperBound < run.lowerBound,
               source.substring(with: NSRange(location: previous.upperBound, length: run.lowerBound - previous.upperBound)).contains("|"),
               source.character(at: previous.upperBound - 1) != 0x0A, source.character(at: run.lowerBound) != 0x0A {
                result += " | "
            }
            result += source.substring(with: NSRange(location: run.lowerBound, length: run.count))
            previous = run
        }
        return result
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
