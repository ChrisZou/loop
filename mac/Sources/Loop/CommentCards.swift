import SwiftUI
import AppKit

/// A card floating over the plan inside the editor. Not an NSPopover (no arrow, sheet-like look) and not a
/// separate window, so the plan's window keeps its active look while a comment is being written.
final class CardView: NSHostingView<AnyView> {
    /// Room around the card for its shadow.
    static let shadowRoom: CGFloat = 24
    /// A preview never takes the pointer, or hovering would flicker between the text and the card.
    var passesClicks = false

    override func hitTest(_ point: NSPoint) -> NSView? { passesClicks ? nil : super.hitTest(point) }

    func show<Content: View>(_ content: Content, below anchor: NSRect, in textView: NSView) {
        rootView = AnyView(content
            .shadow(color: .black.opacity(0.13), radius: 18, y: 8)
            .padding(Self.shadowRoom))
        isHidden = false
        place(below: anchor, in: textView)
    }

    /// Hangs the card just under `anchor` (in `textView`'s coordinates), or above it near the bottom edge.
    func place(below anchor: NSRect, in textView: NSView) {
        guard let parent = superview, !isHidden else { return }
        let size = fittingSize
        let room = Self.shadowRoom
        // The parent is unflipped: minY is the anchor's visual bottom.
        let target = parent.convert(anchor, from: textView)
        var origin = NSPoint(x: target.midX - size.width / 2, y: target.minY - 6 + room - size.height)
        origin.x = min(max(origin.x, 8 - room), parent.bounds.width - size.width - 8 + room)
        if origin.y < 8 - room { origin.y = min(target.maxY + 6 - room, parent.bounds.height - size.height + room - 8) }
        frame = NSRect(origin: origin, size: size)
    }

    func contains(windowPoint: NSPoint) -> Bool {
        !isHidden && bounds.insetBy(dx: Self.shadowRoom, dy: Self.shadowRoom).contains(convert(windowPoint, from: nil))
    }

    func focusFirstTextView() {
        // SwiftUI sets focus a beat later; typing must go straight into the comment either way.
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window,
                  !((window.firstResponder as? NSView)?.isDescendant(of: self) ?? false),
                  let editor = Self.firstTextView(in: self) else { return }
            window.makeFirstResponder(editor)
        }
    }

    func dismiss() {
        isHidden = true
        rootView = AnyView(EmptyView())
    }

    private static func firstTextView(in view: NSView) -> NSTextView? {
        if let text = view as? NSTextView, text.isEditable { return text }
        for subview in view.subviews { if let text = firstTextView(in: subview) { return text } }
        return nil
    }
}

private struct NumberBadge: View {
    let number: Int
    var body: some View {
        Text("\(number)")
            .font(.system(size: number >= 10 ? 8.5 : 10, weight: .bold, design: .serif))
            .foregroundStyle(Color(Theme.onVermilion))
            .frame(width: 16, height: 16)
            .background(Circle().fill(Color(Theme.vermilion)))
            .accessibilityLabel("第 \(number) 条")
    }
}

private struct CardTitle: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 11.5, weight: .semibold)).tracking(1).foregroundStyle(Color(Theme.vermilion))
    }
}

private struct QuoteText: View {
    let quote: String
    var body: some View {
        Text("「\(quote)」")
            .font(Font(Theme.serif(12.5, weight: .regular)))
            .foregroundStyle(Color(Theme.secondary))
            .lineSpacing(2)
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private extension View {
    func card(width: CGFloat) -> some View {
        padding(.horizontal, 16).padding(.vertical, 14)
            .frame(width: width, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(Theme.sheet)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color(Theme.rule)))
    }
}

/// Shown while hovering a comment's marker or its highlighted text.
struct CommentPreview: View {
    let comment: Comment
    let number: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                NumberBadge(number: number)
                CardTitle(text: "批注")
                Spacer(minLength: 12)
                Text("点击圈码修改").font(.system(size: 11)).foregroundStyle(Color(Theme.secondary))
            }
            QuoteText(quote: comment.quote)
            Text(comment.body)
                .font(.system(size: 14)).lineSpacing(4)
                .foregroundStyle(Color(Theme.ink))
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card(width: 310)
    }
}

/// Edits `store.draft`, for both new comments and existing ones.
struct CommentEditorCard: View {
    @ObservedObject var store: SessionStore
    let number: Int
    @FocusState private var focused: Bool

    private var existing: Bool { store.comments.contains { $0.id == store.draft?.id } }
    private var empty: Bool { store.draftBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                NumberBadge(number: number)
                CardTitle(text: existing ? "修改批注" : "批注")
                Spacer()
                if existing, let id = store.draft?.id {
                    Button(role: .destructive) { store.remove(id) } label: {
                        Image(systemName: "trash").font(.system(size: 12))
                    }
                    .buttonStyle(.plain).foregroundStyle(Color(Theme.secondary))
                    .help("删除批注").accessibilityLabel("删除批注")
                }
            }
            QuoteText(quote: store.draft?.quote ?? "")
            TextEditor(text: $store.draftBody)
                .font(.system(size: 14))
                .lineSpacing(3)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.never)
                .padding(.horizontal, 6).padding(.vertical, 8)
                .frame(height: 96)
                .overlay(alignment: .topLeading) {
                    if store.draftBody.isEmpty {
                        Text("写下你的意见…").font(.system(size: 14)).foregroundStyle(Color(Theme.secondary))
                            .padding(.leading, 11).padding(.top, 8).allowsHitTesting(false)
                    }
                }
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(Theme.field)))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color(Theme.vermilion).opacity(focused ? 0.45 : 0.15)))
                .focused($focused)
                .accessibilityLabel("批注意见")
                .onExitCommand(perform: store.cancelDraft)
            HStack(spacing: 6) {
                Spacer()
                Button("取消", action: store.cancelDraft).buttonStyle(PlainToolButtonStyle())
                Button { store.saveDraft() } label: {
                    HStack(spacing: 6) { Text("保存"); Text("⌘↩").font(.system(size: 11.5)).opacity(0.65) }
                }
                .buttonStyle(InkButtonStyle())
                .disabled(empty)
                .help("保存（⌘↩）")
            }
        }
        .card(width: 340)
        .tint(Color(Theme.vermilion))
        .onAppear { DispatchQueue.main.async { focused = true } }
    }
}
