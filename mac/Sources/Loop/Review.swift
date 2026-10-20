import Foundation
import CryptoKit

/// `Loop --review <plan> [--out <file>]`: an agent hands a plan to the user and gets the feedback back on submit.
struct ReviewRequest {
    static let approval = "我看过了这版方案，没有修改意见，可以按这版继续。"

    let source: URL
    let output: URL?
    let text: String

    enum ParseError: LocalizedError {
        case missingValue(String)
        case unreadable(String, Error)
        var errorDescription: String? {
            switch self {
            case .missingValue(let flag): return "\(flag) 缺少参数"
            case .unreadable(let path, let error): return "无法读取 \(path)：\(error.localizedDescription)"
            }
        }
    }

    static func parse(_ arguments: [String]) throws -> ReviewRequest? {
        func value(after flag: String) throws -> String? {
            guard let index = arguments.firstIndex(of: flag) else { return nil }
            guard index + 1 < arguments.count, !arguments[index + 1].hasPrefix("--") else { throw ParseError.missingValue(flag) }
            return arguments[index + 1]
        }
        guard let path = try value(after: "--review") else { return nil }
        let source = URL(fileURLWithPath: path).standardizedFileURL
        let text: String
        do { text = try String(contentsOf: source, encoding: .utf8) } catch { throw ParseError.unreadable(path, error) }
        let output = try value(after: "--out").map { URL(fileURLWithPath: $0).standardizedFileURL }
        return ReviewRequest(source: source, output: output, text: text)
    }

    var title: String { source.lastPathComponent }

    /// Unsubmitted comments survive an accidental close and come back when the same plan is reviewed again.
    var draftURL: URL {
        let digest = SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Loop/reviews/\(digest.prefix(16)).json")
    }

    func deliver(_ feedback: String) throws {
        let data = Data((feedback + "\n").utf8)
        if let output { try data.write(to: output, options: .atomic) } else { FileHandle.standardOutput.write(data) }
    }
}
