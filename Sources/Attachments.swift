import AppKit
import AVFoundation
import UniformTypeIdentifiers

enum ChipKind { case audio, file }

// MARK: - Image cell (draws the picture at its display size with soft corners)

final class ImageCell: NSTextAttachmentCell {
    var displaySize: NSSize

    init(image: NSImage, displaySize: NSSize) {
        self.displaySize = displaySize
        super.init(imageCell: image)
    }
    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func cellSize() -> NSSize { displaySize }
    override func cellBaselineOffset() -> NSPoint { .zero }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        guard let image else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.imageInterpolation = .high
        NSBezierPath(roundedRect: cellFrame, xRadius: 6, yRadius: 6).addClip()
        image.draw(in: cellFrame, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        NSGraphicsContext.restoreGraphicsState()
    }
    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?, characterIndex: Int) {
        draw(withFrame: cellFrame, in: controlView)
    }
    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?, characterIndex: Int, layoutManager: NSLayoutManager) {
        draw(withFrame: cellFrame, in: controlView)
    }
}

// MARK: - Equation cell (tinted with the text colour so it works on dark paper)

final class EquationCell: NSTextAttachmentCell {
    var source: String
    var display: Bool
    var displaySize: NSSize
    var baselineDrop: CGFloat
    var pngData: Data?
    var needsRender: Bool { pngData == nil }

    private var mask: CGImage?

    init(source: String, display: Bool, image: NSImage?, pngData: Data?, displaySize: NSSize, baselineDrop: CGFloat) {
        self.source = source
        self.display = display
        self.displaySize = displaySize
        self.baselineDrop = baselineDrop
        self.pngData = pngData
        super.init(imageCell: image)
    }
    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func cellSize() -> NSSize { displaySize }
    override func cellBaselineOffset() -> NSPoint { NSPoint(x: 0, y: -baselineDrop) }

    /// Replaces the rendered picture (e.g. after a re-render) and drops the cached mask.
    func setRendered(png: Data, image: NSImage, size: NSSize, baselineDrop: CGFloat) {
        pngData = png
        self.image = image
        displaySize = size
        self.baselineDrop = baselineDrop
        mask = nil
    }

    /// A CoreGraphics image mask built from the PNG's alpha channel; painted with the text colour.
    private func currentMask() -> CGImage? {
        if let mask { return mask }
        guard let png = pngData, let src = NSBitmapImageRep(data: png)?.cgImage else { return nil }
        let w = src.width, h = src.height
        guard w > 0, h > 0, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var rgba = [UInt8](repeating: 0, count: w * h * 4)
        let ok: Bool = rgba.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(src, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { return nil }
        var gray = [UInt8](repeating: 255, count: w * h)
        for i in 0..<(w * h) { gray[i] = 255 &- rgba[i * 4 + 3] }   // image masks: 0 = paint
        guard let provider = CGDataProvider(data: Data(gray) as CFData),
              let m = CGImage(maskWidth: w, height: h, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: w, provider: provider, decode: nil, shouldInterpolate: true) else { return nil }
        mask = m
        return m
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        guard let cg = NSGraphicsContext.current?.cgContext else { return }
        guard let m = currentMask() else {
            // Not rendered yet: show the source in a soft box.
            let path = NSBezierPath(roundedRect: cellFrame.insetBy(dx: 0.5, dy: 0.5), xRadius: 5, yRadius: 5)
            Theme.tideBlue.withAlphaComponent(0.08).setFill(); path.fill()
            Theme.tideBlue.withAlphaComponent(0.3).setStroke(); path.stroke()
            let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            (source as NSString).draw(in: cellFrame.insetBy(dx: 6, dy: 4), withAttributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor])
            return
        }
        let flipped = controlView?.isFlipped ?? (NSGraphicsContext.current?.isFlipped ?? true)
        cg.saveGState()
        cg.interpolationQuality = .high
        let local = CGRect(x: 0, y: 0, width: cellFrame.width, height: cellFrame.height)
        if flipped {
            cg.translateBy(x: cellFrame.minX, y: cellFrame.maxY)
            cg.scaleBy(x: 1, y: -1)
        } else {
            cg.translateBy(x: cellFrame.minX, y: cellFrame.minY)
        }
        cg.clip(to: local, mask: m)
        cg.setFillColor(NSColor.textColor.cgColor)
        cg.fill(local)
        cg.restoreGState()
    }
    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?, characterIndex: Int) {
        draw(withFrame: cellFrame, in: controlView)
    }
    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?, characterIndex: Int, layoutManager: NSLayoutManager) {
        draw(withFrame: cellFrame, in: controlView)
    }

    override func wantsToTrackMouse() -> Bool { true }
    override func trackMouse(with theEvent: NSEvent, in cellFrame: NSRect, of controlView: NSView?, atCharacterIndex charIndex: Int, untilMouseUp flag: Bool) -> Bool {
        if theEvent.clickCount >= 2, let tv = controlView as? TideTextView {
            DispatchQueue.main.async { tv.editor?.editEquation(at: charIndex) }
            return true
        }
        return false
    }

    // Serialisation of the source into docx alt text / RTFD file names so it survives round trips.
    var docxDescription: String { "tide-equation:\(display ? 1 : 0):\(Int(baselineDrop.rounded())):\(Self.encode(source))" }
    static func parseDocxDescription(_ s: String) -> (source: String, display: Bool, baselineDrop: CGFloat)? {
        let parts = s.split(separator: ":", maxSplits: 3, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 4, parts[0] == "tide-equation", let src = decode(parts[3]) else { return nil }
        return (src, parts[1] == "1", CGFloat(Int(parts[2]) ?? 0))
    }
    static func fileName(source: String, display: Bool, baselineDrop: CGFloat) -> String {
        let enc = encode(source)
        if enc.count > 180 { return "equation.png" }
        return "eq_\(display ? 1 : 0)_\(Int(baselineDrop.rounded()))_\(enc).png"
    }
    static func parseFileName(_ name: String) -> (source: String, display: Bool, baselineDrop: CGFloat)? {
        guard name.hasPrefix("eq_"), name.hasSuffix(".png") else { return nil }
        let core = String(name.dropFirst(3).dropLast(4))
        let parts = core.split(separator: "_", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3, let src = decode(parts[2]) else { return nil }
        return (src, parts[0] == "1", CGFloat(Int(parts[1]) ?? 0))
    }
    static func encode(_ s: String) -> String {
        Data(s.utf8).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    static func decode(_ s: String) -> String? {
        var b = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b.count % 4 != 0 { b += "=" }
        guard let d = Data(base64Encoded: b) else { return nil }
        return String(data: d, encoding: .utf8)
    }
}

// MARK: - File / audio chip

final class FileChipCell: NSTextAttachmentCell {
    let kind: ChipKind
    let name: String
    var fileURL: URL?
    let data: Data?
    private let icon: NSImage
    static let height: CGFloat = 24
    static let font = NSFont.systemFont(ofSize: 12, weight: .medium)

    private static var player: AVAudioPlayer?
    private static weak var playingCell: FileChipCell?
    private static let playerDelegate = PlayerDelegate()

    final class PlayerDelegate: NSObject, AVAudioPlayerDelegate {
        var onFinish: (() -> Void)?
        func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) { onFinish?() }
    }

    init(kind: ChipKind, name: String, fileURL: URL?, data: Data?) {
        self.kind = kind
        self.name = name
        self.fileURL = fileURL
        self.data = data
        let type = UTType(filenameExtension: (name as NSString).pathExtension) ?? (kind == .audio ? .audio : .data)
        icon = NSWorkspace.shared.icon(for: type)
        super.init(textCell: "")
    }
    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    var isPlaying: Bool { FileChipCell.playingCell === self && (FileChipCell.player?.isPlaying ?? false) }

    private var textWidth: CGFloat { (name as NSString).size(withAttributes: [.font: Self.font]).width.rounded(.up) }

    override func cellSize() -> NSSize {
        NSSize(width: 10 + 16 + 6 + textWidth + (kind == .audio ? 8 + 12 : 0) + 10, height: Self.height)
    }
    override func cellBaselineOffset() -> NSPoint { NSPoint(x: 0, y: -7) }

    override func draw(withFrame f: NSRect, in controlView: NSView?) {
        let path = NSBezierPath(roundedRect: f.insetBy(dx: 0.5, dy: 0.5), xRadius: f.height / 2, yRadius: f.height / 2)
        Theme.tideBlue.withAlphaComponent(0.12).setFill()
        path.fill()
        Theme.tideBlue.withAlphaComponent(0.35).setStroke()
        path.lineWidth = 1
        path.stroke()
        var x = f.minX + 10
        icon.draw(in: NSRect(x: x, y: f.midY - 8, width: 16, height: 16), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        x += 22
        let attrs: [NSAttributedString.Key: Any] = [.font: Self.font, .foregroundColor: NSColor.textColor]
        let textHeight = Self.font.ascender - Self.font.descender
        (name as NSString).draw(at: NSPoint(x: x, y: f.midY - textHeight / 2), withAttributes: attrs)
        x += textWidth + 8
        if kind == .audio {
            Theme.tideBlue.setFill()
            if isPlaying {
                NSBezierPath(roundedRect: NSRect(x: x, y: f.midY - 5, width: 10, height: 10), xRadius: 2, yRadius: 2).fill()
            } else {
                let tri = NSBezierPath()
                tri.move(to: NSPoint(x: x, y: f.midY - 6))
                tri.line(to: NSPoint(x: x + 11, y: f.midY))
                tri.line(to: NSPoint(x: x, y: f.midY + 6))
                tri.close()
                tri.fill()
            }
        }
    }
    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?, characterIndex: Int) {
        draw(withFrame: cellFrame, in: controlView)
    }
    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?, characterIndex: Int, layoutManager: NSLayoutManager) {
        draw(withFrame: cellFrame, in: controlView)
    }

    override func wantsToTrackMouse() -> Bool { true }
    override func trackMouse(with theEvent: NSEvent, in cellFrame: NSRect, of controlView: NSView?, atCharacterIndex charIndex: Int, untilMouseUp flag: Bool) -> Bool {
        guard let view = controlView, let window = view.window else { return false }
        var inside = true
        while true {
            guard let e = window.nextEvent(matching: [.leftMouseUp, .leftMouseDragged]) else { break }
            inside = cellFrame.contains(view.convert(e.locationInWindow, from: nil))
            if e.type == .leftMouseUp { break }
        }
        if inside { activate(in: view) }
        return inside
    }

    func activate(in view: NSView) {
        switch kind {
        case .audio: togglePlayback(view)
        case .file: open()
        }
    }

    func open() {
        if let url = fileURL, FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.open(url)
        } else if let data {
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("TideAttachments", isDirectory: true)
            try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
            let url = tmp.appendingPathComponent(name)
            if (try? data.write(to: url)) != nil { NSWorkspace.shared.open(url) }
        }
    }

    func togglePlayback(_ view: NSView) {
        if FileChipCell.playingCell === self {
            FileChipCell.player?.stop()
            FileChipCell.playingCell = nil
            view.needsDisplay = true
            return
        }
        guard let data else { return }
        FileChipCell.player?.stop()
        guard let p = try? AVAudioPlayer(data: data) else { return }
        p.delegate = FileChipCell.playerDelegate
        FileChipCell.player = p
        FileChipCell.playingCell = self
        FileChipCell.playerDelegate.onFinish = { [weak view] in
            FileChipCell.playingCell = nil
            view?.needsDisplay = true
        }
        p.play()
        view.needsDisplay = true
    }

    static func stopAll() {
        player?.stop()
        playingCell = nil
    }
}

/// AppKit swaps audio/video attachments over to its own inline media view and quietly discards any
/// custom cell. This subclass owns its cell so chips render the way Tide draws them.
final class ChipAttachment: NSTextAttachment {
    private var chipCell: FileChipCell?
    override var attachmentCell: (any NSTextAttachmentCellProtocol)? {
        get { chipCell }
        set {
            chipCell = newValue as? FileChipCell
            chipCell?.attachment = self
        }
    }
}

// MARK: - Factory / fix-up

enum AttachmentFactory {
    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "tiff", "tif", "heic", "heif", "bmp", "webp"]

    static func naturalSize(pixels px: NSSize) -> NSSize {
        let scale: CGFloat = px.width > 700 ? 2 : 1
        return NSSize(width: px.width / scale, height: px.height / scale)
    }

    static func fit(_ size: NSSize, maxWidth: CGFloat) -> NSSize {
        guard size.width > maxWidth, size.width > 0 else { return size }
        return NSSize(width: maxWidth, height: (size.height * maxWidth / size.width).rounded())
    }

    static func imageAttachment(data: Data, filename: String, displaySize: NSSize?, maxWidth: CGFloat) -> NSTextAttachment? {
        guard let image = NSImage(data: data) else { return nil }
        let px = ImageUtil.pixelSize(data) ?? image.size
        let size = fit(displaySize ?? naturalSize(pixels: px), maxWidth: maxWidth)
        let fw = FileWrapper(regularFileWithContents: data)
        fw.preferredFilename = filename.isEmpty ? "image.png" : filename
        let att = NSTextAttachment(fileWrapper: fw)
        att.bounds = CGRect(origin: .zero, size: size)
        att.attachmentCell = ImageCell(image: image, displaySize: size)
        return att
    }

    static func chipAttachment(fileURL url: URL) -> NSTextAttachment? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return chipAttachment(name: url.lastPathComponent, data: data, fileURL: url)
    }

    /// An attachment made from a non-image file wrapper ignores custom cells, so build it empty,
    /// install the cell, and only then attach the wrapper.
    static func chipAttachment(name: String, data: Data?, fileURL: URL?) -> NSTextAttachment {
        let kind: ChipKind = (UTType(filenameExtension: (name as NSString).pathExtension)?.conforms(to: .audio) ?? false) ? .audio : .file
        let att = ChipAttachment(data: nil, ofType: nil)
        att.allowsTextAttachmentView = false
        att.attachmentCell = FileChipCell(kind: kind, name: name.isEmpty ? "File" : name, fileURL: fileURL, data: data)
        if let data {
            let fw = FileWrapper(regularFileWithContents: data)
            fw.preferredFilename = name.isEmpty ? "file" : name
            att.fileWrapper = fw
        }
        return att
    }

    static func equationAttachment(pngData: Data?, source: String, display: Bool, displaySize: NSSize, baselineDrop: CGFloat) -> NSTextAttachment {
        let att: NSTextAttachment
        if let png = pngData {
            let fw = FileWrapper(regularFileWithContents: png)
            fw.preferredFilename = EquationCell.fileName(source: source, display: display, baselineDrop: baselineDrop)
            att = NSTextAttachment(fileWrapper: fw)
        } else {
            att = NSTextAttachment(data: nil, ofType: nil)
        }
        att.bounds = CGRect(origin: .zero, size: displaySize)
        att.attachmentCell = EquationCell(source: source, display: display, image: pngData.flatMap { NSImage(data: $0) }, pngData: pngData, displaySize: displaySize, baselineDrop: baselineDrop)
        return att
    }

    static func isImage(name: String, data: Data?) -> Bool {
        if let data, ImageUtil.kind(of: data) != nil { return true }
        let ext = (name as NSString).pathExtension.lowercased()
        if imageExtensions.contains(ext) { return true }
        if let t = UTType(filenameExtension: ext), t.conforms(to: .image) { return true }
        return false
    }

    /// Gives an attachment that arrived by paste, drop or import the right cell. Returns the attachment
    /// to keep — a replacement when the original cannot carry a custom cell (non-image file wrappers).
    @discardableResult
    static func installCell(on att: NSTextAttachment, availableWidth: CGFloat) -> NSTextAttachment {
        if att.attachmentCell is ImageCell || att.attachmentCell is FileChipCell || att.attachmentCell is EquationCell { return att }
        let name = att.fileWrapper?.preferredFilename ?? att.fileWrapper?.filename ?? ""
        let data = att.fileWrapper?.regularFileContents
        if let data, let eq = EquationCell.parseFileName(name), let image = NSImage(data: data) {
            let px = ImageUtil.pixelSize(data) ?? image.size
            let size = NSSize(width: px.width / 2, height: px.height / 2)
            att.attachmentCell = EquationCell(source: eq.source, display: eq.display, image: image, pngData: data, displaySize: size, baselineDrop: eq.baselineDrop)
            att.bounds = CGRect(origin: .zero, size: size)
            return att
        }
        if let data, isImage(name: name, data: data), let image = NSImage(data: data) {
            let px = ImageUtil.pixelSize(data) ?? image.size
            var size = fit(naturalSize(pixels: px), maxWidth: availableWidth)
            if att.bounds.width > 0, att.bounds.width <= availableWidth { size = att.bounds.size }
            att.attachmentCell = ImageCell(image: image, displaySize: size)
            att.bounds = CGRect(origin: .zero, size: size)
            return att
        }
        if att.fileWrapper == nil, let image = att.image {
            let size = fit(naturalSize(pixels: image.size), maxWidth: availableWidth)
            att.attachmentCell = ImageCell(image: image, displaySize: size)
            att.bounds = CGRect(origin: .zero, size: size)
            return att
        }
        return chipAttachment(name: name, data: data, fileURL: nil)
    }

    static func installCells(in storage: NSMutableAttributedString, availableWidth: CGFloat) {
        guard storage.length > 0 else { return }
        var replacements: [(NSRange, NSTextAttachment)] = []
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length), options: []) { value, range, _ in
            guard let att = value as? NSTextAttachment else { return }
            let kept = installCell(on: att, availableWidth: availableWidth)
            if kept !== att { replacements.append((range, kept)) }
        }
        for (range, att) in replacements { storage.addAttribute(.attachment, value: att, range: range) }
    }
}
