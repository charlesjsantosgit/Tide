import AppKit

/// Writes Office Open XML (.docx) that Word, Pages and LibreOffice open, keeping the things
/// Apple's built-in writer drops: highlights, images, links, real list numbering, heading styles.
struct DocxWriter {
    let text: NSAttributedString
    let typography: Typography
    let title: String
    let paperSize: PaperSize

    private var media: [(name: String, data: Data, rId: String)] = []
    private var hyperlinks: [(rId: String, target: String)] = []
    private var numInstances: [(numId: Int, abstract: Int)] = []
    private var rIdCounter = 10
    private var docPrId = 1

    init(text: NSAttributedString, typography: Typography, title: String, paperSize: PaperSize) {
        self.text = text
        self.typography = typography
        self.title = title
        self.paperSize = paperSize
    }

    static let wNS = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
    static let rNS = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"

    mutating func makeData() throws -> Data {
        let body = buildBody()
        var zip = ZipWriter()
        zip.add("[Content_Types].xml", Data(contentTypes.utf8))
        zip.add("_rels/.rels", Data(rootRels.utf8))
        zip.add("word/document.xml", Data(documentXML(body).utf8))
        zip.add("word/_rels/document.xml.rels", Data(documentRels.utf8))
        zip.add("word/styles.xml", Data(stylesXML.utf8))
        zip.add("word/numbering.xml", Data(numberingXML.utf8))
        zip.add("word/settings.xml", Data(settingsXML.utf8))
        for m in media { zip.add("word/media/\(m.name)", m.data) }
        zip.add("docProps/core.xml", Data(coreXML.utf8))
        zip.add("docProps/app.xml", Data(appXML.utf8))
        return zip.finish()
    }

    private mutating func nextRId() -> String { rIdCounter += 1; return "rId\(rIdCounter)" }

    // MARK: body

    private mutating func buildBody() -> String {
        var out = ""
        var listState: (kind: ListKind, numId: Int)? = nil
        let paragraphs = DocumentWalker.paragraphs(of: text, typography: typography)
        for p in paragraphs {
            var pPr = ""
            if let sid = p.style.docxStyleId { pPr += "<w:pStyle w:val=\"\(sid)\"/>" }
            if let kind = p.listKind {
                if listState?.kind != kind {
                    numInstances.append((numId: numInstances.count + 1, abstract: kind.abstractNumId))
                    listState = (kind, numInstances.count)
                }
                pPr += "<w:numPr><w:ilvl w:val=\"\(min(p.listLevel, 8))\"/><w:numId w:val=\"\(listState!.numId)\"/></w:numPr>"
            } else {
                listState = nil
                let left = Int((p.paragraphStyle.headIndent * 20).rounded())
                let first = Int(((p.paragraphStyle.firstLineHeadIndent - p.paragraphStyle.headIndent) * 20).rounded())
                if left > 0 || first != 0 {
                    pPr += "<w:ind w:left=\"\(left)\"" + (first != 0 ? " w:firstLine=\"\(first)\"" : "") + "/>"
                }
            }
            let before = Int((p.paragraphStyle.paragraphSpacingBefore * 20).rounded())
            let after = Int((p.paragraphStyle.paragraphSpacing * 20).rounded())
            let mult = p.paragraphStyle.lineHeightMultiple > 0 ? p.paragraphStyle.lineHeightMultiple : 1
            pPr += "<w:spacing w:before=\"\(before)\" w:after=\"\(after)\" w:line=\"\(Int((240 * mult).rounded()))\" w:lineRule=\"auto\"/>"
            switch p.alignment {
            case .center: pPr += "<w:jc w:val=\"center\"/>"
            case .right: pPr += "<w:jc w:val=\"right\"/>"
            case .justified: pPr += "<w:jc w:val=\"both\"/>"
            default: break
            }
            var runs = ""
            for (s, attrs) in DocumentWalker.runs(of: text, in: p.contentRange) {
                runs += runXML(s, attrs: attrs, paragraph: p)
            }
            out += "<w:p><w:pPr>\(pPr)</w:pPr>\(runs)</w:p>"
        }
        return out
    }

    private mutating func runXML(_ s: String, attrs: [NSAttributedString.Key: Any], paragraph: ParagraphInfo) -> String {
        if let att = attrs[.attachment] as? NSTextAttachment {
            return attachmentXML(att, attrs: attrs)
        }
        let rPr = runProperties(attrs, paragraph: paragraph)
        var out = ""
        var buffer = ""
        func flush() {
            if !buffer.isEmpty {
                out += "<w:r>\(rPr)<w:t xml:space=\"preserve\">\(XML.escape(buffer))</w:t></w:r>"
                buffer = ""
            }
        }
        for ch in s.unicodeScalars {
            switch ch {
            case "\t": flush(); out += "<w:r>\(rPr)<w:tab/></w:r>"
            case "\u{2028}", "\u{0B}": flush(); out += "<w:r>\(rPr)<w:br/></w:r>"
            case "\u{0C}": flush(); out += "<w:r>\(rPr)<w:br w:type=\"page\"/></w:r>"
            case "\n", "\r": flush()
            case "\u{FFFC}": flush()
            default: buffer.unicodeScalars.append(ch)
            }
        }
        flush()
        if let link = linkTarget(attrs[.link]) {
            let rId = nextRId()
            hyperlinks.append((rId, link))
            return "<w:hyperlink r:id=\"\(rId)\">\(out)</w:hyperlink>"
        }
        return out
    }

    private func linkTarget(_ value: Any?) -> String? {
        if let url = value as? URL { return url.absoluteString }
        if let s = value as? String, !s.isEmpty { return s }
        return nil
    }

    private func runProperties(_ attrs: [NSAttributedString.Key: Any], paragraph: ParagraphInfo, isLink: Bool = false) -> String {
        var r = ""
        let font = attrs[.font] as? NSFont ?? typography.font(for: paragraph.style)
        var family = font.familyName ?? typography.family
        if family.hasPrefix(".") || family == Settings.systemFamily { family = "Helvetica Neue" }
        let fam = XML.escape(family)
        r += "<w:rFonts w:ascii=\"\(fam)\" w:hAnsi=\"\(fam)\" w:cs=\"\(fam)\" w:eastAsia=\"\(fam)\"/>"
        if font.isBold { r += "<w:b/><w:bCs/>" }
        if font.isItalic { r += "<w:i/><w:iCs/>" }
        if let u = attrs[.underlineStyle] as? Int, u != 0 { r += "<w:u w:val=\"single\"/>" }
        if let st = attrs[.strikethroughStyle] as? Int, st != 0 { r += "<w:strike/>" }
        if let color = attrs[.foregroundColor] as? NSColor, !color.isDynamic, let srgb = color.usingColorSpace(.sRGB), srgb.alphaComponent > 0.5 {
            // skip near-black (it's the default anyway)
            if srgb.redComponent + srgb.greenComponent + srgb.blueComponent > 0.15 { r += "<w:color w:val=\"\(srgb.hexString)\"/>" }
        }
        if let idx = attrs[.tideHighlight] as? Int, let h = Highlight(rawValue: idx) {
            r += "<w:shd w:val=\"clear\" w:color=\"auto\" w:fill=\"\(h.hex)\"/>"
        } else if let bg = attrs[.backgroundColor] as? NSColor, let srgb = bg.usingColorSpace(.sRGB), srgb.alphaComponent > 0.1 {
            r += "<w:shd w:val=\"clear\" w:color=\"auto\" w:fill=\"\(srgb.hexString)\"/>"
        }
        if let sup = attrs[.superscript] as? Int, sup != 0 { r += "<w:vertAlign w:val=\"\(sup > 0 ? "superscript" : "subscript")\"/>" }
        let half = Int((font.pointSize * 2).rounded())
        r += "<w:sz w:val=\"\(half)\"/><w:szCs w:val=\"\(half)\"/>"
        return "<w:rPr>\(r)</w:rPr>"
    }

    private mutating func attachmentXML(_ att: NSTextAttachment, attrs: [NSAttributedString.Key: Any]) -> String {
        if let chip = att.attachmentCell as? FileChipCell {
            let label = (chip.kind == .audio ? "🎵 " : "📎 ") + chip.name
            let rPr = "<w:rPr><w:rStyle w:val=\"Hyperlink\"/></w:rPr>"
            let run = "<w:r>\(rPr)<w:t xml:space=\"preserve\">\(XML.escape(label))</w:t></w:r>"
            if let url = chip.fileURL {
                let rId = nextRId()
                hyperlinks.append((rId, url.absoluteString))
                return "<w:hyperlink r:id=\"\(rId)\">\(run)</w:hyperlink>"
            }
            return run
        }
        var descr: String? = nil
        var size = NSSize(width: 200, height: 100)
        var imageData: Data? = nil
        if let eq = att.attachmentCell as? EquationCell {
            guard let png = eq.pngData else {
                let src = eq.display ? "$$\(eq.source)$$" : "$\(eq.source)$"
                return "<w:r><w:rPr><w:rFonts w:ascii=\"Menlo\" w:hAnsi=\"Menlo\"/></w:rPr><w:t xml:space=\"preserve\">\(XML.escape(src))</w:t></w:r>"
            }
            descr = eq.docxDescription
            size = eq.displaySize
            imageData = png
        } else if let cell = att.attachmentCell as? ImageCell {
            size = cell.displaySize
            imageData = att.fileWrapper?.regularFileContents ?? cell.image.flatMap(ImageUtil.pngData)
        } else {
            imageData = att.fileWrapper?.regularFileContents ?? att.image.flatMap(ImageUtil.pngData)
            if let d = imageData, let px = ImageUtil.pixelSize(d) {
                let w = min(px.width / 2, 468)
                size = NSSize(width: w, height: w * px.height / max(px.width, 1))
            }
            if att.bounds.width > 0 { size = att.bounds.size }
        }
        guard let raw = imageData, let (bytes, ext, _) = ImageUtil.normalized(raw) else { return "" }
        let name = "image\(media.count + 1).\(ext)"
        let rId = nextRId()
        media.append((name, bytes, rId))
        let cx = Int((size.width * 12700).rounded()), cy = Int((size.height * 12700).rounded())
        let id = docPrId
        docPrId += 1
        let descrAttr = descr.map { " descr=\"\(XML.escape($0))\"" } ?? ""
        return """
        <w:r><w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0"><wp:extent cx="\(cx)" cy="\(cy)"/><wp:docPr id="\(id)" name="Picture \(id)"\(descrAttr)/><a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture"><pic:pic><pic:nvPicPr><pic:cNvPr id="0" name="\(name)"/><pic:cNvPicPr/></pic:nvPicPr><pic:blipFill><a:blip r:embed="\(rId)"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill><pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="\(cx)" cy="\(cy)"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr></pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r>
        """
    }

    // MARK: parts

    private func documentXML(_ body: String) -> String {
        let (w, h) = paperSize.twips
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="\(Self.wNS)" xmlns:r="\(Self.rNS)" xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture"><w:body>\(body)<w:sectPr><w:pgSz w:w="\(w)" w:h="\(h)"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="720" w:footer="720" w:gutter="0"/></w:sectPr></w:body></w:document>
        """
    }

    private var contentTypes: String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Default Extension="png" ContentType="image/png"/><Default Extension="jpeg" ContentType="image/jpeg"/><Default Extension="jpg" ContentType="image/jpeg"/><Default Extension="gif" ContentType="image/gif"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/><Override PartName="/word/numbering.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml"/><Override PartName="/word/settings.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/><Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/><Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/></Types>
        """
    }

    private var rootRels: String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/><Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/></Relationships>
        """
    }

    private var documentRels: String {
        var rels = """
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering" Target="numbering.xml"/><Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings" Target="settings.xml"/>
        """
        for m in media {
            rels += "<Relationship Id=\"\(m.rId)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/image\" Target=\"media/\(m.name)\"/>"
        }
        for h in hyperlinks {
            rels += "<Relationship Id=\"\(h.rId)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink\" Target=\"\(XML.escape(h.target))\" TargetMode=\"External\"/>"
        }
        return "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">\(rels)</Relationships>"
    }

    private var stylesXML: String {
        var family = typography.family
        if family == Settings.systemFamily { family = "Helvetica Neue" }
        let fam = XML.escape(family)
        let body = Int(typography.bodySize * 2)
        let title = Int(typography.size(for: .title) * 2)
        let h1 = Int(typography.size(for: .heading) * 2)
        let h2 = Int(typography.size(for: .subheading) * 2)
        let line = Int((240 * max(1, typography.lineSpacing)).rounded())
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:styles xmlns:w="\(Self.wNS)"><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="\(fam)" w:hAnsi="\(fam)" w:cs="\(fam)" w:eastAsia="\(fam)"/><w:sz w:val="\(body)"/><w:szCs w:val="\(body)"/><w:lang w:val="en-US"/></w:rPr></w:rPrDefault><w:pPrDefault><w:pPr><w:spacing w:after="120" w:line="\(line)" w:lineRule="auto"/></w:pPr></w:pPrDefault></w:docDefaults><w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:qFormat/></w:style><w:style w:type="paragraph" w:styleId="Title"><w:name w:val="Title"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/><w:pPr><w:spacing w:before="0" w:after="200"/></w:pPr><w:rPr><w:b/><w:bCs/><w:sz w:val="\(title)"/><w:szCs w:val="\(title)"/></w:rPr></w:style><w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/><w:pPr><w:keepNext/><w:spacing w:before="280" w:after="80"/><w:outlineLvl w:val="0"/></w:pPr><w:rPr><w:b/><w:bCs/><w:sz w:val="\(h1)"/><w:szCs w:val="\(h1)"/></w:rPr></w:style><w:style w:type="paragraph" w:styleId="Heading2"><w:name w:val="heading 2"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/><w:pPr><w:keepNext/><w:spacing w:before="200" w:after="40"/><w:outlineLvl w:val="1"/></w:pPr><w:rPr><w:b/><w:bCs/><w:sz w:val="\(h2)"/><w:szCs w:val="\(h2)"/></w:rPr></w:style><w:style w:type="paragraph" w:styleId="ListParagraph"><w:name w:val="List Paragraph"/><w:basedOn w:val="Normal"/><w:qFormat/><w:pPr><w:ind w:left="720"/><w:contextualSpacing/></w:pPr></w:style><w:style w:type="character" w:styleId="Hyperlink"><w:name w:val="Hyperlink"/><w:rPr><w:color w:val="2F7BF6"/><w:u w:val="single"/></w:rPr></w:style></w:styles>
        """
    }

    private var numberingXML: String {
        var nums = ""
        for n in numInstances {
            nums += "<w:num w:numId=\"\(n.numId)\"><w:abstractNumId w:val=\"\(n.abstract)\"/><w:lvlOverride w:ilvl=\"0\"><w:startOverride w:val=\"1\"/></w:lvlOverride></w:num>"
        }
        func bulletLevel(_ i: Int, _ text: String) -> String {
            "<w:lvl w:ilvl=\"\(i)\"><w:start w:val=\"1\"/><w:numFmt w:val=\"bullet\"/><w:lvlText w:val=\"\(text)\"/><w:lvlJc w:val=\"left\"/><w:pPr><w:ind w:left=\"\(720 + 360 * i)\" w:hanging=\"360\"/></w:pPr></w:lvl>"
        }
        func numberLevel(_ i: Int, _ fmt: String) -> String {
            "<w:lvl w:ilvl=\"\(i)\"><w:start w:val=\"1\"/><w:numFmt w:val=\"\(fmt)\"/><w:lvlText w:val=\"%\(i + 1).\"/><w:lvlJc w:val=\"left\"/><w:pPr><w:ind w:left=\"\(720 + 360 * i)\" w:hanging=\"360\"/></w:pPr></w:lvl>"
        }
        let bullets = bulletLevel(0, "•") + bulletLevel(1, "◦") + bulletLevel(2, "▪")
        let numbers = numberLevel(0, "decimal") + numberLevel(1, "lowerLetter") + numberLevel(2, "lowerRoman")
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:numbering xmlns:w="\(Self.wNS)"><w:abstractNum w:abstractNumId="0"><w:multiLevelType w:val="hybridMultilevel"/>\(bullets)</w:abstractNum><w:abstractNum w:abstractNumId="1"><w:multiLevelType w:val="hybridMultilevel"/>\(numbers)</w:abstractNum>\(nums)</w:numbering>
        """
    }

    private var settingsXML: String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:settings xmlns:w="\(Self.wNS)"><w:defaultTabStop w:val="720"/><w:characterSpacingControl w:val="doNotCompress"/><w:compat><w:compatSetting w:name="compatibilityMode" w:uri="http://schemas.microsoft.com/office/word" w:val="15"/></w:compat></w:settings>
        """
    }

    private var coreXML: String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        let now = f.string(from: Date())
        let who = XML.escape(NSFullUserName())
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:dcmitype="http://purl.org/dc/dcmitype/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"><dc:title>\(XML.escape(title))</dc:title><dc:creator>\(who)</dc:creator><cp:lastModifiedBy>\(who)</cp:lastModifiedBy><dcterms:created xsi:type="dcterms:W3CDTF">\(now)</dcterms:created><dcterms:modified xsi:type="dcterms:W3CDTF">\(now)</dcterms:modified></cp:coreProperties>
        """
    }

    private var appXML: String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes"><Application>Tide</Application></Properties>
        """
    }
}
