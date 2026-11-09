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
        // History home has no review session.
        guard let store else { return }
        // A 总评 still in the composer is kept as a note, like a comment card left open.
        store.saveGeneral()
        store.saveNow()
        // Closing a review without submitting must not look like an approval to the waiting agent.
        if !store.submitted {
            FileHandle.standardError.write(Data("Loop：未提交，批注已暂存，再次打开同一方案会恢复\n".utf8))
            exit(1)
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct LoopApp: App {
    /// Set by `LoopMain` before launch. Nil opens the approval-history home.
    static var launchStore: SessionStore?

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("Loop", id: "main") {
            Group {
                if let store = Self.launchStore {
                    ContentView(store: store)
                        .onAppear { delegate.store = store }
                } else {
                    HomeGate()
                }
            }
            .tint(Color(Theme.vermilion))
        }
        .defaultSize(width: 1080, height: 800)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CommandGroup(replacing: .newItem) {}
            if let store = Self.launchStore {
                CommandMenu("批注") {
                    Button(store.draft != nil ? "保存批注" : store.composingGeneral ? "保存总评" : "添加批注", action: store.commitShortcut)
                        .keyboardShortcut(.return, modifiers: .command)
                        .disabled(!store.canCommitShortcut)
                    Divider()
                    Button("预览提交内容") { store.preview = true }
                    Button("提交", action: store.requestSubmit)
                        .keyboardShortcut(.return, modifiers: [.command, .shift])
                }
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
                if let request = try ReviewRequest.parse(CommandLine.arguments) {
                    LoopApp.launchStore = SessionStore(review: request)
                } else {
                    LoopApp.launchStore = nil
                }
            } catch {
                FileHandle.standardError.write(Data("Loop：\(error.localizedDescription)\n".utf8))
                exit(64)
            }
        }
        LoopApp.main()
    }
}
