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

/// 总评, written once the whole plan has been read: a rounded capsule floating on the desk.
private struct FeedbackBar: View {
    @ObservedObject var store: SessionStore
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("总评")
                    .font(Font(Theme.serif(15)))
                    .foregroundStyle(Color(Theme.vermilion))
                Rectangle()
                    .fill(Color(Theme.rule))
                    .frame(width: 1, height: 15)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 2 }
                TextField(text: $store.general, prompt: Text("读完整份方案后的总体意见（可选）").foregroundStyle(Color(Theme.secondary)),
                          axis: .vertical) { Text("总评") }
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .foregroundStyle(Color(Theme.ink))
                    .lineLimit(1...4)
                    .focused($focused)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 13)
            .background(RoundedRectangle(cornerRadius: 23, style: .continuous).fill(Color(Theme.sheet)))
            .overlay(RoundedRectangle(cornerRadius: 23, style: .continuous)
                .strokeBorder(focused ? Color(Theme.vermilion).opacity(0.35) : Color(Theme.rule)))
            .shadow(color: .black.opacity(0.07), radius: 14, y: 6)
            .frame(maxWidth: 640)
            if let error = store.persistenceError {
                Text(error).font(.caption).foregroundStyle(Color(Theme.vermilion)).textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.top, 4)
        .padding(.bottom, 18)
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
