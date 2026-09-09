import AppKit

/// Scroll-view document view: centres the "page" (the text view) and draws the paper behind it.
final class PageHostView: NSView {
    let textView: NSTextView
    var pageWidth: CGFloat = 680 { didSet { needsLayout = true } }
    var paperColor: NSColor = Theme.paperLight { didSet { needsDisplay = true } }
    let topMargin: CGFloat = 32
    let bottomMargin: CGFloat = 96
    let sideMargin: CGFloat = 40
    /// Extra room on the side where the floating panel lives, so the collapsed pill never covers text.
    var panelSide: PanelSide = .right { didSet { needsLayout = true } }
    var panelInset: CGFloat = 84 { didSet { needsLayout = true } }
    let minPageHeight: CGFloat = 760
    private(set) var pageRect = NSRect.zero
    private var observers: [Any] = []

    init(textView: NSTextView) {
        self.textView = textView
        super.init(frame: NSRect(x: 0, y: 0, width: 900, height: 800))
        addSubview(textView)
        textView.postsFrameChangedNotifications = true
        observers.append(NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: textView, queue: .main) { [weak self] _ in
            self?.needsLayout = true
        })
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    deinit { observers.forEach { NotificationCenter.default.removeObserver($0) } }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    override func layout() {
        super.layout()
        let clip = enclosingScrollView?.contentView.bounds.size ?? bounds.size
        let leftInset = panelSide == .left ? panelInset : sideMargin
        let rightInset = panelSide == .right ? panelInset : sideMargin
        let pw = min(pageWidth, max(320, clip.width - leftInset - rightInset)).rounded()
        if abs(textView.frame.width - pw) > 0.5 {
            textView.setFrameSize(NSSize(width: pw, height: textView.frame.height))
            if let lm = textView.layoutManager, let tc = textView.textContainer { lm.ensureLayout(for: tc) }
            textView.sizeToFit()
        }
        let totalWidth = max(clip.width, pw + leftInset + rightInset)
        let x = (leftInset + (totalWidth - leftInset - rightInset - pw) / 2).rounded()
        let pageHeight = max(textView.frame.height, minPageHeight)
        let totalHeight = max(clip.height, topMargin + pageHeight + bottomMargin)
        let origin = NSPoint(x: x, y: topMargin)
        if textView.frame.origin != origin { textView.setFrameOrigin(origin) }
        let newSize = NSSize(width: totalWidth, height: totalHeight)
        if frame.size != newSize { setFrameSize(newSize) }
        let newPage = NSRect(x: x, y: topMargin, width: pw, height: pageHeight)
        if newPage != pageRect { pageRect = newPage; needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard pageRect.width > 0 else { return }
        let path = NSBezierPath(roundedRect: pageRect, xRadius: 10, yRadius: 10)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowBlurRadius = 24
        shadow.shadowOffset = NSSize(width: 0, height: -8)
        shadow.shadowColor = NSColor(srgbRed: 0.10, green: 0.25, blue: 0.60, alpha: 0.18)
        shadow.set()
        paperColor.setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()
        Theme.tideBlue.withAlphaComponent(0.14).setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard !textView.frame.contains(p) else { super.mouseDown(with: event); return }
        window?.makeFirstResponder(textView)
        if p.y > textView.frame.maxY {
            textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
        }
    }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .arrow) }
}
