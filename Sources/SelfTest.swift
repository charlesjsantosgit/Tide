import AppKit

/// `Tide --selftest`: exercises formatting, lists, attachments and every file format without a window.
enum SelfTest {
    private static var failures = 0
    private static var passes = 0

    private static func check(_ condition: Bool, _ name: String, _ detail: @autoclosure () -> String = "") {
        if condition { passes += 1; print("PASS  \(name)") } else { failures += 1; print("FAIL  \(name)  \(detail())") }
    }

    private static func attr(_ s: NSAttributedString, _ key: NSAttributedString.Key, at i: Int) -> Any? {
        guard i < s.length else { return nil }
        return s.attribute(key, at: i, effectiveRange: nil)
    }

    private static func hasRun(_ s: NSAttributedString, where predicate: ([NSAttributedString.Key: Any]) -> Bool) -> Bool {
        var found = false
        guard s.length > 0 else { return false }
        s.enumerateAttributes(in: NSRange(location: 0, length: s.length), options: []) { a, _, stop in
            if predicate(a) { found = true; stop.pointee = true }
        }
        return found
    }

    private static func shell(_ cmd: String, _ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: cmd)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return -1 }
        p.waitUntilExit()
        return p.terminationStatus
    }

    /// `--eqdebug <dir>`: writes the raw equation PNG and a rendering of the cell, with alpha statistics.
    static func equationDebug(outputDir: String) -> Never {
        let dir = URL(fileURLWithPath: outputDir, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let r = EquationRenderer.shared.renderSync(latex: "E = mc^2", display: false, fontSize: 14) else { print("render failed"); exit(1) }
        try? r.png.write(to: dir.appendingPathComponent("eq-raw.png"))
        if let rep = NSBitmapImageRep(data: r.png) {
            var buckets = [Int](repeating: 0, count: 5)
            for y in 0..<rep.pixelsHigh { for x in 0..<rep.pixelsWide {
                let a = rep.colorAt(x: x, y: y)?.alphaComponent ?? 0
                buckets[min(4, Int(a * 4.999))] += 1 } }
            print("png \(rep.pixelsWide)x\(rep.pixelsHigh) alpha buckets [0-.2,.2-.4,.4-.6,.6-.8,.8-1]: \(buckets) hasAlpha=\(rep.hasAlpha) format=\(rep.bitmapFormat.rawValue)")
        }
        let att = AttachmentFactory.equationAttachment(pngData: r.png, source: "E = mc^2", display: false, displaySize: r.size, baselineDrop: r.baselineDrop)
        guard let cell = att.attachmentCell as? EquationCell else { print("no cell"); exit(1) }
        let frame = NSRect(x: 10, y: 10, width: r.size.width, height: r.size.height)
        let img = NSImage(size: NSSize(width: r.size.width + 20, height: r.size.height + 20), flipped: true) { rect in
            NSColor.white.setFill(); rect.fill()
            cell.draw(withFrame: frame, in: nil)
            return true
        }
        if let png = ImageUtil.pngData(img) { try? png.write(to: dir.appendingPathComponent("eq-cell.png")) }
        print("cell image set: \(cell.image != nil) size=\(cell.displaySize) drop=\(cell.baselineDrop)")
        exit(0)
    }

    /// `--dump <file>`: imports a document the way Open does and prints its paragraphs.
    static func dump(path: String) -> Never {
        let url = URL(fileURLWithPath: path)
        let t = Typography.current
        do {
            let text = try Importers.attributedString(from: url, typography: t)
            let str = text.string as NSString
            for p in DocumentWalker.paragraphs(of: text, typography: t) {
                var flags: [String] = []
                if let k = p.listKind { flags.append(k == .bullet ? "•list L\(p.listLevel)" : "#list L\(p.listLevel)") }
                if p.alignment == .center { flags.append("center") }
                if p.alignment == .right { flags.append("right") }
                var runs: [String] = []
                for (s, attrs) in DocumentWalker.runs(of: text, in: p.contentRange) {
                    if let att = attrs[.attachment] as? NSTextAttachment {
                        if let eq = att.attachmentCell as? EquationCell { runs.append("⟨eq \(eq.source)⟩") }
                        else if let chip = att.attachmentCell as? FileChipCell { runs.append("⟨chip \(chip.name)⟩") }
                        else if let img = att.attachmentCell as? ImageCell { runs.append("⟨image \(Int(img.displaySize.width))×\(Int(img.displaySize.height))⟩") }
                        else { runs.append("⟨attachment⟩") }
                        continue
                    }
                    var deco = ""
                    if let f = attrs[.font] as? NSFont { if f.isBold { deco += "B" }; if f.isItalic { deco += "I" } }
                    if (attrs[.underlineStyle] as? Int ?? 0) != 0 { deco += "U" }
                    if (attrs[.strikethroughStyle] as? Int ?? 0) != 0 { deco += "S" }
                    if let h = attrs[.tideHighlight] as? Int, let hl = Highlight(rawValue: h) { deco += "H(\(hl.name))" }
                    if attrs[.link] != nil { deco += "L" }
                    runs.append(deco.isEmpty ? s : "[\(deco)]\(s)")
                }
                let prefix = p.listKind != nil ? (ListSupport.markerPrefixRange(in: str, paragraph: p.range).map { str.substring(with: $0).replacingOccurrences(of: "\t", with: "") + " " } ?? "") : ""
                print("\(p.style.rawValue.padding(toLength: 10, withPad: " ", startingAt: 0)) \(flags.joined(separator: ",").padding(toLength: 10, withPad: " ", startingAt: 0)) \(prefix)\(runs.joined().prefix(110))")
            }
            exit(0)
        } catch {
            print("error: \(error)")
            exit(1)
        }
    }

    static func run() -> Never {
        print("Tide self-test")
        let editor = EditorController()
        let tv = editor.textView
        let t = editor.typography
        let storage = tv.textStorage!
        let newline = #selector(NSResponder.insertNewline(_:))

        editor.load(NSAttributedString())
        tv.insertText("Hello World", replacementRange: NSRange(location: 0, length: 0))
        tv.setSelectedRange(NSRange(location: 6, length: 5))
        editor.toggleBold()
        check((attr(storage, .font, at: 6) as? NSFont)?.isBold == true, "bold applies to the selection")
        editor.toggleItalic()
        let f = attr(storage, .font, at: 6) as? NSFont
        check(f?.isBold == true && f?.isItalic == true, "italic stacks with bold", "\(String(describing: f))")
        editor.toggleUnderline()
        check((attr(storage, .underlineStyle, at: 6) as? Int ?? 0) != 0, "underline")
        editor.applyHighlight(.sky)
        check((attr(storage, .tideHighlight, at: 6) as? Int) == 1 && attr(storage, .backgroundColor, at: 6) != nil, "highlight sky")
        editor.applyHighlight(.sky)
        check(attr(storage, .tideHighlight, at: 6) == nil, "same highlight again removes it")
        editor.applyHighlight(.mint)
        check((attr(storage, .tideHighlight, at: 6) as? Int) == 2, "highlight mint")
        check(editor.state.highlight == .mint && editor.state.bold, "selection state reflects formatting")

        tv.setSelectedRange(NSRange(location: 0, length: 0))
        editor.applyTextStyle(.title)
        check((attr(storage, .font, at: 0) as? NSFont)?.pointSize == t.size(for: .title) && (attr(storage, .tideStyle, at: 0) as? String) == "title", "title style on paragraph")
        tv.setSelectedRange(NSRange(location: 11, length: 0))
        tv.doCommand(by: newline)
        check(editor.state.style == .body, "Return after a title continues in body")
        tv.insertText("Second paragraph", replacementRange: tv.selectedRange())
        editor.toggleList(.bullet)
        check(storage.string.contains("\t•\tSecond paragraph"), "bulleted list adds a marker", storage.string.debugDescription)
        tv.doCommand(by: newline)
        tv.insertText("Item two", replacementRange: tv.selectedRange())
        check(storage.string.contains("\t•\tItem two"), "Return continues the bullet list", storage.string.debugDescription)
        editor.toggleList(.numbered)
        check(storage.string.contains("\t1.\tItem two"), "switch item to numbered", storage.string.debugDescription)
        tv.doCommand(by: newline)
        tv.insertText("Item three", replacementRange: tv.selectedRange())
        check(storage.string.contains("\t2.\tItem three"), "numbered list renumbers", storage.string.debugDescription)
        tv.doCommand(by: newline)
        tv.doCommand(by: newline)
        check(editor.state.list == nil, "Return on an empty item leaves the list")
        editor.changeIndent(by: 1)
        tv.insertText("Indented body", replacementRange: tv.selectedRange())
        let boldStart = tv.selectedRange().location - 4
        tv.setSelectedRange(NSRange(location: boldStart, length: 4))
        editor.toggleBold()
        check((attr(storage, .font, at: boldStart) as? NSFont)?.isBold == true && (attr(storage, .tideStyle, at: boldStart) as? String) == "body", "bold inside a body paragraph")
        tv.setSelectedRange(NSRange(location: boldStart + 4, length: 0))
        editor.toggleBold()   // typing attributes back to regular
        check((tv.typingAttributes[.font] as? NSFont)?.isBold == false, "bold toggles off for typing")
        let ps = attr(storage, .paragraphStyle, at: tv.selectedRange().location - 1) as? NSParagraphStyle
        check((ps?.headIndent ?? 0) >= 24, "indent moves the paragraph")

        tv.doCommand(by: newline)
        if let png = SampleDocument.sampleImagePNG() {
            let att = AttachmentFactory.imageAttachment(data: png, filename: "tide-sample.png", displaySize: nil, maxWidth: editor.textWidth)!
            editor.insertAttachment(att, actionName: "Insert Image")
        }
        check(hasRun(storage) { ($0[.attachment] as? NSTextAttachment)?.attachmentCell is ImageCell }, "image attachment gets an ImageCell")
        if let cell = storage.string.isEmpty ? nil : (0..<storage.length).compactMap({ (attr(storage, .attachment, at: $0) as? NSTextAttachment)?.attachmentCell as? ImageCell }).first {
            check(cell.displaySize.width <= editor.textWidth + 0.5, "image fits the page width", "\(cell.displaySize) vs \(editor.textWidth)")
        }

        let rendered = EquationRenderer.shared.renderSync(latex: "\\frac{a}{b} + \\sqrt{x}", display: true, fontSize: 16)
        check(rendered != nil && (rendered?.size.width ?? 0) > 10, "LaTeX renders through WebKit MathML", "\(String(describing: rendered?.size))")
        tv.doCommand(by: newline)
        tv.insertText("Energy: ", replacementRange: tv.selectedRange())
        editor.commitEquation(EquationRequest(source: "E = mc^2", display: false, replaceRange: nil))
        let deadline = Date().addingTimeInterval(6)
        while Date() < deadline, !hasRun(storage, where: { (($0[.attachment] as? NSTextAttachment)?.attachmentCell as? EquationCell)?.pngData != nil }) {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
        check(hasRun(storage) { (($0[.attachment] as? NSTextAttachment)?.attachmentCell as? EquationCell)?.source == "E = mc^2" }, "inline equation inserted")
        editor.commitLink(LinkRequest(url: "example.com", text: "Example", range: tv.selectedRange()))
        check(hasRun(storage) { ($0[.link] as? URL)?.absoluteString == "https://example.com" }, "link inserted with https:// added")
        let wav = SampleDocument.sampleWAV()
        let chip = wav.flatMap { AttachmentFactory.chipAttachment(fileURL: $0) }
        if let chip { editor.insertAttachment(chip, actionName: "Insert Audio") }
        check(hasRun(storage) { (($0[.attachment] as? NSTextAttachment)?.attachmentCell as? FileChipCell)?.kind == .audio }, "audio chip inserted",
              "wav=\(String(describing: wav?.path)) chip=\(String(describing: chip)) cell=\(String(describing: chip?.attachmentCell)) cells=\((0..<storage.length).compactMap { (attr(storage, .attachment, at: $0) as? NSTextAttachment)?.attachmentCell }.map { String(describing: type(of: $0)) })")

        // Undo works for a formatting change
        let before = storage.string
        tv.insertText(" tail", replacementRange: NSRange(location: storage.length, length: 0))
        tv.undoManager?.undo()
        check(storage.string == before || tv.undoManager == nil, "undo restores text (or no undo manager without a document)")

        // ---- Formats ----
        let text = editor.currentText
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("tide-selftest-\(getpid())", isDirectory: true)
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

        var docxData = Data()
        do {
            docxData = try Exporters.data(text: text, format: .docx, title: "Self Test", typography: t)
            check(docxData.count > 2000, "docx export produces data", "\(docxData.count) bytes")
        } catch { check(false, "docx export", "\(error)") }
        let docxURL = tmp.appendingPathComponent("selftest.docx")
        try? docxData.write(to: docxURL)
        check(shell("/usr/bin/unzip", ["-tq", docxURL.path]) == 0, "docx is a valid zip (unzip -t)")
        if let zip = try? ZipReader(data: docxData) {
            for part in ["word/document.xml", "word/styles.xml", "word/numbering.xml", "[Content_Types].xml", "word/_rels/document.xml.rels"] {
                if let d = zip.contents(of: part) {
                    let u = tmp.appendingPathComponent((part as NSString).lastPathComponent)
                    try? d.write(to: u)
                    check(shell("/usr/bin/xmllint", ["--noout", u.path]) == 0, "\(part) is well-formed XML")
                } else {
                    check(false, "\(part) present in docx")
                }
            }
            let xml = zip.contents(of: "word/document.xml").map { String(decoding: $0, as: UTF8.self) } ?? ""
            check(xml.contains("<w:b/>"), "docx: bold run")
            check(xml.contains("<w:i/>"), "docx: italic run")
            check(xml.contains("<w:u w:val=\"single\"/>"), "docx: underline run")
            check(xml.contains("w:shd") && xml.contains(Highlight.mint.hex), "docx: highlight as shading")
            check(xml.contains("<w:pStyle w:val=\"Title\"/>"), "docx: title paragraph uses the Title style")
            check(xml.contains("<w:numPr>"), "docx: list numbering")
            check(!xml.contains("<w:t xml:space=\"preserve\">•"), "docx: bullet glyph not duplicated as text")
            check(xml.contains("<w:drawing>") && (zip.entries.keys.contains { $0.hasPrefix("word/media/") }), "docx: embedded picture")
            check(xml.contains("<w:hyperlink"), "docx: hyperlink")
            check(xml.contains("descr=\"tide-equation:"), "docx: equation keeps its LaTeX in alt text")
            check(xml.contains("w:ind w:left="), "docx: indent")
        } else {
            check(false, "docx readable by ZipReader")
        }

        do {
            let back = try DocxReader(typography: t).read(docxData)
            check(back.string.contains("Hello World"), "docx round trip: text")
            check((attr(back, .tideStyle, at: 0) as? String) == "title", "docx round trip: title style")
            check(hasRun(back) { ($0[.font] as? NSFont)?.isBold == true && ($0[.font] as? NSFont)?.isItalic == true }, "docx round trip: bold italic run")
            check(hasRun(back) { ($0[.tideHighlight] as? Int) == 2 }, "docx round trip: mint highlight")
            check(hasRun(back) { ($0[.underlineStyle] as? Int ?? 0) != 0 }, "docx round trip: underline")
            check(back.string.contains("\t•\tSecond paragraph") && back.string.contains("\t1.\tItem two") && back.string.contains("\t2.\tItem three"), "docx round trip: lists with numbering", back.string.debugDescription)
            check(hasRun(back) { ($0[.attachment] as? NSTextAttachment)?.attachmentCell is ImageCell }, "docx round trip: picture")
            check(hasRun(back) { (($0[.attachment] as? NSTextAttachment)?.attachmentCell as? EquationCell)?.source == "E = mc^2" }, "docx round trip: equation source")
            check(hasRun(back) { ($0[.link] as? URL)?.host == "example.com" }, "docx round trip: link")
            check(hasRun(back) { (($0[.attachment] as? NSTextAttachment)?.attachmentCell as? FileChipCell)?.kind == .audio }, "docx round trip: audio chip via file link")
        } catch { check(false, "docx round trip", "\(error)") }

        let apple = try? NSAttributedString(data: docxData, options: [.documentType: NSAttributedString.DocumentType.officeOpenXML], documentAttributes: nil)
        check(apple?.string.contains("Hello World") == true, "Apple's Word importer opens Tide's docx")
        check(apple.map { hasRun($0) { ($0[.font] as? NSFont)?.isBold == true } } == true, "Apple's importer sees the bold run")

        let md = MarkdownExporter.markdown(from: text, typography: t)
        check(md.hasPrefix("# Hello"), "markdown: title heading", md.prefix(40).description)
        check(md.contains("=="), "markdown: highlight ==")
        check(md.contains("- Second paragraph"), "markdown: bullet")
        check(md.contains("1. Item two") && md.contains("2. Item three"), "markdown: numbered")
        check(md.contains("$E = mc^2$"), "markdown: inline equation")
        check(md.contains("[Example](https://example.com)"), "markdown: link", md.split(separator: "\n").filter { $0.contains("Example") || $0.contains("Energy") }.joined(separator: " | ").debugDescription)
        check(md.contains("![tide-sample.png](data:image/png;base64,"), "markdown: image as data URI")

        let mdBack = MarkdownImporter.attributedString(from: "---\ntitle: x\n---\n# Title\n\nSome **bold** and *italic* with ==mark== and $x^2$ and [a link](https://apple.com).\n\n- one\n- two\n\n1. first\n2. second\n\n## Heading\n\n```\ncode block\n```\n", typography: t, baseURL: nil)
        check((attr(mdBack, .tideStyle, at: 0) as? String) == "title" && mdBack.string.hasPrefix("Title"), "markdown import: heading (front matter stripped)", mdBack.string.debugDescription)
        check(hasRun(mdBack) { ($0[.font] as? NSFont)?.isBold == true && ($0[.tideStyle] as? String) == "body" }, "markdown import: bold")
        check(hasRun(mdBack) { ($0[.font] as? NSFont)?.isItalic == true }, "markdown import: italic")
        check(hasRun(mdBack) { ($0[.tideHighlight] as? Int) == Highlight.butter.rawValue }, "markdown import: ==highlight==")
        check(hasRun(mdBack) { (($0[.attachment] as? NSTextAttachment)?.attachmentCell as? EquationCell)?.source == "x^2" }, "markdown import: $equation$")
        check(hasRun(mdBack) { ($0[.link] as? URL)?.host == "apple.com" }, "markdown import: link")
        check(mdBack.string.contains("\t•\tone") && mdBack.string.contains("\t•\ttwo"), "markdown import: bullets", mdBack.string.debugDescription)
        check(mdBack.string.contains("\t1.\tfirst") && mdBack.string.contains("\t2.\tsecond"), "markdown import: numbered", mdBack.string.debugDescription)
        check(hasRun(mdBack) { ($0[.tideStyle] as? String) == "heading" }, "markdown import: ## heading")
        check(hasRun(mdBack) { ($0[.font] as? NSFont)?.familyName == Typography.monoFamily }, "markdown import: code block in Menlo")

        let html = HTMLExporter.html(from: text, title: "Self Test", typography: t)
        check(html.contains("<h1>") && html.contains("<strong>") && html.contains("<mark style=\"background:#") && html.contains("<img src=\"data:image/png;base64,") && html.contains("<ul>") && html.contains("<ol>"), "html export has headings, bold, mark, image, lists")

        if let rtf = try? Exporters.data(text: text, format: .rtf, title: "x", typography: t) { check(rtf.count > 100 && String(decoding: rtf.prefix(5), as: UTF8.self) == "{\\rtf", "rtf export") } else { check(false, "rtf export") }
        let txt = Exporters.plainText(text, typography: t)
        check(txt.contains("Hello World") && txt.contains("• Second paragraph") && txt.contains("1. Item two"), "plain text export keeps list markers", txt.debugDescription)
        if let pdf = try? Exporters.data(text: text, format: .pdf, title: "Self Test", typography: t) {
            check(pdf.count > 1000 && String(decoding: pdf.prefix(4), as: UTF8.self) == "%PDF", "pdf export", "\(pdf.count) bytes")
        } else { check(false, "pdf export") }

        // The sample document (used for screenshots) must build and survive docx.
        let sample = SampleDocument.make(typography: t, renderEquations: false)
        if let d = try? Exporters.data(text: sample, format: .docx, title: "Sample", typography: t), let back = try? DocxReader(typography: t).read(d) {
            check(back.string.contains("The Tide Manual") && back.string.contains("\t1.\tOpen the panel"), "sample document round trips", back.string.prefix(120).description)
        } else { check(false, "sample document exports") }

        // Updater basics
        check(Updater.compare("1.0.1", "1.0.0") > 0 && Updater.compare("1.10", "1.9") > 0 && Updater.compare("2.0", "1.99.99") > 0 && Updater.compare("1.0", "1.0.0") == 0 && Updater.compare("v1.2", "1.2") == 0, "updater: version comparison")
        let feedJSON = Data("""
        {"tag_name":"v9.9.9","name":"Tide 9.9.9","body":"notes here","assets":[{"name":"Tide-9.9.9.dmg","browser_download_url":"https://x/y.dmg"},{"name":"Tide-9.9.9.zip","browser_download_url":"https://github.com/charlesjsantosgit/Tide/releases/download/v9.9.9/Tide-9.9.9.zip","size":123}]}
        """.utf8)
        let parsed = Updater.parse(feed: feedJSON)
        check(parsed?.version == "9.9.9" && parsed?.assetName == "Tide-9.9.9.zip" && parsed?.size == 123 && parsed?.notes == "notes here", "updater: parses a GitHub release feed and picks the .zip asset")
        check(Updater.isNewer(parsed?.version ?? "0", than: Updater.currentVersion), "updater: 9.9.9 is newer than \(Updater.currentVersion)")
        check(Updater.parse(feed: Data("{}".utf8)) == nil, "updater: rejects a feed without a tag")

        // Through NSDocument itself: save in every format, reopen, check the text survived.
        let dc = NSDocumentController.shared
        for format in [DocFormat.docx, .rtfd, .rtf, .txt, .markdown, .html] {
            guard let doc = try? dc.makeUntitledDocument(ofType: DocFormat.docx.identifier) as? TideDocument else { check(false, "make untitled document"); break }
            doc.content = sample
            let url = tmp.appendingPathComponent("roundtrip.\(format.fileExtension)")
            var saved = false, finished = false
            doc.save(to: url, ofType: format.identifier, for: .saveAsOperation) { error in saved = error == nil; finished = true; if let error { print("   save error: \(error)") } }
            let until = Date().addingTimeInterval(10)
            while !finished && Date() < until { RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02)) }
            check(saved && FileManager.default.fileExists(atPath: url.path), "NSDocument saves .\(format.fileExtension)")
            let type = (try? dc.typeForContents(of: url)) ?? "?"
            check(DocFormat.from(typeIdentifier: type) == format, "NSDocumentController recognises .\(format.fileExtension)", type)
            if let back = try? TideDocument(contentsOf: url, ofType: type) {
                check(back.content.string.contains("The Tide Manual"), "NSDocument reopens .\(format.fileExtension)", back.content.string.prefix(60).description)
            } else { check(false, "NSDocument reopens .\(format.fileExtension)") }
            doc.close()
            if format == .docx, let out = ProcessInfo.processInfo.environment["TIDE_SAMPLE_OUT"] {
                try? FileManager.default.removeItem(atPath: out)
                try? FileManager.default.copyItem(at: url, to: URL(fileURLWithPath: out))
            }
        }

        try? FileManager.default.removeItem(at: tmp)
        print("\n\(passes) passed, \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
