import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// Images attached to comments and 总评 notes. Each is copied into the review's own folder, so the agent can still
/// open it from the path in the feedback after the window is gone.
enum Attachments {
    /// Where ⌘V reads from; the self-test swaps in a private pasteboard.
    static var pasteboard = NSPasteboard.general
    /// Formats the agent reads as they are; other images are converted to PNG.
    private static let readable: [UTType] = [.png, .jpeg, .gif, .webP]

    /// The pasteboard's image files, or else its image data. Text wins over a picture of it, so copied rich text
    /// still pastes as text. Empty when there is nothing to attach, and the paste goes on as usual.
    static func save(from pasteboard: NSPasteboard, into folder: URL) -> [String] {
        let files = pasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true, .urlReadingContentsConformToTypes: [UTType.image.identifier]
        ]) as? [URL] ?? []
        if !files.isEmpty { return save(files: files, into: folder) }
        guard pasteboard.string(forType: .string) == nil else { return [] }
        if let png = pasteboard.data(forType: .png) { return save(data: png, type: .png, into: folder).map { [$0] } ?? [] }
        guard let image = NSImage(pasteboard: pasteboard), let png = png(image) else { return [] }
        return save(data: png, type: .png, into: folder).map { [$0] } ?? []
    }

    static func save(files: [URL], into folder: URL) -> [String] {
        files.compactMap { file in
            guard let type = UTType(filenameExtension: file.pathExtension), type.conforms(to: .image),
                  let data = try? Data(contentsOf: file) else { return nil }
            return save(data: data, type: type, into: folder)
        }
    }

    /// Writes one image into `folder` under a fresh name and returns its path.
    static func save(data: Data, type: UTType?, into folder: URL) -> String? {
        var data = data
        var type = type ?? .png
        if !readable.contains(where: type.conforms(to:)) {
            guard let image = NSImage(data: data), let png = png(image) else { return nil }
            data = png
            type = .png
        }
        let name = UUID().uuidString.prefix(8).lowercased() + "." + (type.preferredFilenameExtension ?? "png")
        let url = folder.appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch { return nil }
        return url.path
    }

    /// Images dragged in from Finder, a screenshot thumbnail or a browser, saved as they arrive.
    static func save(_ providers: [NSItemProvider], into folder: URL, added: @escaping ([String]) -> Void) {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    let paths = save(files: [url], into: folder)
                    DispatchQueue.main.async { if !paths.isEmpty { added(paths) } }
                }
            } else if let identifier = provider.registeredTypeIdentifiers.first(where: { UTType($0)?.conforms(to: .image) == true }) {
                provider.loadDataRepresentation(forTypeIdentifier: identifier) { data, _ in
                    guard let data, let path = save(data: data, type: UTType(identifier), into: folder) else { return }
                    DispatchQueue.main.async { added([path]) }
                }
            }
        }
    }

    /// Drops the images of reviews that are long over: their draft is gone and nothing changed for 30 days.
    static func prune(_ root: URL = ReviewRequest.support, now: Date = Date()) {
        let manager = FileManager.default
        let folders = (try? manager.contentsOfDirectory(at: root.appendingPathComponent("attachments"),
                                                       includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for folder in folders {
            let draft = root.appendingPathComponent("reviews/\(folder.lastPathComponent).json")
            guard !manager.fileExists(atPath: draft.path),
                  let modified = try? folder.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                  now.timeIntervalSince(modified) > 30 * 24 * 3600 else { continue }
            try? manager.removeItem(at: folder)
        }
    }

    private static func png(_ image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    private static let thumbnails = NSCache<NSString, NSImage>()

    /// A downsampled copy sharp enough to fill a `side`-point square, cached.
    static func thumbnail(_ path: String, side: CGFloat) -> NSImage? {
        let key = "\(side)|\(path)" as NSString
        if let cached = thumbnails.object(forKey: key) { return cached }
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
              let height = properties[kCGImagePropertyPixelHeight] as? CGFloat, width > 0, height > 0 else { return nil }
        // The square crops the long side, so the short side sets the size; 2x for Retina.
        let longest = min(max(width, height), side * 2 * max(width, height) / min(width, height))
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: longest
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        thumbnails.setObject(image, forKey: key)
        return image
    }
}

/// Square thumbnails that wrap onto new rows. Clicking one opens it in Preview; with `remove`, hovering one
/// shows a button that takes it off.
struct ImageStrip: View {
    let paths: [String]
    var side: CGFloat = 52
    var remove: ((String) -> Void)?

    var body: some View {
        WrappingRow(spacing: 8) {
            ForEach(paths, id: \.self) { Thumbnail(path: $0, side: side, remove: remove) }
        }
    }
}

private struct Thumbnail: View {
    let path: String
    let side: CGFloat
    let remove: ((String) -> Void)?
    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: side > 40 ? 7 : 5, style: .continuous)
        Group {
            if let image = Attachments.thumbnail(path, side: side) {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "photo").font(.system(size: side * 0.32)).foregroundStyle(Color(Theme.secondary))
            }
        }
        .frame(width: side, height: side)
        .background(Color(Theme.field))
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color(Theme.rule)))
        .overlay(alignment: .topTrailing) {
            if let remove, hovering {
                Button { remove(path) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 7.5, weight: .bold))
                        .foregroundStyle(Color(Theme.onPrimary))
                        .frame(width: 17, height: 17)
                        .background(Circle().fill(Color(Theme.primary)))
                        .overlay(Circle().strokeBorder(Color(Theme.sheet), lineWidth: 1.5))
                }
                .buttonStyle(.plain)
                .offset(x: 6, y: -6)
                .help("移除这张图片")
                .accessibilityLabel("移除图片")
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
        .onHover { hovering = $0 }
        .help("点击查看大图")
        .accessibilityElement(children: .contain)
        .accessibilityLabel("附图")
    }
}

/// Lays children out left to right, starting a new row when one would overflow.
private struct WrappingRow: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        return CGSize(width: rows.map(\.width).max() ?? 0, height: rows.last.map { $0.y + $0.height } ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.items {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [(items: [Int], y: CGFloat, width: CGFloat, height: CGFloat)] {
        var rows: [(items: [Int], y: CGFloat, width: CGFloat, height: CGFloat)] = []
        var current: (items: [Int], y: CGFloat, width: CGFloat, height: CGFloat) = ([], 0, 0, 0)
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            if !current.items.isEmpty, current.width + spacing + size.width > width {
                rows.append(current)
                current = ([], current.y + current.height + spacing, 0, 0)
            }
            current.width += (current.items.isEmpty ? 0 : spacing) + size.width
            current.height = max(current.height, size.height)
            current.items.append(index)
        }
        if !current.items.isEmpty { rows.append(current) }
        return rows
    }
}

/// Picks images from disk in a sheet on the window.
struct AddImageButton: View {
    let add: ([URL]) -> Void

    var body: some View {
        Button(action: pick) {
            Image(systemName: "photo").font(.system(size: 13))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color(Theme.secondary))
        .help("添加图片（也可以直接粘贴截图，或把图片拖进来）")
        .accessibilityLabel("添加图片")
    }

    private func pick() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = "选择要附上的图片"
        panel.prompt = "附上"
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window) { if $0 == .OK { add(panel.urls) } }
        } else if panel.runModal() == .OK {
            add(panel.urls)
        }
    }
}

extension View {
    /// ⌘V with an image on the pasteboard attaches it through `paste` (which returns whether it took anything)
    /// instead of pasting nothing into this TextEditor. Image files dropped on the editor reach the `onDrop`
    /// around it rather than going in as their paths.
    func pastesImages(_ paste: @escaping (NSPasteboard) -> Bool) -> some View {
        background(ImagePasteProbe(paste: paste))
    }
}

/// Sits behind a TextEditor to reach the NSTextView SwiftUI builds for it, which SwiftUI keeps private.
private struct ImagePasteProbe: NSViewRepresentable {
    let paste: (NSPasteboard) -> Bool

    func makeNSView(context: Context) -> Probe { Probe() }
    func updateNSView(_ view: Probe, context: Context) { view.paste = paste }

    final class Probe: NSView {
        var paste: (NSPasteboard) -> Bool = { _ in false }
        private(set) weak var textView: NSTextView?
        private var monitor: Any?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            guard window != nil else { return }
            // SwiftUI lays the editor out a beat after the probe.
            DispatchQueue.main.async { [weak self] in self?.attach() }
        }

        private func attach() {
            guard window != nil, monitor == nil, let editor = editor() else { return }
            textView = editor
            editor.unregisterDraggedTypes()
            editor.registerForDraggedTypes([.string])
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, let textView = self.textView, event.window?.firstResponder === textView,
                      event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                      event.charactersIgnoringModifiers == "v", !textView.hasMarkedText(),
                      self.paste(Attachments.pasteboard) else { return event }
                return nil
            }
        }

        /// The editable text view overlapping this probe the most, in the nearest ancestor that has one.
        private func editor() -> NSTextView? {
            let frame = convert(bounds, to: nil)
            var ancestor = superview
            while let view = ancestor {
                let best = Self.textViews(in: view).map { text -> (NSTextView, CGFloat) in
                    let box = text.enclosingScrollView ?? text
                    let overlap = box.convert(box.bounds, to: nil).intersection(frame)
                    return (text, overlap.isNull ? 0 : overlap.width * overlap.height)
                }.max { $0.1 < $1.1 }
                if let best, best.1 > 0 { return best.0 }
                ancestor = view.superview
            }
            return nil
        }

        private static func textViews(in view: NSView) -> [NSTextView] {
            if let text = view as? NSTextView { return text.isEditable ? [text] : [] }
            return view.subviews.flatMap(textViews)
        }

        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    }
}
