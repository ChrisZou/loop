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
    static func markerRange(of range: NSRange, in text: String) -> NSRange? {
        guard valid(range, in: text) else { return nil }
        let source = text as NSString
        var index = NSMaxRange(range) - 1
        while index > range.location,
              let scalar = UnicodeScalar(source.character(at: index)),
              CharacterSet.whitespacesAndNewlines.contains(scalar) { index -= 1 }
        return source.rangeOfComposedCharacterSequence(at: index)
    }

    static func valid(_ range: NSRange, in text: String) -> Bool {
        let count = (text as NSString).length
        return range.location >= 0 && range.location != NSNotFound && range.length > 0
            && range.location <= count && range.length <= count - range.location
    }
}
