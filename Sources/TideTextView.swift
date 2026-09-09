import AppKit
import UniformTypeIdentifiers

/// The editor's NSTextView. Menu actions land here through the responder chain and are
/// forwarded to the EditorController, which owns the formatting logic.
final class TideTextView: NSTextView {
    weak var editor: EditorController?

    override var acceptsFirstResponder: Bool { true }

    // MARK: Format menu

    @objc func tideBold(_ sender: Any?) { editor?.toggleBold() }
    @objc func tideItalic(_ sender: Any?) { editor?.toggleItalic() }
    @objc func tideUnderline(_ sender: Any?) { editor?.toggleUnderline() }
    @objc func tideStrikethrough(_ sender: Any?) { editor?.toggleStrikethrough() }
    @objc func tideStyle(_ sender: NSMenuItem) {
        guard sender.tag >= 0, sender.tag < TextStyle.allCases.count else { return }
        editor?.applyTextStyle(TextStyle.allCases[sender.tag])
    }
    @objc func tideHighlight(_ sender: NSMenuItem) { editor?.applyHighlight(Highlight(rawValue: sender.tag)) }
    @objc func tideList(_ sender: NSMenuItem) {
        switch sender.tag {
        case 1: editor?.toggleList(.bullet)
        case 2: editor?.toggleList(.numbered)
        default: editor?.removeList()
        }
    }
    @objc func tideAlign(_ sender: NSMenuItem) { editor?.setAlignment(NSTextAlignment(rawValue: sender.tag) ?? .natural) }
    @objc func tideIndent(_ sender: Any?) { editor?.changeIndent(by: 1) }
    @objc func tideOutdent(_ sender: Any?) { editor?.changeIndent(by: -1) }

    // MARK: Insert menu

    @objc func tideInsertImage(_ sender: Any?) { editor?.insertImageFromPanel() }
    @objc func tideInsertFile(_ sender: Any?) { editor?.insertFileFromPanel() }
    @objc func tideInsertAudio(_ sender: Any?) { editor?.insertAudioFromPanel() }
    @objc func tideInsertEquation(_ sender: Any?) { editor?.requestEquation() }
    @objc func tideInsertLink(_ sender: Any?) { editor?.requestLink() }
    @objc func tideInsertDate(_ sender: Any?) {
        let f = DateFormatter()
        f.dateStyle = .long
        f.timeStyle = .none
        insertText(f.string(from: Date()), replacementRange: selectedRange())
    }

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        guard let action = item.action else { return super.validateUserInterfaceItem(item) }
        let menuItem = item as? NSMenuItem
        let st = editor?.state ?? SelectionState()
        switch action {
        case #selector(tideBold(_:)):
            menuItem?.state = st.bold ? .on : .off
            return isEditable
        case #selector(tideItalic(_:)):
            menuItem?.state = st.italic ? .on : .off
            return isEditable
        case #selector(tideUnderline(_:)):
            menuItem?.state = st.underline ? .on : .off
            return isEditable
        case #selector(tideStrikethrough(_:)):
            menuItem?.state = st.strike ? .on : .off
            return isEditable
        case #selector(tideStyle(_:)):
            if let m = menuItem, m.tag >= 0, m.tag < TextStyle.allCases.count { m.state = TextStyle.allCases[m.tag] == st.style ? .on : .off }
            return isEditable
        case #selector(tideHighlight(_:)):
            if let m = menuItem { m.state = (st.highlight?.rawValue ?? 0) == m.tag ? .on : .off }
            return isEditable
        case #selector(tideList(_:)):
            if let m = menuItem { m.state = (st.list?.rawValue ?? 0) == m.tag ? .on : .off }
            return isEditable
        case #selector(tideAlign(_:)):
            if let m = menuItem {
                let a: NSTextAlignment = st.alignment == .natural ? .left : st.alignment
                m.state = a.rawValue == m.tag ? .on : .off
            }
            return isEditable
        case #selector(tideIndent(_:)), #selector(tideOutdent(_:)), #selector(tideInsertImage(_:)), #selector(tideInsertFile(_:)),
             #selector(tideInsertAudio(_:)), #selector(tideInsertEquation(_:)), #selector(tideInsertLink(_:)), #selector(tideInsertDate(_:)):
            return isEditable
        default:
            return super.validateUserInterfaceItem(item)
        }
    }

    // MARK: Files dropped or pasted become chips (or pictures)

    private func fileURLs(on pasteboard: NSPasteboard) -> [URL] {
        (pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = fileURLs(on: sender.draggingPasteboard)
        if !urls.isEmpty, let editor {
            let point = convert(sender.draggingLocation, from: nil)
            var index = characterIndexForInsertion(at: point)
            for url in urls {
                editor.insertFileChip(url: url, at: index)
                index += 1
            }
            window?.makeFirstResponder(self)
            return true
        }
        return super.performDragOperation(sender)
    }

    override func paste(_ sender: Any?) {
        let pb = NSPasteboard.general
        let textTypes: [NSPasteboard.PasteboardType] = [.string, .rtf, .rtfd, .html]
        let hasText = pb.types?.contains(where: { textTypes.contains($0) }) ?? false
        if !hasText, let editor {
            let urls = fileURLs(on: pb)
            if !urls.isEmpty {
                for url in urls { editor.insertFileChip(url: url) }
                return
            }
        }
        super.paste(sender)
    }
}
