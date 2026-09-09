import AppKit
import UniformTypeIdentifiers

enum DocxError: Error, LocalizedError {
    case notAZip, missingDocument, badXML
    var errorDescription: String? {
        switch self {
        case .notAZip: return "This file is not a Word document."
        case .missingDocument: return "The document is missing its main part."
        case .badXML: return "The document's XML could not be read."
        }
    }
}

/// Reads .docx into an attributed string using Tide's conventions (heading tags, list markers,
/// highlight tags, chips, equation sources). Tolerant of Word-authored files: unknown elements are skipped.
final class DocxReader {
    private let typography: Typography
    private var zip: ZipReader!
    private var rels: [String: (target: String, external: Bool)] = [:]
    private var numbering: [String: ListKind] = [:]     // numId -> kind
    private var headingStyles: [String: TextStyle] = [:] // styleId -> style
    private var styleNumbering: [String: (numId: String, level: Int)] = [:] // styles that carry list numbering (Word's "List Bullet" etc.)
    private var result = NSMutableAttributedString()
    private var listCounters: [String: Int] = [:]
    private var previousNumId: String? = nil
    private var firstParagraph = true
    private var lastParagraphAttributes: [NSAttributedString.Key: Any] = [:]

    private struct RunProps {
        var bold = false, italic = false, underline = false, strike = false
        var size: CGFloat? = nil
        var family: String? = nil
        var color: NSColor? = nil
        var highlight: Highlight? = nil
        var background: NSColor? = nil
        var superscript = 0
        var link: URL? = nil
        var code = false
    }

    private struct ParaProps {
        var style: TextStyle = .body
        var alignment: NSTextAlignment = .natural
        var numId: String? = nil
        var level = 0
        var leftIndent: CGFloat = 0
        var firstLine: CGFloat = 0
    }

    init(typography: Typography) { self.typography = typography }

    func read(_ data: Data) throws -> NSAttributedString {
        do { zip = try ZipReader(data: data) } catch { throw DocxError.notAZip }
        guard let docData = zip.contents(of: "word/document.xml") else { throw DocxError.missingDocument }
        rels = Self.parseRels(zip.contents(of: "word/_rels/document.xml.rels"))
        numbering = Self.parseNumbering(zip.contents(of: "word/numbering.xml"))
        let styles = zip.contents(of: "word/styles.xml")
        headingStyles = Self.parseStyles(styles)
        styleNumbering = Self.parseStyleNumbering(styles)
        let doc: XMLDocument
        do { doc = try XMLDocument(data: docData, options: [.nodePreserveWhitespace, .nodeLoadExternalEntitiesNever]) } catch { throw DocxError.badXML }
        guard let root = doc.rootElement(), let body = Self.child(root, "body") else { throw DocxError.badXML }
        walkBlock(body)
        return result
    }

    // MARK: helpers

    private static func child(_ e: XMLElement, _ local: String) -> XMLElement? {
        for c in e.children ?? [] { if let el = c as? XMLElement, el.localName == local { return el } }
        return nil
    }
    private static func children(_ e: XMLElement, _ local: String) -> [XMLElement] {
        (e.children ?? []).compactMap { c in
            guard let el = c as? XMLElement, el.localName == local else { return nil }
            return el
        }
    }
    private static func descendant(_ e: XMLElement, _ local: String) -> XMLElement? {
        for c in e.children ?? [] {
            guard let el = c as? XMLElement else { continue }
            if el.localName == local { return el }
            if let d = descendant(el, local) { return d }
        }
        return nil
    }
    private static func attr(_ e: XMLElement, _ local: String) -> String? {
        for a in e.attributes ?? [] where a.localName == local { return a.stringValue }
        return nil
    }
    private static func flag(_ e: XMLElement) -> Bool {
        guard let v = attr(e, "val") else { return true }
        return !(v == "0" || v == "false" || v == "off")
    }

    private static func parseRels(_ data: Data?) -> [String: (String, Bool)] {
        var out: [String: (String, Bool)] = [:]
        guard let data, let doc = try? XMLDocument(data: data, options: [.nodeLoadExternalEntitiesNever]), let root = doc.rootElement() else { return out }
        for r in children(root, "Relationship") {
            guard let id = attr(r, "Id"), let target = attr(r, "Target") else { continue }
            out[id] = (target, attr(r, "TargetMode") == "External")
        }
        return out
    }

    private static func parseNumbering(_ data: Data?) -> [String: ListKind] {
        var out: [String: ListKind] = [:]
        guard let data, let doc = try? XMLDocument(data: data, options: [.nodeLoadExternalEntitiesNever]), let root = doc.rootElement() else { return out }
        var abstractKinds: [String: ListKind] = [:]
        for a in children(root, "abstractNum") {
            guard let id = attr(a, "abstractNumId") else { continue }
            var kind: ListKind = .bullet
            if let lvl = children(a, "lvl").first, let fmt = child(lvl, "numFmt"), let v = attr(fmt, "val") {
                kind = (v == "bullet" || v == "none") ? .bullet : .numbered
            }
            abstractKinds[id] = kind
        }
        for n in children(root, "num") {
            guard let id = attr(n, "numId"), let abs = child(n, "abstractNumId"), let aid = attr(abs, "val") else { continue }
            out[id] = abstractKinds[aid] ?? .bullet
        }
        return out
    }

    private static func parseStyles(_ data: Data?) -> [String: TextStyle] {
        var out: [String: TextStyle] = ["Title": .title, "Heading1": .heading, "Heading2": .subheading, "Heading3": .subheading]
        guard let data, let doc = try? XMLDocument(data: data, options: [.nodeLoadExternalEntitiesNever]), let root = doc.rootElement() else { return out }
        for s in children(root, "style") {
            guard attr(s, "type") == "paragraph", let id = attr(s, "styleId") else { continue }
            let name = child(s, "name").flatMap { attr($0, "val") }?.lowercased() ?? ""
            if name == "title" { out[id] = .title; continue }
            if name.hasPrefix("heading") || id.lowercased().hasPrefix("heading") {
                let digits = (name.isEmpty ? id : name).filter { $0.isNumber }
                let level = Int(digits) ?? 1
                out[id] = level <= 1 ? .heading : .subheading
                continue
            }
            if let pPr = child(s, "pPr"), let ol = child(pPr, "outlineLvl"), let v = attr(ol, "val"), let level = Int(v) {
                out[id] = level == 0 ? .heading : .subheading
            }
        }
        return out
    }

    private static func parseStyleNumbering(_ data: Data?) -> [String: (numId: String, level: Int)] {
        var out: [String: (String, Int)] = [:]
        guard let data, let doc = try? XMLDocument(data: data, options: [.nodeLoadExternalEntitiesNever]), let root = doc.rootElement() else { return out }
        var basedOn: [String: String] = [:]
        for s in children(root, "style") {
            guard attr(s, "type") == "paragraph", let id = attr(s, "styleId") else { continue }
            if let b = child(s, "basedOn"), let v = attr(b, "val") { basedOn[id] = v }
            guard let pPr = child(s, "pPr"), let numPr = child(pPr, "numPr"), let n = child(numPr, "numId"), let v = attr(n, "val"), v != "0" else { continue }
            let level = child(numPr, "ilvl").flatMap { attr($0, "val") }.flatMap(Int.init) ?? 0
            out[id] = (v, min(max(level, 0), 2))
        }
        // inherit through basedOn chains (List Bullet 2 → List Bullet …)
        for (id, _) in basedOn where out[id] == nil {
            var cur: String? = id
            var hops = 0
            while let c = cur, hops < 8 {
                if let n = out[c] { out[id] = n; break }
                cur = basedOn[c]
                hops += 1
            }
        }
        return out
    }

    // MARK: block walk

    private func walkBlock(_ el: XMLElement) {
        for c in el.children ?? [] {
            guard let e = c as? XMLElement else { continue }
            switch e.localName {
            case "p": paragraph(e)
            case "tbl":
                for tr in Self.children(e, "tr") { for tc in Self.children(tr, "tc") { walkBlock(tc) } }
            case "sdt":
                if let content = Self.child(e, "sdtContent") { walkBlock(content) }
            case "AlternateContent":
                if let fb = Self.child(e, "Fallback") { walkBlock(fb) }
            case "txbxContent", "pict", "textbox", "sdtContent", "customXml", "smartTag":
                walkBlock(e)
            default:
                break
            }
        }
    }

    private func paragraph(_ p: XMLElement) {
        var props = ParaProps()
        if let pPr = Self.child(p, "pPr") { parsePPr(pPr, &props) }
        // start a new paragraph
        if !firstParagraph {
            result.append(NSAttributedString(string: "\n", attributes: lastParagraphAttributes))
        }
        firstParagraph = false
        let start = result.length

        // list marker
        var listKind: ListKind? = nil
        if let numId = props.numId, let kind = numbering[numId] ?? Optional(ListKind.bullet) {
            listKind = kind
            let key = "\(numId)/\(props.level)"
            if previousNumId != numId { listCounters = [:] }
            let n = (listCounters[key] ?? 0) + 1
            listCounters[key] = n
            let prefix = ListSupport.prefix(kind: kind, level: props.level, itemNumber: n)
            result.append(NSAttributedString(string: prefix, attributes: baseAttributes(props: props, run: RunProps())))
        }
        previousNumId = props.numId

        walkInline(p, props: props, run: RunProps())

        // paragraph style over the whole paragraph
        let ps = typography.paragraphStyle(for: props.style)
        ps.alignment = props.alignment
        if let kind = listKind {
            ListSupport.configure(ps, kind: kind, level: props.level)
        } else if props.leftIndent > 0 || props.firstLine != 0 {
            ps.headIndent = props.leftIndent
            ps.firstLineHeadIndent = max(0, props.leftIndent + props.firstLine)
        }
        let range = NSRange(location: start, length: result.length - start)
        var attrsForNewline = baseAttributes(props: props, run: RunProps())
        attrsForNewline[.paragraphStyle] = ps
        if range.length > 0 {
            result.addAttribute(.paragraphStyle, value: ps, range: range)
            result.addAttribute(.tideStyle, value: props.style.rawValue, range: range)
        }
        lastParagraphAttributes = attrsForNewline
    }

    private func parsePPr(_ pPr: XMLElement, _ props: inout ParaProps) {
        for c in pPr.children ?? [] {
            guard let e = c as? XMLElement else { continue }
            switch e.localName {
            case "pStyle":
                if let v = Self.attr(e, "val") {
                    if let s = headingStyles[v] { props.style = s }
                    if props.numId == nil, let n = styleNumbering[v] { props.numId = n.numId; props.level = n.level }
                }
            case "jc":
                switch Self.attr(e, "val") ?? "" {
                case "center": props.alignment = .center
                case "right", "end": props.alignment = .right
                case "both", "distribute": props.alignment = .justified
                default: props.alignment = .natural
                }
            case "numPr":
                if let n = Self.child(e, "numId"), let v = Self.attr(n, "val"), v != "0" { props.numId = v }
                if let l = Self.child(e, "ilvl"), let v = Self.attr(l, "val"), let lv = Int(v) { props.level = min(max(lv, 0), 2) }
            case "ind":
                if let l = Self.attr(e, "left") ?? Self.attr(e, "start"), let v = Double(l) { props.leftIndent = CGFloat(v) / 20 }
                if let f = Self.attr(e, "firstLine"), let v = Double(f) { props.firstLine = CGFloat(v) / 20 }
                if let h = Self.attr(e, "hanging"), let v = Double(h) { props.firstLine = -CGFloat(v) / 20 }
            case "outlineLvl":
                if props.style == .body, let v = Self.attr(e, "val"), let lv = Int(v) { props.style = lv == 0 ? .heading : .subheading }
            default: break
            }
        }
    }

    // MARK: inline walk

    private func walkInline(_ el: XMLElement, props: ParaProps, run inherited: RunProps) {
        for c in el.children ?? [] {
            guard let e = c as? XMLElement else { continue }
            switch e.localName {
            case "r": run(e, props: props, inherited: inherited)
            case "hyperlink":
                var r = inherited
                if let id = Self.attr(e, "id"), let rel = rels[id], let url = URL(string: rel.target) { r.link = url }
                walkInline(e, props: props, run: r)
            case "smartTag", "ins", "sdtContent", "fldSimple", "customXml", "moveTo", "dir", "bdo":
                walkInline(e, props: props, run: inherited)
            case "sdt":
                if let content = Self.child(e, "sdtContent") { walkInline(content, props: props, run: inherited) }
            case "AlternateContent":
                if let fb = Self.child(e, "Fallback") { walkInline(fb, props: props, run: inherited) }
            default: break
            }
        }
    }

    private func run(_ r: XMLElement, props: ParaProps, inherited: RunProps) {
        var rp = inherited
        if let rPr = Self.child(r, "rPr") { parseRPr(rPr, &rp) }
        for c in r.children ?? [] {
            guard let e = c as? XMLElement else { continue }
            switch e.localName {
            case "t":
                let s = (e.stringValue ?? "").replacingOccurrences(of: "\r\n", with: " ").replacingOccurrences(of: "\n", with: " ")
                append(s, props: props, run: rp)
            case "tab": append("\t", props: props, run: rp)
            case "br": append(Self.attr(e, "type") == "page" ? "\u{0C}" : "\u{2028}", props: props, run: rp)
            case "cr": append("\u{2028}", props: props, run: rp)
            case "noBreakHyphen": append("\u{2011}", props: props, run: rp)
            case "softHyphen": append("\u{00AD}", props: props, run: rp)
            case "sym":
                if let ch = Self.attr(e, "char"), let v = UInt32(ch, radix: 16), let scalar = UnicodeScalar(v) { append(String(Character(scalar)), props: props, run: rp) }
            case "drawing": drawing(e, props: props, run: rp)
            case "pict", "object": vmlImage(e, props: props, run: rp)
            case "AlternateContent":
                if let fb = Self.child(e, "Fallback") { for cc in fb.children ?? [] { if let el = cc as? XMLElement { if el.localName == "r" { run(el, props: props, inherited: rp) } else if el.localName == "pict" { vmlImage(el, props: props, run: rp) } } } }
            default: break
            }
        }
    }

    private func parseRPr(_ rPr: XMLElement, _ p: inout RunProps) {
        for c in rPr.children ?? [] {
            guard let e = c as? XMLElement else { continue }
            switch e.localName {
            case "b": p.bold = Self.flag(e)
            case "i": p.italic = Self.flag(e)
            case "u": p.underline = (Self.attr(e, "val") ?? "single") != "none"
            case "strike", "dstrike": p.strike = Self.flag(e)
            case "sz": if let v = Self.attr(e, "val"), let d = Double(v) { p.size = CGFloat(d) / 2 }
            case "rFonts": p.family = Self.attr(e, "ascii") ?? Self.attr(e, "hAnsi")
            case "color":
                if let v = Self.attr(e, "val"), v.lowercased() != "auto", let c = NSColor(hex: v) { p.color = c }
            case "highlight":
                p.highlight = Self.highlight(named: Self.attr(e, "val") ?? "")
            case "shd":
                if let fill = Self.attr(e, "fill"), fill.lowercased() != "auto", let c = NSColor(hex: fill) {
                    if let h = Highlight.nearest(to: c) { p.highlight = h } else if c.brightnessComponent < 0.98 { p.background = c }
                }
            case "vertAlign":
                switch Self.attr(e, "val") ?? "" {
                case "superscript": p.superscript = 1
                case "subscript": p.superscript = -1
                default: p.superscript = 0
                }
            case "rStyle":
                if let v = Self.attr(e, "val")?.lowercased(), v.contains("code") || v.contains("verbatim") { p.code = true }
            default: break
            }
        }
    }

    private static func highlight(named name: String) -> Highlight? {
        switch name.lowercased() {
        case "yellow", "darkyellow": return .butter
        case "cyan", "blue", "darkblue", "darkcyan": return .sky
        case "green", "darkgreen": return .mint
        case "magenta", "red", "darkmagenta", "darkred": return .blush
        case "lightgray", "darkgray", "black": return .lilac
        default: return nil
        }
    }

    private func baseAttributes(props: ParaProps, run: RunProps) -> [NSAttributedString.Key: Any] {
        var attrs: [NSAttributedString.Key: Any] = [:]
        let style = props.style
        var family = run.family ?? typography.family
        if run.code { family = Typography.monoFamily }
        if NSFontManager.shared.availableFontFamilies.contains(family) == false && family != Settings.systemFamily { family = typography.family }
        let size = run.size ?? typography.size(for: style)
        let bold = run.bold || style.isBold
        attrs[.font] = typography.font(family: family, size: size, bold: bold, italic: run.italic)
        attrs[.foregroundColor] = run.color ?? NSColor.textColor
        attrs[.tideStyle] = style.rawValue
        if run.underline { attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        if run.strike { attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        if let h = run.highlight { attrs[.backgroundColor] = h.color; attrs[.tideHighlight] = h.rawValue }
        else if let bg = run.background { attrs[.backgroundColor] = bg }
        if run.superscript != 0 { attrs[.superscript] = run.superscript }
        if let link = run.link { attrs[.link] = link }
        return attrs
    }

    private func append(_ s: String, props: ParaProps, run: RunProps) {
        guard !s.isEmpty else { return }
        // Chips come back from our own files as file:// links with an emoji prefix.
        if let link = run.link, link.isFileURL, (s.hasPrefix("🎵 ") || s.hasPrefix("📎 ")),
           FileManager.default.fileExists(atPath: link.path),
           let chip = AttachmentFactory.chipAttachment(fileURL: link) {
            var attrs = baseAttributes(props: props, run: RunProps())
            attrs[.attachment] = chip
            result.append(NSAttributedString(string: "\u{FFFC}", attributes: attrs))
            return
        }
        result.append(NSAttributedString(string: s, attributes: baseAttributes(props: props, run: run)))
    }

    private func drawing(_ d: XMLElement, props: ParaProps, run: RunProps) {
        guard let blip = Self.descendant(d, "blip"), let rid = Self.attr(blip, "embed") ?? Self.attr(blip, "link") else { return }
        var size: NSSize? = nil
        if let ext = Self.descendant(d, "extent"), let cx = Self.attr(ext, "cx"), let cy = Self.attr(ext, "cy"), let w = Double(cx), let h = Double(cy), w > 0, h > 0 {
            size = NSSize(width: w / 12700, height: h / 12700)
        }
        let descr = Self.descendant(d, "docPr").flatMap { Self.attr($0, "descr") }
        insertImage(rId: rid, size: size, descr: descr, props: props)
    }

    private func vmlImage(_ e: XMLElement, props: ParaProps, run: RunProps) {
        guard let data = Self.descendant(e, "imagedata"), let rid = Self.attr(data, "id") ?? Self.attr(data, "href") else { return }
        var size: NSSize? = nil
        if let shape = Self.descendant(e, "shape"), let style = Self.attr(shape, "style") {
            var w: Double? = nil, h: Double? = nil
            for part in style.split(separator: ";") {
                let kv = part.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                guard kv.count == 2 else { continue }
                let v = Double(kv[1].replacingOccurrences(of: "pt", with: "").replacingOccurrences(of: "px", with: ""))
                if kv[0] == "width" { w = v } else if kv[0] == "height" { h = v }
            }
            if let w, let h { size = NSSize(width: w, height: h) }
        }
        insertImage(rId: rid, size: size, descr: nil, props: props)
    }

    private func insertImage(rId: String, size: NSSize?, descr: String?, props: ParaProps) {
        guard let rel = rels[rId], !rel.external else { return }
        var path = rel.target
        if path.hasPrefix("/") { path.removeFirst() } else { path = "word/" + path }
        while let r = path.range(of: "word/../") { path.replaceSubrange(r, with: "") }
        guard let data = zip.contents(of: path) else { return }
        var attrs = baseAttributes(props: props, run: RunProps())
        if let descr, let eq = EquationCell.parseDocxDescription(descr) {
            let att = AttachmentFactory.equationAttachment(pngData: data, source: eq.source, display: eq.display, displaySize: size ?? NSSize(width: 120, height: 32), baselineDrop: eq.baselineDrop)
            attrs[.attachment] = att
            attrs[.tideEquation] = eq.source
        } else {
            let name = (path as NSString).lastPathComponent
            guard let att = AttachmentFactory.imageAttachment(data: data, filename: name, displaySize: size, maxWidth: 468) else { return }
            attrs[.attachment] = att
        }
        result.append(NSAttributedString(string: "\u{FFFC}", attributes: attrs))
    }
}
