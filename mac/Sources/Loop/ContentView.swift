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

    // 提交 sends the whole review — every comment plus the 总评 — so it sits with the window's actions.
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

/// 总评, written once the whole plan has been read. The composer files each note into the list above it
/// with ⌘↩ and empties itself for the next one; Return starts a new line. Both are as wide as the sheet.
private struct FeedbackBar: View {
    @ObservedObject var store: SessionStore
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 8) {
            if !store.generals.isEmpty { notes }
            composer
            if let error = store.persistenceError {
                Text(error).font(.caption).foregroundStyle(Color(Theme.vermilion)).textSelection(.enabled)
            }
        }
        // Exactly as wide as the sheet above, and on the same axis even when a scroller narrows the plan.
        .frame(width: store.sheet.width)
        .offset(x: store.sheet.offset)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.top, 4)
        .padding(.bottom, 18)
        .animation(.snappy(duration: 0.22), value: store.generals)
        .onChange(of: focused) { _, isFocused in store.composingGeneral = isFocused }
    }

    private var notes: some View {
        let rows = VStack(spacing: 0) {
            ForEach(Array(store.generals.enumerated()), id: \.offset) { index, note in
                if index > 0 { Rectangle().fill(Color(Theme.rule)).frame(height: 1).padding(.leading, 48) }
                GeneralNoteRow(number: index + 1, note: note, editing: store.editingGeneral == index,
                               edit: { store.editGeneral(at: index); focused = true },
                               remove: { store.removeGeneral(at: index) })
            }
        }
        return Group {
            if store.generals.count > 3 {
                ScrollView { rows }.frame(height: 150)
            } else {
                rows
            }
        }
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(Theme.sheet)))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color(Theme.rule)))
        .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    private var composer: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("总评")
                .font(Font(Theme.serif(15)))
                .foregroundStyle(Color(Theme.vermilion))
            Rectangle()
                .fill(Color(Theme.rule))
                .frame(width: 1, height: 15)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 2 }
            // A hidden copy of the text sets the height (up to six lines) and the baseline the labels align to;
            // the editor laid over it scrolls past six lines.
            Text(store.generalDraft.isEmpty || store.generalDraft.hasSuffix("\n") ? store.generalDraft + " " : store.generalDraft)
                .font(.system(size: 14)).lineSpacing(3)
                .lineLimit(6)
                .padding(.horizontal, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .hidden()
                .accessibilityHidden(true)
                .overlay(alignment: .topLeading) {
                    if store.generalDraft.isEmpty {
                        Text(store.generals.isEmpty ? "读完整份方案后的总体意见（可选）" : "再写一条总评…")
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
                            // Esc drops a change to a saved note; a new note keeps its text and just steps away.
                            if store.editingGeneral != nil { store.cancelGeneral() } else { focused = false }
                        }
                }
            if let index = store.editingGeneral {
                Text("修改第 \(index + 1) 条").font(.system(size: 11.5, weight: .medium)).foregroundStyle(Color(Theme.vermilion)).fixedSize()
            }
            if focused || !store.generalDraft.isEmpty {
                Text("⌘↩ 保存").font(.system(size: 11.5)).foregroundStyle(Color(Theme.secondary)).fixedSize()
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 13)
        .background(RoundedRectangle(cornerRadius: 23, style: .continuous).fill(Color(Theme.sheet)))
        .overlay(RoundedRectangle(cornerRadius: 23, style: .continuous)
            .strokeBorder(focused ? Color(Theme.vermilion).opacity(0.35) : Color(Theme.rule)))
        .shadow(color: .black.opacity(0.07), radius: 14, y: 6)
    }
}

/// One saved 总评 note: click to change it in the composer, or delete it.
private struct GeneralNoteRow: View {
    let number: Int
    let note: String
    let editing: Bool
    let edit: () -> Void
    let remove: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(number)")
                .font(Font(Theme.serif(14)))
                .foregroundStyle(Color(Theme.vermilion))
                .frame(width: 16)
            Text(note)
                .font(.system(size: 13.5)).lineSpacing(2)
                .foregroundStyle(Color(Theme.ink))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            if editing {
                Text("修改中").font(.system(size: 11.5, weight: .medium)).foregroundStyle(Color(Theme.vermilion))
            } else if hovering {
                HStack(spacing: 10) {
                    Button(action: edit) { Image(systemName: "pencil") }
                        .help("修改这条总评").accessibilityLabel("修改第 \(number) 条总评")
                    Button(action: remove) { Image(systemName: "trash") }
                        .help("删除这条总评").accessibilityLabel("删除第 \(number) 条总评")
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Color(Theme.secondary))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color(Theme.vermilion).opacity(editing ? 0.06 : 0))
        .contentShape(Rectangle())
        .onTapGesture(perform: edit)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("第 \(number) 条总评：\(note)")
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
