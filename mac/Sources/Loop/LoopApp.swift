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

    func applicationWillTerminate(_ notification: Notification) { store?.saveNow() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct LoopApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = SessionStore()

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
                Button("导出反馈", action: store.copyFeedback)
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                Button("预览导出") { store.preview = true }
                Divider()
                Button("新建", action: store.requestNew).keyboardShortcut("n", modifiers: .command)
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
        LoopApp.main()
    }
}
