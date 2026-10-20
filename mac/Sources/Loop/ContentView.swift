import SwiftUI

struct ContentView: View {
    @ObservedObject var store: SessionStore

    var body: some View {
        VStack(spacing: 0) {
            DocumentEditor(store: store)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .bottom) {
                    // The sheet sinks into the desk instead of stopping at a hard edge.
                    LinearGradient(colors: [Color(Theme.ground).opacity(0), Color(Theme.ground)], startPoint: .top, endPoint: .bottom)
                        .frame(height: 24)
                        .allowsHitTesting(false)
                }
            FeedbackBar(store: store)
        }
        .background(Color(Theme.ground).ignoresSafeArea())
        .frame(minWidth: 600, minHeight: 440)
        .navigationTitle(store.documentTitle)
        .toolbar { toolbar }
        .toolbarBackground(.hidden, for: .windowToolbar)
        .sheet(isPresented: $store.preview) { SubmissionPreview(store: store) }
        .confirmationDialog("没有批注，直接提交？", isPresented: $store.confirmSubmit, titleVisibility: .visible) {
            Button("提交", action: store.submit)
            Button("取消", role: .cancel) {}
        } message: {
            Text("AI 会收到：\(ReviewRequest.approval)")
        }
    }

    /// Plain toolbar items: on macOS 26 they would otherwise sit on glass capsules.
    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        if #available(macOS 26, *) {
            ToolbarItem(placement: .principal) { title }.sharedBackgroundVisibility(.hidden)
            ToolbarItem(placement: .primaryAction) { actions }.sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .principal) { title }
            ToolbarItem(placement: .primaryAction) { actions }
        }
    }

    private var title: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(store.documentTitle)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(Theme.heading))
                .lineLimit(1)
            Text(store.comments.isEmpty ? "审阅中" : "审阅中 · \(store.comments.count) 处批注")
                .font(.system(size: 11.5))
                .foregroundStyle(Color(Theme.secondary))
                .monospacedDigit()
        }
    }

    // 提交 sends the whole review — every comment plus the general opinion — so it sits with the window's actions.
    private var actions: some View {
        HStack(spacing: 2) {
            Button(action: store.addComment) { Label("批注", systemImage: "pencil") }
                .buttonStyle(PlainToolButtonStyle())
                .disabled(!store.canAdd)
                .help("添加批注（⌘↩）")
            Button { store.preview = true } label: { Label("预览", systemImage: "doc.text") }
                .buttonStyle(PlainToolButtonStyle())
                .help("预览提交内容")
            Button(action: store.requestSubmit) {
                HStack(spacing: 7) {
                    Text("提交")
                    Image(systemName: "arrow.right").font(.system(size: 11, weight: .bold))
                }
            }
            .buttonStyle(InkButtonStyle())
            .padding(.leading, 6)
            .help("把全部批注和总评提交给 AI（⇧⌘↩）")
        }
        .labelStyle(.titleAndIcon)
    }
}

/// 总评, written once the whole plan has been read: a rounded capsule as wide as the sheet.
/// Like a comment it is saved explicitly — ⌘↩, or clicking elsewhere — and Return starts a new line.
private struct FeedbackBar: View {
    @ObservedObject var store: SessionStore
    @FocusState private var focused: Bool
    @State private var hovering = false
    private static let placeholder = "读完整份方案后的总体意见（可选）"

    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .top, spacing: 12) {
                Text("总评")
                    .font(Font(Theme.serif(15)))
                    .foregroundStyle(Color(Theme.vermilion))
                Rectangle()
                    .fill(Color(Theme.rule))
                    .frame(width: 1, height: 15)
                    .padding(.top, 3)
                if store.editingGeneral { editor } else { saved }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 13)
            .background(RoundedRectangle(cornerRadius: 23, style: .continuous).fill(Color(Theme.sheet)))
            .overlay(RoundedRectangle(cornerRadius: 23, style: .continuous)
                .strokeBorder(store.editingGeneral ? Color(Theme.vermilion).opacity(0.35) : Color(Theme.rule)))
            .shadow(color: .black.opacity(0.07), radius: 14, y: 6)
            // Exactly as wide as the sheet above, and on the same axis even when a scroller narrows the plan.
            .frame(width: store.sheet.width)
            .offset(x: store.sheet.offset)
            if let error = store.persistenceError {
                Text(error).font(.caption).foregroundStyle(Color(Theme.vermilion)).textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.top, 4)
        .padding(.bottom, 18)
        .onChange(of: focused) { _, isFocused in
            // Clicking elsewhere keeps what was typed, like a comment card.
            if !isFocused { store.saveGeneral() }
        }
    }

    private var editor: some View {
        HStack(alignment: .top, spacing: 10) {
            // A hidden copy of the text sets the height, up to six lines; the editor laid over it scrolls past that.
            Text(store.generalDraft.isEmpty || store.generalDraft.hasSuffix("\n") ? store.generalDraft + " " : store.generalDraft)
                .font(.system(size: 14)).lineSpacing(3)
                .lineLimit(6)
                .padding(.horizontal, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .hidden()
                .accessibilityHidden(true)
                .overlay(alignment: .topLeading) {
                    if store.generalDraft.isEmpty {
                        Text(Self.placeholder)
                            .font(.system(size: 14))
                            .foregroundStyle(Color(Theme.secondary))
                            .padding(.horizontal, 5)
                            .allowsHitTesting(false)
                    }
                }
                .overlay {
                TextEditor(text: $store.generalDraft)
                    .font(.system(size: 14)).lineSpacing(3)
                    .foregroundStyle(Color(Theme.ink))
                    .scrollContentBackground(.hidden)
                    .scrollIndicators(.never)
                    .focused($focused)
                    .accessibilityLabel("总评")
                    .onExitCommand {
                        store.cancelGeneral()
                        focused = false
                    }
                }
            Text("⌘↩ 保存")
                .font(.system(size: 11.5))
                .foregroundStyle(Color(Theme.secondary))
                .padding(.top, 1)
                .fixedSize()
        }
        .onAppear { DispatchQueue.main.async { focused = true } }
    }

    private var saved: some View {
        Button(action: store.beginGeneral) {
            HStack(alignment: .top, spacing: 10) {
                Text(store.general.isEmpty ? Self.placeholder : store.general)
                    .font(.system(size: 14)).lineSpacing(3)
                    .foregroundStyle(Color(store.general.isEmpty ? Theme.secondary : Theme.ink))
                    .lineLimit(4)
                    .padding(.horizontal, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !store.general.isEmpty {
                    Label(hovering ? "修改" : "已保存", systemImage: hovering ? "pencil" : "checkmark")
                        .labelStyle(.titleAndIcon)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Color(hovering ? Theme.secondary : Theme.vermilion))
                        .padding(.top, 1)
                        .fixedSize()
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(store.general.isEmpty ? "填写总评" : "点击修改总评")
        .accessibilityLabel(store.general.isEmpty ? "填写总评" : "总评：\(store.general)，点击修改")
    }
}

private struct SubmissionPreview: View {
    @ObservedObject var store: SessionStore
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("预览提交内容").font(Font(Theme.serif(17))).foregroundStyle(Color(Theme.heading))
                Spacer()
                Button { store.preview = false } label: { Image(systemName: "xmark") }
                    .buttonStyle(PlainToolButtonStyle())
                    .help("关闭").accessibilityLabel("关闭预览")
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 24).padding(.vertical, 16)
            Divider()
            ScrollView {
                Text(store.submission)
                    .font(.system(size: 14)).lineSpacing(7)
                    .foregroundStyle(Color(Theme.ink))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(28)
            }
            .background(Color(Theme.sheet))
            Divider()
            HStack {
                Spacer()
                Button { store.preview = false; store.requestSubmit() } label: {
                    HStack(spacing: 7) { Text("提交"); Image(systemName: "arrow.right").font(.system(size: 11, weight: .bold)) }
                }
                .buttonStyle(InkButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 680, height: 600)
        .background(Color(Theme.ground))
    }
}
