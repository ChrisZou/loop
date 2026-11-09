import Darwin
import Foundation

struct SetupStep: Identifiable, Equatable {
    enum Kind: Equatable {
        case cli
        case path(profile: URL)
        case skill(directory: URL)
    }

    let kind: Kind
    let title: String
    let detail: String
    var done: Bool
    var id: String { title }
}

enum SetupError: LocalizedError {
    case occupied(String)
    case translocated
    case notOnPath(String)

    var errorDescription: String? {
        switch self {
        case .occupied(let path): "\(path) 已被占用，移走后重试"
        case .translocated: "请先把 Loop 拖到“应用程序”文件夹，再重新打开"
        case .notOnPath(let directory): "请把 \(directory) 加入 PATH 后重试"
        }
    }
}

/// Puts the bundled `loop` command and agent skill where agents can find them. Both are symlinks into the app,
/// so they follow app updates, and moving the app leaves dangling links that the next launch repairs.
struct AgentSetup {
    let home: URL
    let resources: URL
    let bundlePath: String
    let shell: String
    /// Directories already on PATH that package managers install `loop` into.
    let systemBins: [URL]

    private var fm: FileManager { .default }

    static var current: AgentSetup {
        let env = ProcessInfo.processInfo.environment
        // LOOP_SETUP_HOME exercises the flow without touching the real home directory.
        let home = env["LOOP_SETUP_HOME"].map { URL(fileURLWithPath: $0) } ?? fm_home
        let resources = Bundle.main.resourceURL ?? Bundle.main.bundleURL
        let shell = getpwuid(getuid()).flatMap { String(validatingUTF8: $0.pointee.pw_shell) } ?? "/bin/zsh"
        return AgentSetup(home: home, resources: resources, bundlePath: Bundle.main.bundlePath, shell: shell,
                          systemBins: [URL(fileURLWithPath: "/opt/homebrew/bin"), URL(fileURLWithPath: "/usr/local/bin")])
    }

    private static var fm_home: URL { FileManager.default.homeDirectoryForCurrentUser }

    private var cliSource: URL { resources.appendingPathComponent("loop") }
    private var skillSource: URL { resources.appendingPathComponent("skills/loop-review") }
    private var binDirectory: URL { home.appendingPathComponent(".local/bin") }
    private var cliLink: URL { binDirectory.appendingPathComponent("loop") }

    /// False when running outside the app bundle (`swift run`), where there is nothing to install from.
    var isBundled: Bool {
        fm.isExecutableFile(atPath: cliSource.path)
            && fm.fileExists(atPath: skillSource.appendingPathComponent("SKILL.md").path)
    }

    var cliInstalled: Bool {
        ([binDirectory] + systemBins).contains { isLoopCLI($0.appendingPathComponent("loop")) }
    }

    /// One skill per agent present on this Mac; Claude Code when none is yet.
    private var skillTargets: [(title: String, locations: [URL])] {
        // The first location is where to install; any of them counts as installed.
        let agents: [(title: String, root: String, locations: [String])] = [
            ("Claude Code Skill", ".claude", [".claude/skills/loop-review"]),
            // Codex documents ~/.agents/skills and still reads the older ~/.codex/skills.
            ("Codex Skill", ".codex", [".agents/skills/loop-review", ".codex/skills/loop-review"]),
            ("WorkBuddy Skill", ".workbuddy", [".workbuddy/skills/loop-review"]),
        ]
        let present = agents.filter { fm.fileExists(atPath: home.appendingPathComponent($0.root).path) }
        return (present.isEmpty ? [agents[0]] : present).map { agent in
            (title: agent.title, locations: agent.locations.map { home.appendingPathComponent($0) })
        }
    }

    func steps(pathProfile: URL?) -> [SetupStep] {
        var steps = [SetupStep(kind: .cli, title: "命令行工具", detail: display(cliLink), done: cliInstalled)]
        if let pathProfile {
            steps.append(SetupStep(kind: .path(profile: pathProfile), title: "PATH", detail: display(pathProfile), done: false))
        }
        steps += skillTargets.map { target in
            SetupStep(kind: .skill(directory: target.locations[0]), title: target.title, detail: display(target.locations[0]),
                      done: target.locations.contains { fm.fileExists(atPath: $0.appendingPathComponent("SKILL.md").path) })
        }
        return steps
    }

    /// The file to edit so a login shell finds `~/.local/bin`; nil when it already does.
    func profileNeeded(loginPath: String?) -> URL? {
        if let loginPath, onPath(loginPath) { return nil }
        return profile
    }

    func perform(_ step: SetupStep) throws {
        guard !bundlePath.contains("/AppTranslocation/") else { throw SetupError.translocated }
        switch step.kind {
        case .cli:
            try link(cliLink, to: cliSource)
        case .path(let profile):
            try append(pathLine, to: profile)
            if let loginPath = loginPath(), !onPath(loginPath) { throw SetupError.notOnPath(display(binDirectory)) }
        case .skill(let directory):
            try link(directory, to: skillSource)
        }
    }

    /// The PATH an agent started from the user's shell sees. Nil if the shell can't be asked.
    func loginPath() -> String? {
        let output = fm.temporaryDirectory.appendingPathComponent("loop-path-\(UUID().uuidString)")
        guard fm.createFile(atPath: output.path, contents: nil), let handle = try? FileHandle(forWritingTo: output) else { return nil }
        defer { try? handle.close(); try? fm.removeItem(at: output) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-ilc", "printf '__LOOP_PATH__%s__LOOP_END__' \"$PATH\""]
        process.environment = ProcessInfo.processInfo.environment.merging(["HOME": home.path]) { $1 }
        process.standardInput = FileHandle.nullDevice
        // A file, not a pipe: something the shell's rc files leave running would hold a pipe open forever.
        process.standardOutput = handle
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        DispatchQueue.global().asyncAfter(deadline: .now() + 5) { if process.isRunning { process.terminate() } }
        process.waitUntilExit()

        guard let text = try? String(contentsOf: output, encoding: .utf8),
              let start = text.range(of: "__LOOP_PATH__"),
              let end = text.range(of: "__LOOP_END__", range: start.upperBound..<text.endIndex) else { return nil }
        return String(text[start.upperBound..<end.lowerBound])
    }

    private func onPath(_ loginPath: String) -> Bool {
        loginPath.split(separator: ":").contains { $0 == binDirectory.path || $0 == binDirectory.path + "/" }
    }

    private var shellName: String { URL(fileURLWithPath: shell).lastPathComponent }

    private var profile: URL {
        switch shellName {
        case "zsh": home.appendingPathComponent(".zshenv")
        case "bash": home.appendingPathComponent(".bash_profile")
        case "fish": home.appendingPathComponent(".config/fish/conf.d/loop.fish")
        default: home.appendingPathComponent(".profile")
        }
    }

    private var pathLine: String {
        shellName == "fish" ? "fish_add_path -g \"$HOME/.local/bin\"" : "export PATH=\"$HOME/.local/bin:$PATH\""
    }

    /// Appends through a file handle: an atomic rewrite would replace a dotfile-manager symlink with a plain file.
    private func append(_ line: String, to file: URL) throws {
        try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !fm.fileExists(atPath: file.path) { fm.createFile(atPath: file.path, contents: nil) }
        if let existing = try? String(contentsOf: file, encoding: .utf8), existing.contains(line) { return }
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("\n# Added by Loop\n\(line)\n".utf8))
    }

    /// Links `path` to `target`, replacing only a dangling symlink and never anything the user put there.
    private func link(_ path: URL, to target: URL) throws {
        if fm.fileExists(atPath: path.path) { throw SetupError.occupied(display(path)) }
        if (try? fm.destinationOfSymbolicLink(atPath: path.path)) != nil { try fm.removeItem(at: path) }
        try fm.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: path, withDestinationURL: target)
    }

    private func isLoopCLI(_ url: URL) -> Bool {
        guard fm.isExecutableFile(atPath: url.path), let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let head = (try? handle.read(upToCount: 512)) ?? nil
        return head.map { String(decoding: $0, as: UTF8.self).contains("# loop review") } ?? false
    }

    private func display(_ url: URL) -> String {
        url.path.hasPrefix(home.path + "/") ? "~" + url.path.dropFirst(home.path.count) : url.path
    }
}

/// Runs the setup off the main thread and publishes each step as it completes.
final class SetupModel: ObservableObject {
    @Published private(set) var steps: [SetupStep]
    @Published private(set) var ready = false
    @Published private(set) var installing = false
    @Published private(set) var error: String?
    @Published private(set) var finished: Bool

    private let setup: AgentSetup

    init(setup: AgentSetup = .current) {
        self.setup = setup
        let steps = setup.steps(pathProfile: nil)
        self.steps = steps
        finished = !setup.isBundled || steps.allSatisfy(\.done)
    }

    /// Asking the login shell for PATH can take a second, so it only happens once the setup page is showing.
    func prepare() {
        guard !finished, !ready else { return }
        if setup.cliInstalled { ready = true; return }
        let setup = setup
        DispatchQueue.global(qos: .userInitiated).async {
            let profile = setup.profileNeeded(loginPath: setup.loginPath())
            DispatchQueue.main.async {
                self.steps = setup.steps(pathProfile: profile)
                self.ready = true
            }
        }
    }

    func install() {
        guard ready, !installing else { return }
        installing = true
        error = nil
        let setup = setup
        let pending = steps.filter { !$0.done }
        DispatchQueue.global(qos: .userInitiated).async {
            for step in pending {
                do {
                    try setup.perform(step)
                } catch {
                    DispatchQueue.main.async {
                        self.error = error.localizedDescription
                        self.installing = false
                    }
                    return
                }
                DispatchQueue.main.async {
                    if let index = self.steps.firstIndex(where: { $0.id == step.id }) { self.steps[index].done = true }
                }
            }
            // Long enough to see the last tick land before the page goes.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
                self.installing = false
                self.finished = true
            }
        }
    }
}
