import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SelectionState: Equatable {
    var bold = false, italic = false, underline = false, strike = false
    var highlight: Highlight? = nil
    var style: TextStyle = .body
    var list: ListKind? = nil
    var alignment: NSTextAlignment = .natural
}

struct EquationRequest: Identifiable {
    let id = UUID()
    var source: String
    var display: Bool
    var replaceRange: NSRange?
}

struct LinkRequest: Identifiable {
    let id = UUID()
    var url: String
    var text: String
    var range: NSRange
}

/// Owns the TextKit 1 stack and every formatting operation. The SwiftUI panel and the menus both talk to this.
final class EditorController: NSObject, ObservableObject {
    weak var document: TideDocument?
    let textView: TideTextView
    let scrollView: NSScrollView
    let pageHost: PageHostView
    private(set) var typography = Typography.current

    @Published var state = SelectionState()
    @Published var wordCount = 0
    @Published var characterCount = 0
    @Published var equationRequest: EquationRequest? = nil
    @Published var linkRequest: LinkRequest? = nil
    @Published var forceExpanded = false
    @Published var titlebarInset: CGFloat = 28

    private var storage: NSTextStorage { textView.textStorage! }
    private var countTimer: Timer?
    private var renumberScheduled = false
    private var isRenumbering = false
    private var adjustingSelection = false
    private var observers: [Any] = []
    private var appliedFamily = Settings.fontFamily

    override init() {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: 680, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layout.addTextContainer(container)
        textView = TideTextView(frame: NSRect(x: 0, y: 0, width: 680, height: 600), textContainer: container)
        pageHost = PageHostView(textView: textView)
        scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 960, height: 700))
        super.init()
        configureTextView()
        configureScrollView()
        textView.editor = self
        textView.delegate = self
        storage.delegate = self
        applySettings(initial: true)
        observers.append(NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.applySettings(initial: false)
        })
    }
    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        countTimer?.invalidate()
    }

    private func configureTextView() {
        textView.isRichText = true
        textView.importsGraphics = true
        textView.allowsUndo = true
        textView.allowsImageEditing = false
        textView.usesFontPanel = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticLinkDetectionEnabled = true
        textView.isAutomaticTextReplacementEnabled = true
        textView.isGrammarCheckingEnabled = false
        textView.smartInsertDeleteEnabled = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 52, height: 48)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = []
        textView.insertionPointColor = Theme.tideBlue
        textView.linkTextAttributes = [.foregroundColor: Theme.tideBlue, .underlineStyle: NSUnderlineStyle.single.rawValue, .cursor: NSCursor.pointingHand]
        textView.displaysLinkToolTips = true
        textView.layoutManager?.allowsNonContiguousLayout = false
        textView.typingAttributes = typography.bodyAttributes()
        textView.defaultParagraphStyle = typography.paragraphStyle(for: .body)
        textView.textColor = NSColor.textColor
    }

    private func configureScrollView() {
        scrollView.documentView = pageHost
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.allowsMagnification = true
        scrollView.minMagnification = 0.5
        scrollView.maxMagnification = 3
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(top: 8, left: 0, bottom: 0, right: 0)
        scrollView.findBarPosition = .aboveContent
        let clip = scrollView.contentView
        clip.postsBoundsChangedNotifications = true
        clip.postsFrameChangedNotifications = true
        observers.append(NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: clip, queue: .main) { [weak self] _ in
            self?.pageHost.needsLayout = true
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: clip, queue: .main) { [weak self] _ in
            self?.pageHost.needsLayout = true
        })
    }

    // MARK: - Content

    var currentText: NSAttributedString { NSAttributedString(attributedString: storage) }
    var textWidth: CGFloat { max(200, textView.frame.width - 2 * textView.textContainerInset.width) }

    func load(_ text: NSAttributedString) {
        storage.setAttributedString(text)
        AttachmentFactory.installCells(in: storage, availableWidth: textWidth)
        if storage.length == 0 { textView.typingAttributes = typography.bodyAttributes() }
        renumberLists(register: false)
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.undoManager?.removeAllActions()
        renderPendingEquations()
        refreshState()
        updateCounts()
        pageHost.needsLayout = true
    }

    func focus() {
        textView.window?.makeFirstResponder(textView)
    }

    // MARK: - Low-level edits (all registered with undo)

    @discardableResult
    func replaceText(in range: NSRange, with attributed: NSAttributedString) -> Bool {
        guard textView.shouldChangeText(in: range, replacementString: attributed.string) else { return false }
        storage.beginEditing()
        storage.replaceCharacters(in: range, with: attributed)
        storage.endEditing()
        textView.didChangeText()
        return true
    }

    @discardableResult
    func addAttributes(_ attrs: [NSAttributedString.Key: Any], in range: NSRange) -> Bool {
        guard range.length > 0, textView.shouldChangeText(in: range, replacementString: nil) else { return false }
        storage.beginEditing()
        storage.addAttributes(attrs, range: range)
        storage.endEditing()
        textView.didChangeText()
        return true
    }

    func setAttributes(in range: NSRange, actionName: String, _ transform: (inout [NSAttributedString.Key: Any]) -> Void) {
        guard range.length > 0, textView.shouldChangeText(in: range, replacementString: nil) else { return }
        var runs: [(NSRange, [NSAttributedString.Key: Any])] = []
        storage.enumerateAttributes(in: range, options: []) { attrs, r, _ in runs.append((r, attrs)) }
        storage.beginEditing()
        for (r, attrs) in runs {
            var m = attrs
            transform(&m)
            storage.setAttributes(m, range: r)
        }
        storage.endEditing()
        textView.didChangeText()
        textView.undoManager?.setActionName(actionName)
        syncTypingAttributes()
        refreshState()
    }

    /// Attributes safe to reuse for freshly inserted text (no link, attachment, highlight…).
    func cleanAttributes(_ attrs: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
        var a = attrs
        for k in [NSAttributedString.Key.attachment, .link, .tideEquation, .underlineStyle, .strikethroughStyle, .backgroundColor, .tideHighlight, .superscript] { a[k] = nil }
        if a[.font] == nil { a[.font] = typography.font(for: .body) }
        if a[.foregroundColor] == nil { a[.foregroundColor] = NSColor.textColor }
        if a[.paragraphStyle] == nil { a[.paragraphStyle] = typography.paragraphStyle(for: .body) }
        return a
    }

    private func syncTypingAttributes() {
        let sel = textView.selectedRange()
        guard storage.length > 0 else { textView.typingAttributes = typography.bodyAttributes(); return }
        let loc = sel.length > 0 ? sel.location : max(0, sel.location - 1)
        if loc < storage.length {
            var a = storage.attributes(at: loc, effectiveRange: nil)
            a[.attachment] = nil
            a[.tideEquation] = nil
            textView.typingAttributes = a
        }
    }

    // MARK: - Paragraph helpers

    func paragraphRanges(in range: NSRange) -> [NSRange] {
        let str = storage.string as NSString
        var out: [NSRange] = []
        var loc = min(range.location, str.length)
        let end = NSMaxRange(range)
        repeat {
            let pr = str.paragraphRange(for: NSRange(location: loc, length: 0))
            out.append(pr)
            loc = NSMaxRange(pr)
            if pr.length == 0 { break }
        } while loc < end
        return out
    }

    func paragraphStyle(at pr: NSRange) -> NSParagraphStyle? {
        if pr.length > 0, pr.location < storage.length {
            return storage.attribute(.paragraphStyle, at: pr.location, effectiveRange: nil) as? NSParagraphStyle
        }
        return textView.typingAttributes[.paragraphStyle] as? NSParagraphStyle
    }

    // MARK: - Character formatting

    func toggleBold() { toggleTrait(.boldFontMask, name: "Bold") }
    func toggleItalic() { toggleTrait(.italicFontMask, name: "Italic") }

    private func toggleTrait(_ trait: NSFontTraitMask, name: String) {
        let sel = textView.selectedRange()
        let fm = NSFontManager.shared
        let isBold = trait == .boldFontMask
        func has(_ f: NSFont) -> Bool { isBold ? f.isBold : f.isItalic }
        if sel.length == 0 {
            var ta = textView.typingAttributes
            let f = ta[.font] as? NSFont ?? typography.font(for: .body)
            ta[.font] = has(f) ? fm.convert(f, toNotHaveTrait: trait) : fm.convert(f, toHaveTrait: trait)
            textView.typingAttributes = ta
            refreshState()
            return
        }
        var all = true
        storage.enumerateAttribute(.font, in: sel, options: []) { v, _, _ in
            if let f = v as? NSFont, !has(f) { all = false }
        }
        setAttributes(in: sel, actionName: name) { attrs in
            guard attrs[.attachment] == nil, let f = attrs[.font] as? NSFont else { return }
            attrs[.font] = all ? fm.convert(f, toNotHaveTrait: trait) : fm.convert(f, toHaveTrait: trait)
        }
    }

    func toggleUnderline() { toggleFlag(.underlineStyle, name: "Underline") }
    func toggleStrikethrough() { toggleFlag(.strikethroughStyle, name: "Strikethrough") }

    private func toggleFlag(_ key: NSAttributedString.Key, name: String) {
        let sel = textView.selectedRange()
        if sel.length == 0 {
            var ta = textView.typingAttributes
            let on = (ta[key] as? Int ?? 0) != 0
            ta[key] = on ? nil : NSUnderlineStyle.single.rawValue
            textView.typingAttributes = ta
            refreshState()
            return
        }
        var all = true
        storage.enumerateAttribute(key, in: sel, options: []) { v, _, _ in if (v as? Int ?? 0) == 0 { all = false } }
        setAttributes(in: sel, actionName: name) { attrs in
            attrs[key] = all ? nil : NSUnderlineStyle.single.rawValue
        }
    }

    func applyHighlight(_ h: Highlight?) {
        let sel = textView.selectedRange()
        if sel.length == 0 {
            var ta = textView.typingAttributes
            let current = ta[.tideHighlight] as? Int
            if let h, current != h.rawValue {
                ta[.backgroundColor] = h.color
                ta[.tideHighlight] = h.rawValue
            } else {
                ta[.backgroundColor] = nil
                ta[.tideHighlight] = nil
            }
            textView.typingAttributes = ta
            refreshState()
            return
        }
        var allSame = h != nil
        if let h {
            storage.enumerateAttribute(.tideHighlight, in: sel, options: []) { v, _, _ in if (v as? Int) != h.rawValue { allSame = false } }
        }
        let target: Highlight? = allSame ? nil : h
        setAttributes(in: sel, actionName: target == nil ? "Remove Highlight" : "Highlight") { attrs in
            if let t = target {
                attrs[.backgroundColor] = t.color
                attrs[.tideHighlight] = t.rawValue
            } else {
                attrs[.backgroundColor] = nil
                attrs[.tideHighlight] = nil
            }
        }
    }

    // MARK: - Paragraph styles

    func applyTextStyle(_ style: TextStyle) {
        let t = typography
        let pr = (storage.string as NSString).paragraphRange(for: textView.selectedRange())
        if pr.length == 0 {
            var ta = textView.typingAttributes
            let f = ta[.font] as? NSFont
            ta[.font] = t.font(for: style, bold: style.isBold, italic: f?.isItalic ?? false)
            ta[.paragraphStyle] = t.paragraphStyle(for: style, base: ta[.paragraphStyle] as? NSParagraphStyle)
            ta[.tideStyle] = style.rawValue
            textView.typingAttributes = ta
            refreshState()
            return
        }
        setAttributes(in: pr, actionName: style.label) { attrs in
            let previous = TextStyle.of(attrs, t)
            if attrs[.attachment] == nil, let f = attrs[.font] as? NSFont {
                let keepBold = previous == .body ? f.isBold : false
                let family = f.familyName ?? t.family
                let mono = family == Typography.monoFamily
                attrs[.font] = t.font(family: family, size: t.size(for: style) * (mono ? 0.92 : 1), bold: style.isBold || keepBold, italic: f.isItalic)
            }
            attrs[.paragraphStyle] = t.paragraphStyle(for: style, base: attrs[.paragraphStyle] as? NSParagraphStyle)
            attrs[.tideStyle] = style.rawValue
        }
    }

    func setAlignment(_ a: NSTextAlignment) {
        switch a {
        case .center: textView.alignCenter(nil)
        case .right: textView.alignRight(nil)
        case .justified: textView.alignJustified(nil)
        default: textView.alignLeft(nil)
        }
        refreshState()
    }

    func changeIndent(by delta: Int) {
        let paragraphs = paragraphRanges(in: textView.selectedRange())
        guard let first = paragraphs.first else { return }
        if paragraphs.allSatisfy({ ListKind.of(paragraphStyle(at: $0)) != nil }) {
            let kind = ListKind.of(paragraphStyle(at: first))
            let level = max(0, (paragraphStyle(at: first)?.textLists.count ?? 1) - 1)
            if delta < 0 && level == 0 { setList(nil, paragraphs: paragraphs) } else { setList(kind, paragraphs: paragraphs, levelDelta: delta) }
            return
        }
        for pr in paragraphs.reversed() where pr.length > 0 {
            guard let ps = paragraphStyle(at: pr)?.mutableCopy() as? NSMutableParagraphStyle else { continue }
            let step = CGFloat(delta) * 24
            ps.headIndent = max(0, ps.headIndent + step)
            ps.firstLineHeadIndent = max(0, ps.firstLineHeadIndent + step)
            addAttributes([.paragraphStyle: ps], in: pr)
        }
        textView.undoManager?.setActionName(delta > 0 ? "Indent" : "Outdent")
        syncTypingAttributes()
        refreshState()
    }

    // MARK: - Lists

    func toggleList(_ kind: ListKind) {
        let paragraphs = paragraphRanges(in: textView.selectedRange())
        let allKind = paragraphs.allSatisfy { ListKind.of(paragraphStyle(at: $0)) == kind }
        setList(allKind ? nil : kind, paragraphs: paragraphs)
    }

    func removeList() {
        setList(nil, paragraphs: paragraphRanges(in: textView.selectedRange()))
    }

    func setList(_ kind: ListKind?, paragraphs: [NSRange], levelDelta: Int = 0) {
        let sel = textView.selectedRange()
        var selDelta = 0
        textView.undoManager?.beginUndoGrouping()
        for pr in paragraphs.reversed() {
            let str = storage.string as NSString
            let attrs: [NSAttributedString.Key: Any] = (pr.length > 0 && pr.location < storage.length) ? storage.attributes(at: pr.location, effectiveRange: nil) : textView.typingAttributes
            let ps = (attrs[.paragraphStyle] as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
            let existing = pr.length > 0 ? ListSupport.markerPrefixRange(in: str, paragraph: pr) : nil
            var level = existing != nil ? max(0, ps.textLists.count - 1) : 0
            level = min(max(level + levelDelta, 0), 2)
            ListSupport.configure(ps, kind: kind, level: level)
            let newPrefix = kind.map { ListSupport.prefix(kind: $0, level: level, itemNumber: 1) } ?? ""
            var prefixAttrs = cleanAttributes(attrs)
            prefixAttrs[.paragraphStyle] = ps
            let replaceRange = existing ?? NSRange(location: pr.location, length: 0)
            if replaceRange.length > 0 || !newPrefix.isEmpty {
                replaceText(in: replaceRange, with: NSAttributedString(string: newPrefix, attributes: prefixAttrs))
            }
            let newLength = pr.length - replaceRange.length + (newPrefix as NSString).length
            let newRange = NSRange(location: pr.location, length: newLength)
            if newRange.length > 0 {
                addAttributes([.paragraphStyle: ps], in: newRange)
            } else {
                var ta = textView.typingAttributes
                ta[.paragraphStyle] = ps
                textView.typingAttributes = ta
            }
            if pr.location <= sel.location { selDelta += (newPrefix as NSString).length - replaceRange.length }
        }
        textView.undoManager?.endUndoGrouping()
        textView.undoManager?.setActionName(kind == nil ? "Remove List" : "List")
        renumberLists(register: true)
        let newLoc = max(0, min(storage.length, sel.location + selDelta))
        textView.setSelectedRange(NSRange(location: newLoc, length: min(sel.length, storage.length - newLoc)))
        syncTypingAttributes()
        refreshState()
    }

    /// Re-labels numbered items so they always read 1, 2, 3… after any edit.
    func renumberLists(register: Bool) {
        guard !isRenumbering, storage.length > 0 else { return }
        let str = storage.string as NSString
        var edits: [(NSRange, String)] = []
        var loc = 0
        var counters: [(kind: ListKind, n: Int)] = []
        var inList = false
        while loc < str.length {
            let pr = str.paragraphRange(for: NSRange(location: loc, length: 0))
            let ps = storage.attribute(.paragraphStyle, at: pr.location, effectiveRange: nil) as? NSParagraphStyle
            if let kind = ListKind.of(ps), let prefix = ListSupport.markerPrefixRange(in: str, paragraph: pr) {
                let level = max(0, (ps?.textLists.count ?? 1) - 1)
                if !inList { counters = [] }
                if counters.count > level + 1 { counters.removeLast(counters.count - level - 1) }
                while counters.count < level + 1 { counters.append((kind, 0)) }
                if counters[level].kind != kind { counters[level] = (kind, 0) }
                counters[level].n += 1
                let expected = ListSupport.prefix(kind: kind, level: level, itemNumber: counters[level].n)
                if str.substring(with: prefix) != expected { edits.append((prefix, expected)) }
                inList = true
            } else {
                inList = false
                counters = []
            }
            loc = NSMaxRange(pr)
            if pr.length == 0 { break }
        }
        guard !edits.isEmpty else { return }
        isRenumbering = true
        for (range, text) in edits.reversed() {
            let attrs = storage.attributes(at: range.location, effectiveRange: nil)
            let replacement = NSAttributedString(string: text, attributes: attrs)
            if register {
                replaceText(in: range, with: replacement)
            } else {
                storage.replaceCharacters(in: range, with: replacement)
            }
        }
        isRenumbering = false
    }

    private func scheduleRenumber() {
        guard !renumberScheduled, !isRenumbering else { return }
        renumberScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.renumberScheduled = false
            let sel = self.textView.selectedRange()
            self.renumberLists(register: true)
            if sel != self.textView.selectedRange(), sel.location <= self.storage.length {
                self.textView.setSelectedRange(sel)
            }
        }
    }

    // MARK: - Return / Delete / Tab inside lists and headings

    private func handleInsertNewline() -> Bool {
        let sel = textView.selectedRange()
        guard sel.length == 0 else { return false }
        let str = storage.string as NSString
        let pr = str.paragraphRange(for: sel)
        let attrs: [NSAttributedString.Key: Any] = (pr.length > 0 && pr.location < storage.length) ? storage.attributes(at: pr.location, effectiveRange: nil) : textView.typingAttributes
        let ps = attrs[.paragraphStyle] as? NSParagraphStyle
        var contentEnd = NSMaxRange(pr)
        if pr.length > 0, str.character(at: contentEnd - 1) == 0x0A { contentEnd -= 1 }

        if let kind = ListKind.of(ps), let prefix = ListSupport.markerPrefixRange(in: str, paragraph: pr) {
            let level = max(0, (ps?.textLists.count ?? 1) - 1)
            if NSMaxRange(prefix) >= contentEnd {
                setList(nil, paragraphs: [pr])
                return true
            }
            guard sel.location >= NSMaxRange(prefix) else { return false }
            var newAttrs = cleanAttributes(storage.attributes(at: NSMaxRange(prefix), effectiveRange: nil))
            newAttrs[.paragraphStyle] = ps
            let s = NSAttributedString(string: "\n" + ListSupport.prefix(kind: kind, level: level, itemNumber: 1), attributes: newAttrs)
            replaceText(in: sel, with: s)
            textView.setSelectedRange(NSRange(location: sel.location + s.length, length: 0))
            renumberLists(register: true)
            syncTypingAttributes()
            refreshState()
            return true
        }

        let style = TextStyle.of(attrs, typography)
        if style != .body, sel.location == contentEnd {
            textView.insertText("\n", replacementRange: sel)
            textView.typingAttributes = typography.bodyAttributes(alignment: ps?.alignment ?? .natural)
            refreshState()
            return true
        }
        return false
    }

    private func handleDeleteBackward() -> Bool {
        let sel = textView.selectedRange()
        guard sel.length == 0, sel.location > 0 else { return false }
        let str = storage.string as NSString
        let pr = str.paragraphRange(for: sel)
        guard let prefix = ListSupport.markerPrefixRange(in: str, paragraph: pr), sel.location == NSMaxRange(prefix) else { return false }
        setList(nil, paragraphs: [pr])
        return true
    }

    private func handleTab(delta: Int) -> Bool {
        let sel = textView.selectedRange()
        let str = storage.string as NSString
        let pr = str.paragraphRange(for: sel)
        guard ListKind.of(paragraphStyle(at: pr)) != nil, let prefix = ListSupport.markerPrefixRange(in: str, paragraph: pr) else {
            return delta < 0
        }
        if sel.length > 0 || sel.location == NSMaxRange(prefix) || delta < 0 {
            changeIndent(by: delta)
            return true
        }
        return false
    }

    private func keepCaretOutOfMarker() {
        let sel = textView.selectedRange()
        guard sel.length == 0, sel.location < storage.length else { return }
        let str = storage.string as NSString
        let pr = str.paragraphRange(for: sel)
        guard let prefix = ListSupport.markerPrefixRange(in: str, paragraph: pr), sel.location < NSMaxRange(prefix) else { return }
        adjustingSelection = true
        textView.setSelectedRange(NSRange(location: NSMaxRange(prefix), length: 0))
        adjustingSelection = false
    }

    // MARK: - Insert media

    private func openPanel(types: [UTType], handler: @escaping ([URL]) -> Void) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = types
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        let finish: (NSApplication.ModalResponse) -> Void = { [weak self] resp in
            guard resp == .OK else { self?.focus(); return }
            handler(panel.urls)
            self?.focus()
        }
        if let window = textView.window {
            panel.beginSheetModal(for: window, completionHandler: finish)
        } else {
            finish(panel.runModal())
        }
    }

    func insertImageFromPanel() {
        openPanel(types: [.image]) { [weak self] urls in urls.forEach { self?.insertImage(url: $0) } }
    }
    func insertFileFromPanel() {
        openPanel(types: [.item]) { [weak self] urls in urls.forEach { self?.insertFileChip(url: $0) } }
    }
    func insertAudioFromPanel() {
        openPanel(types: [.audio]) { [weak self] urls in urls.forEach { self?.insertFileChip(url: $0) } }
    }

    func insertImage(url: URL, at index: Int? = nil) {
        guard let data = try? Data(contentsOf: url),
              let att = AttachmentFactory.imageAttachment(data: data, filename: url.lastPathComponent, displaySize: nil, maxWidth: textWidth) else { return }
        insertAttachment(att, at: index, actionName: "Insert Image")
    }

    func insertFileChip(url: URL, at index: Int? = nil) {
        if AttachmentFactory.isImage(name: url.lastPathComponent, data: nil) { insertImage(url: url, at: index); return }
        guard let att = AttachmentFactory.chipAttachment(fileURL: url) else { return }
        insertAttachment(att, at: index, actionName: "Insert File")
    }

    func insertAttachment(_ att: NSTextAttachment, at index: Int? = nil, actionName: String, extra: [NSAttributedString.Key: Any] = [:]) {
        let range = index.map { NSRange(location: min($0, storage.length), length: 0) } ?? textView.selectedRange()
        var attrs = cleanAttributes(textView.typingAttributes)
        if range.length > 0, range.location < storage.length { attrs = cleanAttributes(storage.attributes(at: range.location, effectiveRange: nil)) }
        attrs.merge(extra) { $1 }
        attrs[.attachment] = att
        replaceText(in: range, with: NSAttributedString(string: "\u{FFFC}", attributes: attrs))
        textView.setSelectedRange(NSRange(location: range.location + 1, length: 0))
        textView.undoManager?.setActionName(actionName)
        syncTypingAttributes()
    }

    // MARK: - Equations

    func equationFontSize(display: Bool) -> CGFloat { (typography.bodySize * (display ? 1.35 : 1.15)).rounded() }

    func requestEquation() {
        equationRequest = EquationRequest(source: "", display: true, replaceRange: nil)
    }

    func editEquation(at index: Int) {
        guard index < storage.length,
              let att = storage.attribute(.attachment, at: index, effectiveRange: nil) as? NSTextAttachment,
              let cell = att.attachmentCell as? EquationCell else { return }
        equationRequest = EquationRequest(source: cell.source, display: cell.display, replaceRange: NSRange(location: index, length: 1))
    }

    func commitEquation(_ req: EquationRequest) {
        let source = req.source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return }
        EquationRenderer.shared.render(latex: source, display: req.display, fontSize: equationFontSize(display: req.display)) { [weak self] result in
            guard let self else { return }
            let size = result?.size ?? NSSize(width: max(40, CGFloat(source.count) * 8), height: 24)
            let att = AttachmentFactory.equationAttachment(pngData: result?.png, source: source, display: req.display, displaySize: size, baselineDrop: result?.baselineDrop ?? 0)
            if let range = req.replaceRange, NSMaxRange(range) <= self.storage.length {
                var attrs = self.storage.attributes(at: range.location, effectiveRange: nil)
                attrs[.attachment] = att
                attrs[.tideEquation] = source
                self.replaceText(in: range, with: NSAttributedString(string: "\u{FFFC}", attributes: attrs))
                self.textView.undoManager?.setActionName("Edit Equation")
            } else if req.display {
                self.insertDisplayEquation(att, source: source)
            } else {
                self.insertAttachment(att, actionName: "Insert Equation", extra: [.tideEquation: source])
            }
            self.focus()
        }
    }

    private func insertDisplayEquation(_ att: NSTextAttachment, source: String) {
        let sel = textView.selectedRange()
        let str = storage.string as NSString
        let pr = str.paragraphRange(for: sel)
        let atStart = sel.location == pr.location
        let base = cleanAttributes(textView.typingAttributes)
        let ps = typography.paragraphStyle(for: .body)
        ps.alignment = .center
        var eqAttrs = base
        eqAttrs[.paragraphStyle] = ps
        eqAttrs[.attachment] = att
        eqAttrs[.tideEquation] = source
        var lineAttrs = base
        lineAttrs[.paragraphStyle] = ps
        let s = NSMutableAttributedString()
        if !atStart { s.append(NSAttributedString(string: "\n", attributes: base)) }
        s.append(NSAttributedString(string: "\u{FFFC}", attributes: eqAttrs))
        s.append(NSAttributedString(string: "\n", attributes: lineAttrs))
        replaceText(in: sel, with: s)
        textView.setSelectedRange(NSRange(location: sel.location + s.length, length: 0))
        textView.typingAttributes = typography.bodyAttributes()
        textView.undoManager?.setActionName("Insert Equation")
        refreshState()
    }

    /// Equations imported from Markdown or docx without a picture get rendered after load.
    func renderPendingEquations() {
        guard storage.length > 0 else { return }
        var pending: [EquationCell] = []
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length), options: []) { v, _, _ in
            if let a = v as? NSTextAttachment, let c = a.attachmentCell as? EquationCell, c.needsRender { pending.append(c) }
        }
        for cell in pending {
            EquationRenderer.shared.render(latex: cell.source, display: cell.display, fontSize: equationFontSize(display: cell.display)) { [weak self] result in
                guard let self, let result else { return }
                cell.setRendered(png: result.png, image: result.image, size: result.size, baselineDrop: result.baselineDrop)
                if let att = cell.attachment {
                    let fw = FileWrapper(regularFileWithContents: result.png)
                    fw.preferredFilename = EquationCell.fileName(source: cell.source, display: cell.display, baselineDrop: result.baselineDrop)
                    att.fileWrapper = fw
                    att.bounds = CGRect(origin: .zero, size: result.size)
                }
                self.invalidateLayout()
            }
        }
    }

    func invalidateLayout() {
        guard let lm = textView.layoutManager, let tc = textView.textContainer else { return }
        lm.invalidateLayout(forCharacterRange: NSRange(location: 0, length: storage.length), actualCharacterRange: nil)
        lm.ensureLayout(for: tc)
        textView.sizeToFit()
        textView.needsDisplay = true
        pageHost.needsLayout = true
    }

    // MARK: - Links

    func requestLink() {
        let sel = textView.selectedRange()
        let text = (storage.string as NSString).substring(with: sel)
        var url = ""
        if sel.length > 0, let l = storage.attribute(.link, at: sel.location, effectiveRange: nil) {
            url = (l as? URL)?.absoluteString ?? (l as? String) ?? ""
        }
        linkRequest = LinkRequest(url: url, text: text, range: sel)
    }

    func commitLink(_ req: LinkRequest) {
        var urlString = req.url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !urlString.isEmpty else { return }
        if !urlString.contains("://") && !urlString.hasPrefix("mailto:") { urlString = "https://" + urlString }
        guard let url = URL(string: urlString) else { return }
        let text = req.text.isEmpty ? urlString : req.text
        let range = NSMaxRange(req.range) <= storage.length ? req.range : textView.selectedRange()
        var attrs = cleanAttributes(range.length > 0 ? storage.attributes(at: range.location, effectiveRange: nil) : textView.typingAttributes)
        attrs[.link] = url
        replaceText(in: range, with: NSAttributedString(string: text, attributes: attrs))
        textView.setSelectedRange(NSRange(location: range.location + (text as NSString).length, length: 0))
        var ta = textView.typingAttributes
        ta[.link] = nil
        textView.typingAttributes = ta
        textView.undoManager?.setActionName("Add Link")
        focus()
    }

    // MARK: - Import

    func importFile(url: URL) throws {
        let s = try Importers.attributedString(from: url, typography: typography)
        let m = NSMutableAttributedString(attributedString: s)
        AttachmentFactory.installCells(in: m, availableWidth: textWidth)
        let range = textView.selectedRange()
        let str = storage.string as NSString
        if range.location > 0, range.location <= str.length, str.character(at: range.location - 1) != 0x0A {
            m.insert(NSAttributedString(string: "\n", attributes: cleanAttributes(textView.typingAttributes)), at: 0)
        }
        replaceText(in: range, with: m)
        textView.setSelectedRange(NSRange(location: range.location + m.length, length: 0))
        textView.undoManager?.setActionName("Import")
        renumberLists(register: true)
        renderPendingEquations()
        syncTypingAttributes()
        refreshState()
    }

    // MARK: - Settings

    func setZoom(_ z: CGFloat) {
        Settings.zoom = min(3, max(0.5, (z * 100).rounded() / 100))
    }

    func applySettings(initial: Bool) {
        let t = Typography.current
        let typographyChanged = t != typography
        typography = t
        textView.isContinuousSpellCheckingEnabled = Settings.spellCheck
        textView.isAutomaticSpellingCorrectionEnabled = Settings.autocorrect
        textView.isAutomaticQuoteSubstitutionEnabled = Settings.smartQuotes
        textView.isAutomaticDashSubstitutionEnabled = Settings.smartQuotes
        let paper = Settings.paper
        textView.appearance = paper == .light ? NSAppearance(named: .aqua) : nil
        pageHost.paperColor = paper == .light ? Theme.paperLight : Theme.paperDynamic
        pageHost.pageWidth = Settings.pageWidth.points
        pageHost.panelSide = Settings.panelSide
        pageHost.panelInset = Settings.panelHidden ? 40 : 84
        if abs(scrollView.magnification - Settings.zoom) > 0.001 { scrollView.magnification = Settings.zoom }
        if typographyChanged && !initial { restyleDocument() }
        if initial || typographyChanged {
            textView.defaultParagraphStyle = t.paragraphStyle(for: .body)
            if storage.length == 0 { textView.typingAttributes = t.bodyAttributes() }
        }
        appliedFamily = t.family
        pageHost.needsLayout = true
        pageHost.needsDisplay = true
    }

    private func restyleDocument() {
        let t = typography
        guard storage.length > 0 else { textView.typingAttributes = t.bodyAttributes(); return }
        let previousFamily = appliedFamily
        let str = storage.string as NSString
        storage.beginEditing()
        var loc = 0
        while loc < storage.length {
            let pr = str.paragraphRange(for: NSRange(location: loc, length: 0))
            guard pr.length > 0 else { break }
            let pAttrs = storage.attributes(at: pr.location, effectiveRange: nil)
            let style = TextStyle.of(pAttrs, t)
            storage.enumerateAttributes(in: pr, options: []) { attrs, r, _ in
                guard attrs[.attachment] == nil, let f = attrs[.font] as? NSFont else { return }
                let fam = f.familyName ?? ""
                let ours = fam == previousFamily || fam.hasPrefix(".") || fam == t.family || previousFamily == Settings.systemFamily
                let mono = fam == Typography.monoFamily
                let family = (ours && !mono) ? t.family : fam
                storage.addAttribute(.font, value: t.font(family: family, size: t.size(for: style) * (mono ? 0.92 : 1), bold: f.isBold, italic: f.isItalic), range: r)
            }
            if let ps = pAttrs[.paragraphStyle] as? NSParagraphStyle {
                storage.addAttribute(.paragraphStyle, value: t.paragraphStyle(for: style, base: ps), range: pr)
            }
            loc = NSMaxRange(pr)
        }
        storage.endEditing()
        document?.updateChangeCount(.changeDone)
        syncTypingAttributes()
        invalidateLayout()
        refreshState()
    }

    // MARK: - State & counts

    func refreshState() {
        let sel = textView.selectedRange()
        var s = SelectionState()
        let attrs: [NSAttributedString.Key: Any]
        if sel.length == 0 || sel.location >= storage.length {
            attrs = textView.typingAttributes
        } else {
            attrs = storage.attributes(at: sel.location, effectiveRange: nil)
        }
        if sel.length > 0, NSMaxRange(sel) <= storage.length {
            var bold = true, italic = true, underline = true, strike = true, sameHighlight = true
            let hl = attrs[.tideHighlight] as? Int
            var sawText = false
            storage.enumerateAttributes(in: sel, options: []) { a, _, _ in
                if a[.attachment] != nil { return }
                sawText = true
                let f = a[.font] as? NSFont
                if !(f?.isBold ?? false) { bold = false }
                if !(f?.isItalic ?? false) { italic = false }
                if (a[.underlineStyle] as? Int ?? 0) == 0 { underline = false }
                if (a[.strikethroughStyle] as? Int ?? 0) == 0 { strike = false }
                if (a[.tideHighlight] as? Int) != hl { sameHighlight = false }
            }
            s.bold = sawText && bold
            s.italic = sawText && italic
            s.underline = sawText && underline
            s.strike = sawText && strike
            s.highlight = sameHighlight ? hl.flatMap(Highlight.init(rawValue:)) : nil
        } else {
            let f = attrs[.font] as? NSFont
            s.bold = f?.isBold ?? false
            s.italic = f?.isItalic ?? false
            s.underline = (attrs[.underlineStyle] as? Int ?? 0) != 0
            s.strike = (attrs[.strikethroughStyle] as? Int ?? 0) != 0
            s.highlight = (attrs[.tideHighlight] as? Int).flatMap(Highlight.init(rawValue:))
        }
        s.style = TextStyle.of(attrs, typography)
        let ps = attrs[.paragraphStyle] as? NSParagraphStyle
        s.list = ListKind.of(ps)
        s.alignment = ps?.alignment ?? .natural
        if s != state { state = s }
    }

    private func scheduleCount() {
        countTimer?.invalidate()
        countTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in self?.updateCounts() }
    }

    func updateCounts() {
        let s = storage.string
        var words = 0
        s.enumerateSubstrings(in: s.startIndex..<s.endIndex, options: [.byWords, .substringNotRequired]) { _, _, _, _ in words += 1 }
        if let re = try? NSRegularExpression(pattern: "\\t[0-9a-z]+\\.\\t", options: []) {
            words -= re.numberOfMatches(in: s, options: [], range: NSRange(location: 0, length: (s as NSString).length))
        }
        let chars = s.unicodeScalars.filter { $0 != "\n" && $0 != "\u{FFFC}" && $0 != "\t" }.count
        if wordCount != max(0, words) { wordCount = max(0, words) }
        if characterCount != chars { characterCount = chars }
    }
}

// MARK: - Delegates

extension EditorController: NSTextViewDelegate {
    func undoManager(for view: NSTextView) -> UndoManager? { document?.undoManager }

    func textDidChange(_ notification: Notification) {
        if storage.length == 0 { textView.typingAttributes = typography.bodyAttributes() }
        if !isRenumbering { scheduleRenumber() }
        scheduleCount()
        refreshState()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        guard !adjustingSelection else { return }
        keepCaretOutOfMarker()
        refreshState()
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)): return handleInsertNewline()
        case #selector(NSResponder.deleteBackward(_:)): return handleDeleteBackward()
        case #selector(NSResponder.insertTab(_:)): return handleTab(delta: 1)
        case #selector(NSResponder.insertBacktab(_:)): return handleTab(delta: -1)
        default: return false
        }
    }

    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        if let url = link as? URL { NSWorkspace.shared.open(url); return true }
        if let s = link as? String, let url = URL(string: s) { NSWorkspace.shared.open(url); return true }
        return false
    }
}

extension EditorController: NSTextStorageDelegate {
    func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters), editedRange.length > 0 else { return }
        let width = textWidth
        var replacements: [(NSRange, NSTextAttachment)] = []
        textStorage.enumerateAttribute(.attachment, in: editedRange, options: []) { v, r, _ in
            guard let att = v as? NSTextAttachment else { return }
            let kept = AttachmentFactory.installCell(on: att, availableWidth: width)
            if kept !== att { replacements.append((r, kept)) }
        }
        for (r, att) in replacements { textStorage.addAttribute(.attachment, value: att, range: r) }
    }
}
