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
