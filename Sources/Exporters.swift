import AppKit
import UniformTypeIdentifiers

enum ExportError: Error, LocalizedError {
    case unsupported(String), pdfFailed, unreadable
    var errorDescription: String? {
        switch self {
        case .unsupported(let t): return "Tide can't write \(t) files."
        case .pdfFailed: return "The PDF could not be generated."
        case .unreadable: return "The file could not be read."
        }
    }
}

enum DocFormat: String, CaseIterable {
    case docx, rtfd, rtf, txt, markdown, html, pdf

    static let docxIdentifier = "org.openxmlformats.wordprocessingml.document"
    static let markdownIdentifier = "net.daringfireball.markdown"

    var identifier: String {
        switch self {
        case .docx: return DocFormat.docxIdentifier
        case .rtfd: return "com.apple.rtfd"
        case .rtf: return "public.rtf"
        case .txt: return "public.plain-text"
        case .markdown: return DocFormat.markdownIdentifier
        case .html: return "public.html"
        case .pdf: return "com.adobe.pdf"
        }
    }
    var fileExtension: String {
        switch self {
        case .docx: return "docx"
        case .rtfd: return "rtfd"
        case .rtf: return "rtf"
        case .txt: return "txt"
        case .markdown: return "md"
        case .html: return "html"
        case .pdf: return "pdf"
        }
    }
    var displayName: String {
        switch self {
        case .docx: return "Word Document"
        case .rtfd: return "Rich Text with Attachments"
        case .rtf: return "Rich Text"
        case .txt: return "Plain Text"
        case .markdown: return "Markdown"
        case .html: return "Web Page"
        case .pdf: return "PDF"
        }
    }
    var utType: UTType { UTType(identifier) ?? UTType(filenameExtension: fileExtension) ?? .data }

    static func from(typeIdentifier: String) -> DocFormat? {
        if let f = allCases.first(where: { $0.identifier == typeIdentifier }) { return f }
        if typeIdentifier.contains("wordprocessingml") { return .docx }
        guard let t = UTType(typeIdentifier) else { return nil }
        if t.conforms(to: .rtfd) { return .rtfd }
        if t.conforms(to: .rtf) { return .rtf }
        if let md = UTType(markdownIdentifier), t.conforms(to: md) { return .markdown }
        if t.conforms(to: .html) { return .html }
        if t.conforms(to: .pdf) { return .pdf }
        if t.conforms(to: .plainText) || t.conforms(to: .text) { return .txt }
        return nil
    }

    static func from(url: URL) -> DocFormat? {
        switch url.pathExtension.lowercased() {
        case "docx": return .docx
        case "rtfd": return .rtfd
        case "rtf": return .rtf
        case "txt", "text": return .txt
        case "md", "markdown", "mdown", "mkd": return .markdown
        case "html", "htm": return .html
        case "pdf": return .pdf
        default: return nil
        }
    }
}

enum Exporters {
    static func data(text: NSAttributedString, format: DocFormat, title: String, typography: Typography) throws -> Data {
        let full = NSRange(location: 0, length: text.length)
        switch format {
        case .docx:
            var w = DocxWriter(text: text, typography: typography, title: title, paperSize: Settings.paperSize)
            return try w.makeData()
        case .rtf:
            return try text.data(from: full, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        case .rtfd:
            return try text.data(from: full, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd])
        case .txt:
            return Data(plainText(text, typography: typography).utf8)
        case .markdown:
            return Data(MarkdownExporter.markdown(from: text, typography: typography).utf8)
        case .html:
            return Data(HTMLExporter.html(from: text, title: title, typography: typography).utf8)
        case .pdf:
            return try PDFExporter.data(text: text, title: title)
        }
    }

    static func fileWrapper(text: NSAttributedString, format: DocFormat, title: String, typography: Typography) throws -> FileWrapper {
        if format == .rtfd {
            return try text.fileWrapper(from: NSRange(location: 0, length: text.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd])
        }
        return FileWrapper(regularFileWithContents: try data(text: text, format: format, title: title, typography: typography))
    }

    static func plainText(_ text: NSAttributedString, typography: Typography) -> String {
        var lines: [String] = []
        let str = text.string as NSString
        for p in DocumentWalker.paragraphs(of: text, typography: typography) {
            var line = ""
            if p.listKind != nil, let prefix = ListSupport.markerPrefixRange(in: str, paragraph: p.range) {
                line += String(repeating: "    ", count: p.listLevel) + str.substring(with: prefix).replacingOccurrences(of: "\t", with: "") + " "
            }
            for (s, attrs) in DocumentWalker.runs(of: text, in: p.contentRange) {
                if let att = attrs[.attachment] as? NSTextAttachment {
                    if let eq = att.attachmentCell as? EquationCell { line += eq.display ? "$$\(eq.source)$$" : "$\(eq.source)$" }
                    else if let chip = att.attachmentCell as? FileChipCell { line += "[\(chip.name)]" }
                    else { line += "[image]" }
                } else {
                    line += s.replacingOccurrences(of: "\u{2028}", with: "\n").replacingOccurrences(of: "\u{FFFC}", with: "")
                }
            }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }
}

enum Importers {
    static func attributedString(from data: Data, format: DocFormat, typography: Typography, baseURL: URL?) throws -> NSAttributedString {
        switch format {
        case .docx:
            do {
                return try DocxReader(typography: typography).read(data)
            } catch {
                // Fall back to Apple's reader for anything our parser refuses.
                if let s = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.officeOpenXML], documentAttributes: nil) {
                    return tagStyles(s, typography: typography)
                }
                throw error
            }
        case .rtf:
            let s = try NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
            return tagStyles(s, typography: typography)
        case .rtfd:
            let s = try NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtfd], documentAttributes: nil)
            return tagStyles(s, typography: typography)
        case .html:
            let s = try NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue], documentAttributes: nil)
            return tagStyles(s, typography: typography)
        case .markdown:
            let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
            return MarkdownImporter.attributedString(from: text, typography: typography, baseURL: baseURL)
        case .txt:
            let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
            return NSAttributedString(string: text.replacingOccurrences(of: "\r\n", with: "\n"), attributes: typography.bodyAttributes())
        case .pdf:
            throw ExportError.unsupported("PDF")
        }
    }

    static func attributedString(from url: URL, typography: Typography) throws -> NSAttributedString {
        guard let format = DocFormat.from(url: url) ?? UTType(filenameExtension: url.pathExtension).flatMap({ DocFormat.from(typeIdentifier: $0.identifier) }) else {
            throw ExportError.unsupported(url.pathExtension)
        }
        if format == .rtfd {
            let s = try NSAttributedString(url: url, options: [.documentType: NSAttributedString.DocumentType.rtfd], documentAttributes: nil)
            return tagStyles(s, typography: typography)
        }
        let data = try Data(contentsOf: url)
        return try attributedString(from: data, format: format, typography: typography, baseURL: url)
    }

    /// Strings from Apple's readers carry fonts but not Tide's style tags; infer them so the panel and exporters agree.
    static func tagStyles(_ s: NSAttributedString, typography: Typography) -> NSAttributedString {
        let m = NSMutableAttributedString(attributedString: s)
        guard m.length > 0 else { return m }
        let str = m.string as NSString
        var loc = 0
        while loc < m.length {
            let pr = str.paragraphRange(for: NSRange(location: loc, length: 0))
            if pr.length > 0 {
                let attrs = m.attributes(at: pr.location, effectiveRange: nil)
                let style = TextStyle.of(attrs, typography)
                m.addAttribute(.tideStyle, value: style.rawValue, range: pr)
                if attrs[.foregroundColor] == nil { m.addAttribute(.foregroundColor, value: NSColor.textColor, range: pr) }
                if let bg = attrs[.backgroundColor] as? NSColor, attrs[.tideHighlight] == nil, let h = Highlight.nearest(to: bg) {
                    m.enumerateAttribute(.backgroundColor, in: pr, options: []) { value, r, _ in
                        if let c = value as? NSColor, Highlight.nearest(to: c) == h {
                            m.addAttribute(.backgroundColor, value: h.color, range: r)
                            m.addAttribute(.tideHighlight, value: h.rawValue, range: r)
                        }
                    }
                }
            }
            loc = NSMaxRange(pr)
            if pr.length == 0 { break }
        }
        return m
    }
}

enum PDFExporter {
    static func printOperation(text: NSAttributedString, printInfo: NSPrintInfo, title: String) -> NSPrintOperation {
        printInfo.leftMargin = 72
        printInfo.rightMargin = 72
        printInfo.topMargin = 72
        printInfo.bottomMargin = 72
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .automatic
        printInfo.isHorizontallyCentered = false
        printInfo.isVerticallyCentered = false
        let width = printInfo.paperSize.width - printInfo.leftMargin - printInfo.rightMargin

        let storage = NSTextStorage(attributedString: text)
        let lm = NSLayoutManager()
        storage.addLayoutManager(lm)
        let container = NSTextContainer(size: NSSize(width: width, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        lm.addTextContainer(container)
        let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 200), textContainer: container)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.textContainerInset = .zero
        tv.drawsBackground = false
        tv.appearance = NSAppearance(named: .aqua)
        AttachmentFactory.installCells(in: storage, availableWidth: width)
        lm.ensureLayout(for: container)
        tv.sizeToFit()
        let op = NSPrintOperation(view: tv, printInfo: printInfo)
        op.jobTitle = title
        return op
    }

    static func write(text: NSAttributedString, to url: URL, title: String) throws {
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.paperSize = Settings.paperSize.size
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url
        let op = printOperation(text: text, printInfo: info, title: title)
        op.showsPrintPanel = false
        op.showsProgressPanel = false
        guard op.run() else { throw ExportError.pdfFailed }
    }

    static func data(text: NSAttributedString, title: String) throws -> Data {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tide-\(UUID().uuidString).pdf")
        try write(text: text, to: url, title: title)
        let d = try Data(contentsOf: url)
        try? FileManager.default.removeItem(at: url)
        return d
    }
}
