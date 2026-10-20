import SwiftUI

struct ContentView: View {
    @ObservedObject var store: SessionStore

    var body: some View {
        VStack(spacing: 0) {
            DocumentEditor(store: store)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            FeedbackBar(store: store)
        }
        .frame(minWidth: 600, minHeight: 440)
        .navigationTitle(store.review.map { "审阅 · \($0.title)" } ?? "Loop")
        .navigationSubtitle(subtitle)
        .toolbar {
            if store.review == nil {
                ToolbarItem(placement: .navigation) {
                    Button(action: store.requestNew) { Label("新建", systemImage: "square.and.pencil") }
                        .help("新建（⌘N）")
                }
            }
            // 提交 sends the whole review — every comment plus the general opinion — so it sits with the window's actions.
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: store.addComment) { Label("批注", systemImage: "text.bubble") }
                    .labelStyle(.titleAndIcon)
                    .disabled(!store.canAdd)
                    .help("添加批注（⌘↩）")
                Button { store.preview = true } label: { Label("预览", systemImage: "eye") }
                    .help(store.review == nil ? "预览导出内容" : "预览提交内容")
                if store.review != nil {
                    Button(action: store.requestSubmit) { Label("提交", systemImage: "paperplane.fill") }
                        .labelStyle(.titleAndIcon)
                        .buttonStyle(.borderedProminent)
                        .help("把全部批注和总体意见提交给 AI（⇧⌘↩）")
                } else {
                    Button(action: store.copyFeedback) { Label("复制反馈", systemImage: "doc.on.doc") }
                        .labelStyle(.titleAndIcon)
                        .buttonStyle(.borderedProminent)
                        .help("复制结构化反馈（⇧⌘C）")
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let toast = store.toast {
                Label(toast, systemImage: "checkmark.circle.fill")
                    .font(.callout)
                    .padding(.horizontal, 18).padding(.vertical, 12)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(color: .black.opacity(0.1), radius: 12, y: 4)
                    .padding(.bottom, 76)
                    .allowsHitTesting(false)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .sheet(isPresented: $store.preview) { ExportPreview(store: store) }
        .confirmationDialog("清空当前方案和批注？", isPresented: $store.confirmNew, titleVisibility: .visible) {
            Button("新建", role: .destructive, action: store.clear)
            Button("取消", role: .cancel) {}
        }
        .confirmationDialog("没有批注，直接提交？", isPresented: $store.confirmSubmit, titleVisibility: .visible) {
            Button("提交", action: store.submit)
            Button("取消", role: .cancel) {}
        } message: {
            Text("AI 会收到：\(ReviewRequest.approval)")
        }
    }

    private var subtitle: String {
        let count = store.comments.isEmpty ? "选中文字即可批注" : "\(store.comments.count) 条批注"
        return store.review == nil ? count : "\(count) · 提交后直接回传给 AI"
    }
}

/// The general opinion, written once the whole plan has been read.
private struct FeedbackBar: View {
    @ObservedObject var store: SessionStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "text.alignleft").foregroundStyle(.tertiary)
                TextField("总体意见（可选）", text: $store.general, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .lineLimit(1...5)
                    .accessibilityLabel("总体意见")
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.primary.opacity(0.08)))
            if let error = store.persistenceError {
                Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled)
            }
        }
        .frame(maxWidth: MarkdownStyler.columnWidth)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24).padding(.vertical, 12)
        .background(.bar)
    }
}

private struct ExportPreview: View {
    @ObservedObject var store: SessionStore
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(store.review == nil ? "预览导出" : "预览提交内容").font(.headline)
                Spacer()
                Button { store.preview = false } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).help("关闭").accessibilityLabel("关闭预览")
                    .keyboardShortcut(.cancelAction)
            }.padding(20)
            Divider()
            ScrollView {
                Text(store.review == nil ? store.exported : store.submission)
                    .font(.system(size: 14, design: .monospaced)).lineSpacing(6)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(24)
            }
            Divider()
            HStack {
                if let toast = store.toast { Text(toast).font(.callout).foregroundStyle(.secondary) }
                Spacer()
                if store.review == nil {
                    Button("复制", action: store.copyFeedback)
                        .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                } else {
                    Button("复制", action: store.copyFeedback)
                    Button("提交") { store.preview = false; store.requestSubmit() }
                        .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                }
            }.padding(16)
        }
        .frame(width: 700, height: 620)
    }
}
