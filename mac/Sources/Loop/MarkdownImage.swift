import AppKit

/// A markdown image, `![alt](target)` or `![alt](<target with spaces> "title")`.
///
/// The text view's copy of the plan swaps the `!` for U+FFFC, the attachment character, and hides the rest,
/// so indexes still match the markdown.
struct MarkdownImage {
    let range: NSRange
    let alt: String
    let target: String

    private static let pattern = try! NSRegularExpression(
        pattern: "!\\[([^\\]\\n]*)\\]\\((?:<([^>\\n]+)>|([^)\\s]+))(?:[ \\t]+\"[^\"\\n]*\")?\\)")

    static func all(in text: String) -> [MarkdownImage] {
        let source = text as NSString
        return pattern.matches(in: text, range: NSRange(location: 0, length: source.length)).map { image($0, in: source) }
    }

    /// The image whose `!` is at `index`.
    static func at(_ index: Int, in source: NSString) -> MarkdownImage? {
        pattern.firstMatch(in: source as String, options: .anchored,
                           range: NSRange(location: index, length: source.length - index)).map { image($0, in: source) }
    }

    private static func image(_ match: NSTextCheckingResult, in source: NSString) -> MarkdownImage {
        let target = match.range(at: 2).location != NSNotFound ? match.range(at: 2) : match.range(at: 3)
        return MarkdownImage(range: match.range, alt: source.substring(with: match.range(at: 1)),
                             target: source.substring(with: target))
    }

    /// How a quote shows the image.
    var label: String {
        let name = alt.trimmingCharacters(in: .whitespaces)
        return "[图片：\(name.isEmpty ? target : name)]"
    }
}

extension Notification.Name {
    /// A remote image finished loading; the object is its URL.
    static let loopImageLoaded = Notification.Name("LoopImageLoaded")
}

/// Images in the plan, loaded once each. Local files load on first use; web images load in the background
/// and post `loopImageLoaded` when they arrive. Main thread only.
enum PlanImages {
    private static var images: [URL: NSImage] = [:]
    private static var failed: Set<URL> = []
    private static var loading: Set<URL> = []

    /// Relative paths are relative to the plan's folder; `%20`-style escapes are undone when the path as written doesn't exist.
    static func resolve(_ target: String, base: URL?) -> URL? {
        if let url = URL(string: target), let scheme = url.scheme?.lowercased(),
           ["http", "https", "file", "data"].contains(scheme) { return url }
        func file(_ path: String) -> URL {
            let path = (path as NSString).expandingTildeInPath
            if path.hasPrefix("/") { return URL(fileURLWithPath: path).standardizedFileURL }
            return (base ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
                .appendingPathComponent(path).standardizedFileURL
        }
        let written = file(target)
        if !FileManager.default.fileExists(atPath: written.path), let decoded = target.removingPercentEncoding, decoded != target {
            return file(decoded)
        }
        return written
    }

    enum State { case loaded(NSImage), loading, missing }

    static func state(of url: URL?) -> State {
        guard let url else { return .missing }
        if let image = images[url] { return .loaded(image) }
        if failed.contains(url) { return .missing }
        if url.scheme == "http" || url.scheme == "https" {
            if !loading.contains(url) { fetch(url) }
            return .loading
        }
        guard let data = try? Data(contentsOf: url), let image = NSImage(data: data), image.size.width > 0 else {
            failed.insert(url)
            return .missing
        }
        images[url] = image
        return .loaded(image)
    }

    private static func fetch(_ url: URL) {
        loading.insert(url)
        URLSession.shared.dataTask(with: url) { data, response, _ in
            let ok = (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
            let image = ok ? data.flatMap(NSImage.init(data:)) : nil
            DispatchQueue.main.async {
                loading.remove(url)
                if let image, image.size.width > 0 { images[url] = image } else { failed.insert(url) }
                NotificationCenter.default.post(name: .loopImageLoaded, object: url)
            }
        }.resume()
    }
}

/// Draws a plan image as wide as it is, up to the text column, on rounded corners with a hairline edge.
/// An image that is still loading or can't be found is a quiet box with its name.
final class PlanImageCell: NSTextAttachmentCell {
    let url: URL?
    let name: String
    static let maxHeight: CGFloat = 560
    private static let placeholderHeight: CGFloat = 64
    private static let radius: CGFloat = 5

    init(url: URL?, name: String) {
        self.url = url
        self.name = name
        super.init(textCell: "")
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Selecting and commenting work on an image the way they do on text.
    override func wantsToTrackMouse() -> Bool { false }

    private func size(within width: CGFloat) -> NSSize {
        guard case .loaded(let image) = PlanImages.state(of: url) else {
            return NSSize(width: min(width, 420), height: Self.placeholderHeight)
        }
        let scale = min(1, width / image.size.width, Self.maxHeight / image.size.height)
        return NSSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
    }

    override func cellSize() -> NSSize { size(within: MarkdownStyler.textWidth) }

    override func cellFrame(for textContainer: NSTextContainer, proposedLineFragment lineFrag: NSRect,
                            glyphPosition position: NSPoint, characterIndex charIndex: Int) -> NSRect {
        let width = max(40, lineFrag.width - textContainer.lineFragmentPadding * 2)
        return NSRect(origin: .zero, size: size(within: width))
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        let frame = cellFrame.integral
        let path = NSBezierPath(roundedRect: frame.insetBy(dx: 0.5, dy: 0.5), xRadius: Self.radius, yRadius: Self.radius)
        let state = PlanImages.state(of: url)
        guard case .loaded(let image) = state else {
            Theme.codeBackground.setFill()
            path.fill()
            drawName(in: frame, missing: { if case .missing = state { return true }; return false }())
            return
        }
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        image.draw(in: frame, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true,
                   hints: [.interpolation: NSImageInterpolation.high])
        NSGraphicsContext.restoreGraphicsState()
        Theme.rule.withAlphaComponent(0.12).setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    private func drawName(in frame: NSRect, missing: Bool) {
        let font = NSFont.systemFont(ofSize: 12.5)
        let symbol = NSImage(systemSymbolName: missing ? "photo.badge.exclamationmark" : "photo", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .regular))
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingMiddle
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: Theme.secondary, .paragraphStyle: style]
        let label = name as NSString
        let iconWidth: CGFloat = symbol.map { $0.size.width + 7 } ?? 0
        let textWidth = min(label.size(withAttributes: attributes).width, frame.width - 32 - iconWidth)
        var x = frame.midX - (iconWidth + textWidth) / 2
        if let symbol {
            let tinted = NSImage(size: symbol.size, flipped: false) { rect in
                symbol.draw(in: rect)
                Theme.secondary.set()
                rect.fill(using: .sourceAtop)
                return true
            }
            tinted.draw(in: NSRect(x: x, y: frame.midY - symbol.size.height / 2, width: symbol.size.width, height: symbol.size.height),
                        from: .zero, operation: .sourceOver, fraction: 0.8, respectFlipped: true, hints: nil)
            x += iconWidth
        }
        let height = font.ascender - font.descender + 2
        label.draw(with: NSRect(x: x, y: frame.midY - height / 2, width: textWidth, height: height),
                   options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attributes)
    }
}
