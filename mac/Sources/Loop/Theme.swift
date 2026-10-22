import AppKit
import SwiftUI

/// 红笔批改: the plan is a white sheet on a cool grey desk, headings are set in serif,
/// and every comment is marked in vermilion, like a teacher's red pen.
enum Theme {
    static let ground = dynamic(light: 0xECEEF1, dark: 0x17181B)
    static let sheet = dynamic(light: 0xFFFFFF, dark: 0x222329)
    static let ink = dynamic(light: 0x23272E, dark: 0xD9DBE0)
    static let heading = dynamic(light: 0x141820, dark: 0xF2F3F5)
    static let secondary = dynamic(light: 0x5F6672, dark: 0x9BA1AB)
    static let vermilion = dynamic(light: 0xB4322A, dark: 0xE8695B)
    static let onVermilion = dynamic(light: 0xFFFFFF, dark: 0x1A1B1E)
    /// The 提交 and 保存 buttons.
    static let primary = dynamic(light: 0x1E2A3A, dark: 0xE9EBEF)
    static let onPrimary = dynamic(light: 0xFFFFFF, dark: 0x141820)
    static let selection = dynamic(light: 0xDCE6F5, dark: 0x2E4467)
    static let codeBackground = dynamic(light: 0xF3F4F6, dark: 0x2C2D33)
    static let codeText = dynamic(light: 0x1E2A3A, dark: 0xC9D3E6)
    static let field = dynamic(light: 0xF6F7F9, dark: 0x1C1D21)
    static let rule = NSColor(name: nil) { appearance in
        isDark(appearance) ? NSColor.white.withAlphaComponent(0.1) : NSColor(srgbRed: 20 / 255, green: 30 / 255, blue: 50 / 255, alpha: 0.1)
    }

    /// A table's rules: heavy above and below it, lighter under its header.
    static let tableRule = NSColor(name: nil) { appearance in
        isDark(appearance) ? NSColor.white.withAlphaComponent(0.45) : color(0x23272E).withAlphaComponent(0.8)
    }
    static let tableHeaderRule = NSColor(name: nil) { appearance in
        isDark(appearance) ? NSColor.white.withAlphaComponent(0.25) : color(0x23272E).withAlphaComponent(0.4)
    }

    static let sheetWidth: CGFloat = 760
    static let sheetPadding: CGFloat = 84
    /// Gap between the toolbar and the top of the sheet, and below the sheet's end.
    static let sheetTop: CGFloat = 6
    static let sheetBottom: CGFloat = 24

    /// New York for Latin text, Songti for Chinese.
    static func serif(_ size: CGFloat, weight: NSFont.Weight = .bold) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        let songti = weight == .regular ? "STSongti-SC-Regular" : "STSongti-SC-Bold"
        let descriptor = (base.fontDescriptor.withDesign(.serif) ?? base.fontDescriptor)
            .addingAttributes([.cascadeList: [NSFontDescriptor(name: songti, size: size)]])
        return NSFont(descriptor: descriptor, size: size) ?? base
    }

    private static func dynamic(light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in color(isDark(appearance) ? dark : light) }
    }

    private static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    private static func color(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

extension Color {
    init(_ color: NSColor) { self.init(nsColor: color) }
}

/// The dark ink button used for 提交 and 保存.
struct InkButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color(Theme.onPrimary))
            .padding(.horizontal, 14)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color(Theme.primary)))
            .opacity(enabled ? (configuration.isPressed ? 0.82 : 1) : 0.4)
            .contentShape(Rectangle())
    }
}

/// Quiet text buttons that only show a background under the pointer.
struct PlainToolButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { HoverLabel(configuration: configuration) }

    private struct HoverLabel: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var enabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.system(size: 12.5))
                .foregroundStyle(Color(enabled ? Theme.ink : Theme.secondary).opacity(enabled ? 1 : 0.6))
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color(Theme.rule).opacity(hovering && enabled ? (configuration.isPressed ? 1.4 : 0.8) : 0)))
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
        }
    }
}

extension View {
    /// SwiftUI's TextEditor holds its binding back while an input method is composing (pinyin before a candidate is
    /// picked), so a placeholder keyed on the binding shows through the composition. This hands `text` the editor's
    /// own text, composing part included, while something is being composed, and nil otherwise. Only the focused
    /// editor's typing counts.
    func composition(_ text: Binding<String?>, focused: Bool) -> some View {
        // Composing posts no text-change notification, but every keystroke of it moves the selection.
        let center = NotificationCenter.default
        let edits = center.publisher(for: NSTextView.didChangeSelectionNotification)
            .merge(with: center.publisher(for: NSText.didChangeNotification))
        return onReceive(edits) { note in
            guard focused, let view = note.object as? NSTextView, view.window?.firstResponder === view else { return }
            text.wrappedValue = view.hasMarkedText() ? view.string : nil
        }
        .onChange(of: focused) { _, isFocused in if !isFocused { text.wrappedValue = nil } }
    }
}
