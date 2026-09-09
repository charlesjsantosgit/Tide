import AppKit

enum HTMLExporter {
    static func html(from text: NSAttributedString, title: String, typography: Typography) -> String {
        var body = ""
        var openList: ListKind? = nil
        func closeList() {
            if let l = openList { body += l == .bullet ? "</ul>\n" : "</ol>\n" }
            openList = nil
        }
        for p in DocumentWalker.paragraphs(of: text, typography: typography) {
            if p.listKind != openList {
                closeList()
                if let l = p.listKind { body += l == .bullet ? "<ul>\n" : "<ol>\n"; openList = l }
            }
            var inner = ""
            for (s, attrs) in DocumentWalker.runs(of: text, in: p.contentRange) { inner += runHTML(s, attrs) }
            var style = ""
            switch p.alignment {
            case .center: style = " style=\"text-align:center\""
            case .right: style = " style=\"text-align:right\""
            case .justified: style = " style=\"text-align:justify\""
            default: break
            }
            let tag = p.listKind != nil ? "li" : p.style.htmlTag
            if inner.isEmpty && p.listKind == nil { inner = "<br>" }
            body += "<\(tag)\(style)>\(inner)</\(tag)>\n"
        }
        closeList()
        var family = typography.family
        if family == Settings.systemFamily { family = "-apple-system, BlinkMacSystemFont" } else { family = "'\(family)'" }
        let css = """
        body{font-family:\(family),'Helvetica Neue',Helvetica,Arial,sans-serif;font-size:\(Int(typography.bodySize))pt;line-height:\(String(format: "%.2f", typography.lineSpacing * 1.35));max-width:720px;margin:48px auto;padding:0 24px;color:#111;background:#fff}
        h1{font-size:2.2em;margin:0 0 .4em}h2{font-size:1.5em;margin:1em 0 .3em}h3{font-size:1.17em;margin:.9em 0 .2em}p{margin:0 0 .6em}
        img{max-width:100%;height:auto;border-radius:6px}mark{padding:0 2px;border-radius:3px}a{color:#2f7bf6}
        .chip{display:inline-block;padding:2px 10px;border-radius:12px;background:#e8f1ff;color:#1a5fd6;text-decoration:none}
        ul,ol{margin:0 0 .6em;padding-left:1.6em}code{font-family:Menlo,monospace;font-size:.92em}
        """
        return "<!doctype html>\n<html><head><meta charset=\"utf-8\"><meta name=\"generator\" content=\"Tide\"><title>\(XML.escape(title))</title><style>\(css)</style></head><body>\n\(body)</body></html>\n"
    }

    private static func runHTML(_ s: String, _ attrs: [NSAttributedString.Key: Any]) -> String {
        if let att = attrs[.attachment] as? NSTextAttachment { return attachmentHTML(att) }
        var t = XML.escape(s)
            .replacingOccurrences(of: "\u{2028}", with: "<br>")
            .replacingOccurrences(of: "\t", with: "&emsp;")
            .replacingOccurrences(of: "\u{FFFC}", with: "")
        guard !t.isEmpty else { return "" }
        let font = attrs[.font] as? NSFont
        if font?.familyName == Typography.monoFamily { t = "<code>\(t)</code>" }
        if let color = attrs[.foregroundColor] as? NSColor, !color.isDynamic { t = "<span style=\"color:#\(color.hexString)\">\(t)</span>" }
        if (attrs[.strikethroughStyle] as? Int ?? 0) != 0 { t = "<s>\(t)</s>" }
        if (attrs[.underlineStyle] as? Int ?? 0) != 0 { t = "<u>\(t)</u>" }
        if font?.isItalic == true { t = "<em>\(t)</em>" }
        let styleTag = attrs[.tideStyle] as? String ?? TextStyle.body.rawValue
        if font?.isBold == true && styleTag == TextStyle.body.rawValue { t = "<strong>\(t)</strong>" }
        if let idx = attrs[.tideHighlight] as? Int, let h = Highlight(rawValue: idx) {
            t = "<mark style=\"background:#\(h.hex)\">\(t)</mark>"
        } else if let bg = attrs[.backgroundColor] as? NSColor {
            t = "<mark style=\"background:#\(bg.hexString)\">\(t)</mark>"
        }
        if let link = attrs[.link] {
            let u = (link as? URL)?.absoluteString ?? (link as? String) ?? ""
            t = "<a href=\"\(XML.escape(u))\">\(t)</a>"
        }
        return t
    }

    private static func attachmentHTML(_ att: NSTextAttachment) -> String {
        if let chip = att.attachmentCell as? FileChipCell {
            let label = XML.escape((chip.kind == .audio ? "🎵 " : "📎 ") + chip.name)
            if let u = chip.fileURL { return "<a class=\"chip\" href=\"\(XML.escape(u.absoluteString))\">\(label)</a>" }
            return "<span class=\"chip\">\(label)</span>"
        }
        var data: Data? = nil
        var size = NSSize.zero
        var alt = "image"
        if let eq = att.attachmentCell as? EquationCell {
            data = eq.pngData
            size = eq.displaySize
            alt = eq.source
        } else if let cell = att.attachmentCell as? ImageCell {
            data = att.fileWrapper?.regularFileContents ?? cell.image.flatMap(ImageUtil.pngData)
            size = cell.displaySize
            alt = att.fileWrapper?.preferredFilename ?? "image"
        } else {
            data = att.fileWrapper?.regularFileContents ?? att.image.flatMap(ImageUtil.pngData)
            size = att.bounds.size
        }
        guard let raw = data, let (bytes, _, mime) = ImageUtil.normalized(raw) else { return "" }
        let dims = size.width > 0 ? " width=\"\(Int(size.width))\" height=\"\(Int(size.height))\"" : ""
        return "<img src=\"data:\(mime);base64,\(bytes.base64EncodedString())\" alt=\"\(XML.escape(alt))\"\(dims)>"
    }
}
