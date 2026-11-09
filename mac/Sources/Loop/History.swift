import Foundation

/// One submitted review kept for the cold-start history home.
struct HistoryEntry: Identifiable, Codable, Equatable {
    enum Channel: String, Codable, Equatable {
        case mac
        case web

        var label: String {
            switch self {
            case .mac: return "本机"
            case .web: return "网页"
            }
        }
    }

    var id: UUID
    var title: String
    var agentName: String
    var channel: Channel
    var document: String
    var feedback: String
    /// ISO-8601 instant when the reviewer submitted.
    var submittedAt: String
    var sourcePath: String?

    init(id: UUID = UUID(), title: String, agentName: String, channel: Channel,
         document: String, feedback: String, submittedAt: String, sourcePath: String? = nil) {
        self.id = id
        self.title = title
        self.agentName = agentName
        self.channel = channel
        self.document = document
        self.feedback = feedback
        self.submittedAt = submittedAt
        self.sourcePath = sourcePath
    }
}

extension HistoryEntry {
    private func formatted(_ pattern: String, _ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }

    private var date: Date? { HistoryStore.parseDate(submittedAt) }

    /// 今天, 昨天, 11月2日; the year only when it isn't this one.
    func dayLabel(now: Date = Date(), calendar: Calendar = .current) -> String {
        guard let date else { return "更早" }
        if calendar.isDate(date, inSameDayAs: now) { return "今天" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) { return "昨天" }
        return formatted(calendar.isDate(date, equalTo: now, toGranularity: .year) ? "M月d日" : "yyyy年M月d日", date)
    }

    func timeLabel() -> String? { date.map { formatted("M月d日 HH:mm", $0) } }

    /// The plan without its first heading when that heading is already shown as the title.
    var documentBody: String {
        let lines = document.components(separatedBy: "\n")
        guard let first = lines.firstIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }), lines[first].hasPrefix("# "),
              lines[first].dropFirst(2).replacingOccurrences(of: "*", with: "").replacingOccurrences(of: "`", with: "")
                .trimmingCharacters(in: .whitespaces) == title else { return document }
        return lines[(first + 1)...].joined(separator: "\n").trimmingCharacters(in: .newlines)
    }
}

/// A submission's text read back into the parts `FeedbackExporter` wrote.
struct FeedbackNotes: Equatable {
    struct Mark: Equatable {
        var quote: String
        var body = ""
        var images: [String] = []
    }

    var marks: [Mark] = []
    var checks: [(text: String, checked: Bool)] = []
    var closing: String?
    var closingImages: [String] = []
    /// Submitted with no changes asked for.
    var approved = false
    /// Text in no format this knows, shown as it is.
    var plain: String?

    var hasRemarks: Bool { !marks.isEmpty || closing != nil || approved || plain != nil }

    static func == (lhs: FeedbackNotes, rhs: FeedbackNotes) -> Bool {
        lhs.marks == rhs.marks && lhs.closing == rhs.closing && lhs.approved == rhs.approved && lhs.plain == rhs.plain
            && lhs.checks.map(\.text) == rhs.checks.map(\.text) && lhs.checks.map(\.checked) == rhs.checks.map(\.checked)
    }

    init(_ feedback: String) {
        let text = feedback.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if text == ReviewRequest.approval { approved = true; return }
        let closingPrefix = "总体意见：", checksPrefix = "待办的勾选状态改为："
        let sections = text.components(separatedBy: "\n\n")
        guard sections[0].hasPrefix("以下是我对你方案的逐条反馈") else { plain = text; return }
        for (index, section) in sections.enumerated().dropFirst() {
            if section.hasPrefix(closingPrefix) {
                // Last section, and a single note may hold blank lines of its own.
                let rest = sections[index...].joined(separator: "\n\n").dropFirst(closingPrefix.count)
                let (body, images) = Self.separateImages(String(rest))
                closing = body.isEmpty ? nil : body
                closingImages = images
                break
            }
            if section.hasPrefix(checksPrefix) {
                checks = section.components(separatedBy: "\n").dropFirst().compactMap { line in
                    guard line.hasPrefix("- ["), line.count > 6 else { return nil }
                    return (String(line.dropFirst(6)), line.dropFirst(3).first == "x")
                }
                continue
            }
            guard let mark = Self.mark(section) else {
                self = FeedbackNotes(plain: text)
                return
            }
            marks.append(mark)
        }
    }

    private init(plain: String) { self.plain = plain }

    private static func mark(_ section: String) -> Mark? {
        let lines = section.components(separatedBy: "\n")
        guard lines[0].range(of: #"^\d+\. 原文：$"#, options: .regularExpression) != nil else { return nil }
        var quote: [String] = []
        var body: [String] = []
        var images: [String] = []
        var inBody = false
        for line in lines.dropFirst() {
            if line.hasPrefix("   附图：") {
                images.append(String(line.dropFirst(6)))
            } else if line.hasPrefix("   意见：") {
                inBody = true
                body.append(String(line.dropFirst(6)))
            } else if inBody {
                body.append(String(line.dropFirst(3)))
            } else if line.hasPrefix("   > ") {
                quote.append(String(line.dropFirst(5)))
            } else {
                return nil
            }
        }
        return Mark(quote: quote.joined(separator: "\n"), body: body.joined(separator: "\n"), images: images)
    }

    private static func separateImages(_ text: String) -> (String, [String]) {
        var kept: [String] = []
        var images: [String] = []
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("附图：") { images.append(String(trimmed.dropFirst(3))) } else { kept.append(line) }
        }
        return (kept.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines), images)
    }
}

/// Submitted reviews under Application Support/Loop/history/, one JSON file each.
struct HistoryStore {
    var root: URL

    static var shared = HistoryStore(root: ReviewRequest.support.appendingPathComponent("history"))

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder = JSONDecoder()

    private static let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoBasic: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func nowISO() -> String {
        iso.string(from: Date())
    }

    static func parseDate(_ value: String) -> Date? {
        iso.date(from: value) ?? isoBasic.date(from: value)
    }

    func fileURL(for id: UUID) -> URL {
        root.appendingPathComponent("\(id.uuidString.lowercased()).json")
    }

    /// Newest submission first.
    func load() -> [HistoryEntry] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: root.path) else { return [] }
        var entries: [HistoryEntry] = []
        for name in names where name.hasSuffix(".json") {
            let url = root.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: url),
                  let entry = try? Self.decoder.decode(HistoryEntry.self, from: data) else { continue }
            entries.append(entry)
        }
        return entries.sorted { lhs, rhs in
            let left = Self.parseDate(lhs.submittedAt) ?? .distantPast
            let right = Self.parseDate(rhs.submittedAt) ?? .distantPast
            if left != right { return left > right }
            return lhs.id.uuidString > rhs.id.uuidString
        }
    }

    func append(_ entry: HistoryEntry) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let data = try Self.encoder.encode(entry)
        try data.write(to: fileURL(for: entry.id), options: .atomic)
    }
}
