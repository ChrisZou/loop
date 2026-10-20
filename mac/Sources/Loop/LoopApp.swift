import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var store: SessionStore?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store?.saveNow()
        // Closing a review without submitting must not look like an approval to the waiting agent.
        if let store, !store.submitted {
            FileHandle.standardError.write(Data("Loop：未提交，批注已暂存，再次打开同一方案会恢复\n".utf8))
            exit(1)
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct LoopApp: App {
    /// Set by `LoopMain` before launch: Loop always opens exactly one review.
    static var launchStore: SessionStore!

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = LoopApp.launchStore

    var body: some Scene {
        Window("Loop", id: "main") {
            ContentView(store: store)
                .tint(Color(red: 0.24, green: 0.38, blue: 0.68))
                .onAppear { delegate.store = store }
        }
        .defaultSize(width: 1080, height: 800)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("批注") {
                Button("添加批注") {
                    if store.draft != nil { store.saveDraft() } else { store.addComment() }
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(store.draft == nil ? !store.canAdd : store.draftBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Divider()
                Button("预览提交内容") { store.preview = true }
                Button("提交", action: store.requestSubmit)
                    .keyboardShortcut(.return, modifiers: [.command, .shift])
            }
        }
    }
}

@main
enum LoopMain {
    static func main() {
        if CommandLine.arguments.contains("--selftest") {
            SelfTest.run()
            return
        }
        let env = ProcessInfo.processInfo.environment
        if env["LOOP_DEMO"] == "1" {
            let store = SessionStore(review: Demo.review, restoring: Demo.session)
            store.preview = env["LOOP_DEMO_PREVIEW"] == "1"
            LoopApp.launchStore = store
        } else {
            do {
                guard let request = try ReviewRequest.parse(CommandLine.arguments) else { explainUsage() }
                LoopApp.launchStore = SessionStore(review: request)
            } catch {
                FileHandle.standardError.write(Data("Loop：\(error.localizedDescription)\n".utf8))
                exit(64)
            }
        }
        LoopApp.main()
    }

    /// Opened from Finder or without arguments: there is nothing to review, so say how reviews start.
    private static func explainUsage() -> Never {
        FileHandle.standardError.write(Data("用法：loop review <方案.md>\n".utf8))
        let delegate = UsageDelegate()
        NSApplication.shared.delegate = delegate
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.run()
        exit(64)
    }
}

/// The alert waits for launch to finish, so it comes to the front like any other app window.
private final class UsageDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Loop 用来审阅 AI 发来的方案"
        alert.informativeText = "由 AI 在终端运行 loop review 方案.md 打开审阅窗口。逐条批注后点「提交」，反馈会直接回到 AI。"
        alert.runModal()
        exit(64)
    }
}
