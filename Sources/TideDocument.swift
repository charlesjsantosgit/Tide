import AppKit
import UniformTypeIdentifiers

final class TideDocumentController: NSDocumentController {
    override var defaultType: String? { DocFormat.docx.identifier }
}

final class TideDocument: NSDocument {
    /// Content read from disk; the live text lives in the editor once a window exists.
    var content = NSAttributedString()
    weak var editor: EditorController?

    var typography: Typography { editor?.typography ?? Typography.current }
    var currentText: NSAttributedString { editor?.currentText ?? content }
    var title: String { displayName ?? "Untitled" }

    override class var autosavesInPlace: Bool { true }

    override func makeWindowControllers() {
        addWindowController(DocumentWindowController(document: self))
    }

    // MARK: Reading

    override func read(from fileWrapper: FileWrapper, ofType typeName: String) throws {
        if DocFormat.from(typeIdentifier: typeName) == .rtfd, fileWrapper.isDirectory {
            guard let s = NSAttributedString(rtfdFileWrapper: fileWrapper, documentAttributes: nil) else { throw ExportError.unreadable }
            content = Importers.tagStyles(s, typography: typography)
            editor?.load(content)
            return
        }
        try super.read(from: fileWrapper, ofType: typeName)
    }

    override func read(from data: Data, ofType typeName: String) throws {
        guard let format = DocFormat.from(typeIdentifier: typeName) else { throw ExportError.unsupported(typeName) }
        content = try Importers.attributedString(from: data, format: format, typography: typography, baseURL: fileURL)
        editor?.load(content)
    }

    // MARK: Writing

    override func data(ofType typeName: String) throws -> Data {
        guard let format = DocFormat.from(typeIdentifier: typeName) else { throw ExportError.unsupported(typeName) }
        return try Exporters.data(text: currentText, format: format, title: title, typography: typography)
    }

    override func fileWrapper(ofType typeName: String) throws -> FileWrapper {
        if DocFormat.from(typeIdentifier: typeName) == .rtfd {
            return try Exporters.fileWrapper(text: currentText, format: .rtfd, title: title, typography: typography)
        }
        return try super.fileWrapper(ofType: typeName)
    }

    override func writableTypes(for saveOperation: NSDocument.SaveOperationType) -> [String] {
        switch saveOperation {
        case .saveAsOperation, .saveToOperation:
            return [DocFormat.docx, .rtfd, .rtf, .txt, .markdown, .html].map { $0.identifier }
        default:
            return [fileType ?? DocFormat.docx.identifier]
        }
    }

    override func printOperation(withSettings printSettings: [NSPrintInfo.AttributeKey: Any]) throws -> NSPrintOperation {
        let info = printInfo.copy() as! NSPrintInfo
        info.dictionary().addEntries(from: printSettings)
        return PDFExporter.printOperation(text: currentText, printInfo: info, title: title)
    }

    // MARK: Import / Export menu actions

    @objc func importDocument(_ sender: Any?) {
        guard let window = windowForSheet, let editor else { return }
        let panel = NSOpenPanel()
        var types: [UTType] = [.rtf, .rtfd, .plainText, .html]
        if let docx = UTType(DocFormat.docxIdentifier) { types.append(docx) }
        if let md = UTType(DocFormat.markdownIdentifier) { types.append(md) }
        if let md2 = UTType(filenameExtension: "md") { types.append(md2) }
        panel.allowedContentTypes = types
        panel.allowsMultipleSelection = false
        panel.message = "Choose a document to insert at the cursor"
        panel.beginSheetModal(for: window) { resp in
            guard resp == .OK, let url = panel.url else { return }
            do { try editor.importFile(url: url) } catch { self.presentError(error) }
            editor.focus()
        }
    }

    @objc func exportPDF(_ sender: Any?) { export(.pdf) }
    @objc func exportDocx(_ sender: Any?) { export(.docx) }
    @objc func exportRTF(_ sender: Any?) { export(.rtf) }
    @objc func exportRTFD(_ sender: Any?) { export(.rtfd) }
    @objc func exportTXT(_ sender: Any?) { export(.txt) }
    @objc func exportMarkdown(_ sender: Any?) { export(.markdown) }
    @objc func exportHTML(_ sender: Any?) { export(.html) }

    private func export(_ format: DocFormat) {
        guard let window = windowForSheet else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.utType]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        let base = (title as NSString).deletingPathExtension
        panel.nameFieldStringValue = "\(base).\(format.fileExtension)"
        panel.beginSheetModal(for: window) { resp in
            guard resp == .OK, let url = panel.url else { return }
            do {
                if format == .pdf {
                    try PDFExporter.write(text: self.currentText, to: url, title: self.title)
                } else {
                    let fw = try Exporters.fileWrapper(text: self.currentText, format: format, title: self.title, typography: self.typography)
                    try fw.write(to: url, options: .atomic, originalContentsURL: nil)
                }
            } catch {
                self.presentError(error)
            }
        }
    }
}
