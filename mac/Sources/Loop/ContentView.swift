import SwiftUI

struct ContentView: View {
    @ObservedObject var store: SessionStore

    var body: some View {
        HSplitView {
            DocumentEditor(store: store)
                .frame(minWidth: 430, maxWidth: .infinity, maxHeight: .infinity)
            sidebar
                .frame(minWidth: 290, idealWidth: 320, maxWidth: 340, maxHeight: .infinity)
        }
        .frame(minWidth: 780, minHeight: 520)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button(action: store.requestNew) { Label("新建", systemImage: "square.and.pencil") }
                    .help("新建（⌘N）")
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: store.addComment) { Label("批注", systemImage: "text.bubble") }
                    .labelStyle(.titleAndIcon)
                    .disabled(!store.canAdd)
                    .help("添加批注（⌘↩）")
                Button { store.preview = true } label: { Label("预览导出", systemImage: "doc.text.magnifyingglass") }
                    .help("预览导出")
            }
            ToolbarItem(placement: .primaryAction) {
                Button(action: store.copyFeedback) { Label("导出反馈", systemImage: "square.and.arrow.up") }
                    .labelStyle(.titleAndIcon)
                    .buttonStyle(.borderedProminent)
                    .help("导出反馈（⇧⌘C）")
            }
        }
        .overlay(alignment: .bottom) {
            if let toast = store.toast {
                Label(toast, systemImage: "checkmark.circle.fill")
                    .font(.callout)
                    .padding(.horizontal, 18).padding(.vertical, 12)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(color: .black.opacity(0.1), radius: 12, y: 4)
                    .padding(.bottom, 22)
                    .allowsHitTesting(false)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .sheet(isPresented: $store.preview) { ExportPreview(store: store) }
        .confirmationDialog("清空当前方案和批注？", isPresented: $store.confirmNew, titleVisibility: .visible) {
            Button("新建", role: .destructive, action: store.clear)
            Button("取消", role: .cancel) {}
        }
    }

    private var displayedComments: [Comment] {
        var comments = store.comments
        if let draft = store.draft {
            comments.removeAll { $0.id == draft.id }
            comments.append(draft)
        }
        return comments.sorted { $0.location < $1.location }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Text("批注").font(.headline)
                Text("\(store.comments.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 18).padding(.vertical, 17)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if displayedComments.isEmpty {
                            Text("选中文字后按 ⌘↩ 添加批注")
                                .font(.callout).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 22)
                        }
                        ForEach(displayedComments) { comment in
                            CommentCard(store: store, comment: comment)
                                .id(comment.id)
                        }
                    }
                    .padding(14)
                }
                .onChange(of: store.editorFocus) { _, _ in
                    if let id = store.draft?.id {
                        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .center) }
                    }
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                Text("总体意见").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                TextEditor(text: $store.general)
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(height: 100)
                    .background(.background.opacity(0.65), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.primary.opacity(0.07)))
                    .accessibilityLabel("总体意见")
                if let error = store.persistenceError {
                    Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled)
                }
            }
            .padding(16)
        }
        .background(.bar)
    }
}

private struct CommentCard: View {
    @ObservedObject var store: SessionStore
    let comment: Comment
    @FocusState private var focused: Bool
    private var editing: Bool { store.draft?.id == comment.id }
    private var active: Bool { store.activeID == comment.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { store.navigate(to: comment) } label: {
                HStack(alignment: .top, spacing: 9) {
                    RoundedRectangle(cornerRadius: 2).fill(Color.accentColor.opacity(0.55)).frame(width: 3)
                    Text(comment.quote)
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                        .lineLimit(3).multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .fixedSize(horizontal: false, vertical: true)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("定位原文")
            if editing {
                TextEditor(text: $store.draftBody)
                    .font(.system(size: 14))
                    .scrollContentBackground(.hidden)
                    .padding(5)
                    .frame(minHeight: 100, maxHeight: 160)
                    .background(.background, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.accentColor.opacity(0.35)))
                    .focused($focused)
                    .accessibilityLabel("批注意见")
                    .onExitCommand(perform: store.cancelDraft)
                    .onAppear {
                        // Existing cards mount the editor after their editing state changes.
                        DispatchQueue.main.async { focused = true }
                    }
                HStack {
                    Button("取消", action: store.cancelDraft).buttonStyle(.plain).foregroundStyle(.secondary)
                    Spacer()
                    Button("保存", action: store.saveDraft)
                        .buttonStyle(.borderedProminent)
                        .disabled(store.draftBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .help("保存（⌘↩）")
                }
            } else {
                Button { store.navigate(to: comment) } label: {
                    Text(comment.body).font(.system(size: 14))
                        .lineSpacing(4).multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain)
                HStack(spacing: 14) {
                    Spacer()
                    Button { store.edit(comment) } label: { Image(systemName: "pencil") }
                        .help("编辑批注").accessibilityLabel("编辑批注")
                        .disabled(store.draft != nil)
                    Button { store.remove(comment.id) } label: { Image(systemName: "trash") }
                        .help("删除批注").accessibilityLabel("删除批注")
                }
                .buttonStyle(.plain).foregroundStyle(.secondary).font(.system(size: 12))
            }
        }
        .padding(14)
        .background(.background.opacity(active ? 1 : 0.75), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(active ? Color.accentColor.opacity(0.55) : .primary.opacity(0.07), lineWidth: active ? 1.5 : 1))
        .contentShape(Rectangle())
        .gesture(
            TapGesture().onEnded { store.navigate(to: comment) },
            including: editing ? .subviews : .all
        )
        .contextMenu {
            Button("定位原文") { store.navigate(to: comment) }
            Button("编辑批注") { store.edit(comment) }.disabled(store.draft != nil)
            Button("删除批注", role: .destructive) { store.remove(comment.id) }
        }
        .onAppear { if editing { focused = true } }
        .onChange(of: editing) { _, value in focused = value }
        .onChange(of: store.editorFocus) { _, _ in if editing { focused = true } }
    }
}

private struct ExportPreview: View {
    @ObservedObject var store: SessionStore
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("预览导出").font(.headline)
                Spacer()
                Button { store.preview = false } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).help("关闭").accessibilityLabel("关闭预览")
                    .keyboardShortcut(.cancelAction)
            }.padding(20)
            Divider()
            ScrollView {
                Text(store.exported)
                    .font(.system(size: 14, design: .monospaced)).lineSpacing(6)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(24)
            }
            Divider()
            HStack {
                if let toast = store.toast { Text(toast).font(.callout).foregroundStyle(.secondary) }
                Spacer()
                Button("复制", action: store.copyFeedback)
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }.padding(16)
        }
        .frame(width: 700, height: 620)
    }
}
