import SwiftUI

private struct QuoteLine: View {
    let quote: String
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 2).fill(Color.accentColor.opacity(0.55)).frame(width: 3)
            Text(quote)
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .lineLimit(3).multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Shown while hovering an inline marker or its highlighted text.
struct CommentPreview: View {
    let comment: Comment
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            QuoteLine(quote: comment.quote)
            Text(comment.body)
                .font(.system(size: 14)).lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Text("点击序号圆标编辑").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(14)
        .frame(width: 300)
        .tint(Color(nsColor: MarkdownStyler.accent))
    }
}

/// Edits `store.draft`, for both new comments and existing ones.
struct CommentEditorPopover: View {
    @ObservedObject var store: SessionStore
    @FocusState private var focused: Bool

    private var existing: Bool { store.comments.contains { $0.id == store.draft?.id } }
    private var empty: Bool { store.draftBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            QuoteLine(quote: store.draft?.quote ?? "")
            TextEditor(text: $store.draftBody)
                .font(.system(size: 14))
                .lineSpacing(3)
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(height: 100)
                .overlay(alignment: .topLeading) {
                    if store.draftBody.isEmpty {
                        Text("写下你的意见…").font(.system(size: 14)).foregroundStyle(.tertiary)
                            .padding(.leading, 11).padding(.top, 6).allowsHitTesting(false)
                    }
                }
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor.opacity(0.35)))
                .focused($focused)
                .accessibilityLabel("批注意见")
                .onExitCommand(perform: store.cancelDraft)
            HStack {
                if existing, let id = store.draft?.id {
                    Button(role: .destructive) { store.remove(id) } label: { Image(systemName: "trash") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                        .help("删除批注").accessibilityLabel("删除批注")
                }
                Spacer()
                Button("取消", action: store.cancelDraft).buttonStyle(.plain).foregroundStyle(.secondary)
                Button { store.saveDraft() } label: {
                    HStack(spacing: 4) { Text("保存"); Text("⌘↩").font(.caption).opacity(0.7) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(empty)
                .help("保存（⌘↩）")
            }
        }
        .padding(16)
        .frame(width: 340)
        .tint(Color(nsColor: MarkdownStyler.accent))
        .onAppear { DispatchQueue.main.async { focused = true } }
    }
}
