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
        if let store, store.review != nil, !store.submitted {
            FileHandle.standardError.write(Data("Loop：未提交，批注已暂存，再次打开同一方案会恢复\n".utf8))
            exit(1)
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct LoopApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = SessionStore(review: ReviewRequest.current)

    var body: some Scene {
        Window("Loop", id: "main") {
            ContentView(store: store)
                .tint(Color(red: 0.24, green: 0.38, blue: 0.68))
                .onAppear { delegate.store = store }
        }
        .defaultSize(width: 1200, height: 800)
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
                if store.review != nil {
                    Button("提交", action: store.requestSubmit)
                        .keyboardShortcut(.return, modifiers: [.command, .shift])
                }
                Button("导出反馈", action: store.copyFeedback)
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                Button("预览导出") { store.preview = true }
                Divider()
                Button("新建", action: store.requestNew).keyboardShortcut("n", modifiers: .command)
                    .disabled(store.review != nil)
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
        do { ReviewRequest.current = try ReviewRequest.parse(CommandLine.arguments) } catch {
            FileHandle.standardError.write(Data("Loop：\(error.localizedDescription)\n".utf8))
            exit(64)
        }
        LoopApp.main()
    }
}
