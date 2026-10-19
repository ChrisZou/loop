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
    var general = ""
}

enum CommentRanges {
    /// NSTextView offsets and lengths are UTF-16, including emoji and composed text.
    static func adjusted(_ range: NSRange, replacing edit: NSRange, withLength count: Int) -> NSRange? {
        let start = range.location
        let end = NSMaxRange(range)
        let editEnd = NSMaxRange(edit)
        let delta = count - edit.length
        if edit.length == 0 {
            if edit.location <= start { return NSRange(location: start + count, length: range.length) }
            if edit.location < end { return NSRange(location: start, length: range.length + count) }
            return range
        }
        if editEnd <= start { return NSRange(location: start + delta, length: range.length) }
        if edit.location >= end { return range }
        if edit.location <= start && editEnd >= end { return nil }
        let newStart = start < edit.location ? start : edit.location
        let newEnd = end >= editEnd ? end + delta : edit.location + count
        return newEnd > newStart ? NSRange(location: newStart, length: newEnd - newStart) : nil
    }

    /// The last visible character of a range, which carries the inline comment marker.
    static func markerRange(of range: NSRange, in text: String, hidden: IndexSet = IndexSet()) -> NSRange? {
        guard valid(range, in: text) else { return nil }
        let source = text as NSString
        var index = NSMaxRange(range) - 1
        while index > range.location, hidden.contains(index) || isSpace(source.character(at: index)) { index -= 1 }
        return source.rangeOfComposedCharacterSequence(at: index)
    }

    /// A selection without leading or trailing whitespace, so highlights and quotes hug the words.
    static func trimmed(_ range: NSRange, in text: String) -> NSRange? {
        guard valid(range, in: text) else { return nil }
        let source = text as NSString
        var start = range.location
        var end = NSMaxRange(range)
        while start < end, isSpace(source.character(at: start)) { start += 1 }
        while end > start, isSpace(source.character(at: end - 1)) { end -= 1 }
        return end > start ? NSRange(location: start, length: end - start) : nil
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
