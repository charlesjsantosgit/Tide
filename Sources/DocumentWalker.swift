import AppKit

enum ListKind: Int, CaseIterable {
    case bullet = 1, numbered = 2

    static func of(_ ps: NSParagraphStyle?) -> ListKind? {
        guard let list = ps?.textLists.last else { return nil }
        return ListKind(markerFormat: list.markerFormat)
    }
    init(markerFormat: NSTextList.MarkerFormat) {
        let raw = markerFormat.rawValue
        if raw.contains("decimal") || raw.contains("alpha") || raw.contains("roman") || raw.contains("octal") || raw.contains("hexadecimal") {
            self = .numbered
        } else {
            self = .bullet
        }
    }
    func textList(level: Int) -> NSTextList {
        switch self {
        case .bullet:
            let formats: [NSTextList.MarkerFormat] = [.disc, .circle, .square]
            return NSTextList(markerFormat: formats[max(0, level) % 3], options: 0)
        case .numbered:
            let formats = ["{decimal}.", "{lower-alpha}.", "{lower-roman}."]
            return NSTextList(markerFormat: NSTextList.MarkerFormat(rawValue: formats[max(0, level) % 3]), options: 0)
        }
    }
    var abstractNumId: Int { self == .bullet ? 0 : 1 }
}

enum ListSupport {
    static let levelIndent: CGFloat = 26
    static let markerWidth: CGFloat = 30

    /// Range of the "\t•\t" marker prefix at the start of a paragraph, if there is one.
    static func markerPrefixRange(in string: NSString, paragraph: NSRange) -> NSRange? {
        guard paragraph.length >= 3, string.character(at: paragraph.location) == 0x09 else { return nil }
        var i = paragraph.location + 1
        let limit = min(NSMaxRange(paragraph), paragraph.location + 14)
        while i < limit {
            if string.character(at: i) == 0x09 { return NSRange(location: paragraph.location, length: i - paragraph.location + 1) }
            i += 1
        }
        return nil
    }

    static func prefix(kind: ListKind, level: Int, itemNumber: Int) -> String {
        "\t" + kind.textList(level: level).marker(forItemNumber: itemNumber) + "\t"
    }

    static func configure(_ ps: NSMutableParagraphStyle, kind: ListKind?, level: Int) {
        if let kind {
            ps.textLists = (0...max(0, level)).map { kind.textList(level: $0) }
            let first = CGFloat(level) * levelIndent
            ps.firstLineHeadIndent = first
            ps.headIndent = first + markerWidth
            ps.tabStops = [
                NSTextTab(textAlignment: .right, location: first + markerWidth - 8, options: [:]),
                NSTextTab(textAlignment: .left, location: first + markerWidth, options: [:]),
            ]
        } else {
            ps.textLists = []
            ps.firstLineHeadIndent = 0
            ps.headIndent = 0
            ps.tabStops = []
        }
    }
}

/// One paragraph of a document as the exporters see it.
struct ParagraphInfo {
    var range: NSRange            // whole paragraph including trailing newline
    var contentRange: NSRange     // text after the list marker, before the newline
    var attributes: [NSAttributedString.Key: Any]
    var paragraphStyle: NSParagraphStyle
    var style: TextStyle
    var listKind: ListKind?
    var listLevel: Int
    var alignment: NSTextAlignment { paragraphStyle.alignment }
}

enum DocumentWalker {
    static func paragraphs(of text: NSAttributedString, typography: Typography) -> [ParagraphInfo] {
        let str = text.string as NSString
        var result: [ParagraphInfo] = []
        var loc = 0
        var ranges: [NSRange] = []
        while loc < str.length {
            let r = str.paragraphRange(for: NSRange(location: loc, length: 0))
            ranges.append(r)
            loc = NSMaxRange(r)
            if r.length == 0 { break }
        }
        if str.length == 0 || str.hasSuffix("\n") { ranges.append(NSRange(location: str.length, length: 0)) }

        for r in ranges {
            let attrs: [NSAttributedString.Key: Any]
            if r.length > 0 {
                attrs = text.attributes(at: r.location, effectiveRange: nil)
            } else {
                attrs = typography.bodyAttributes()
            }
            let ps = attrs[.paragraphStyle] as? NSParagraphStyle ?? NSParagraphStyle.default
            var content = r
            if r.length > 0, str.character(at: NSMaxRange(r) - 1) == 0x0A { content.length -= 1 }
            let kind = ListKind.of(ps)
            var level = 0
            if kind != nil {
                level = max(0, ps.textLists.count - 1)
                if let prefix = ListSupport.markerPrefixRange(in: str, paragraph: content) {
                    content = NSRange(location: NSMaxRange(prefix), length: content.length - prefix.length)
                }
            }
            result.append(ParagraphInfo(range: r, contentRange: content, attributes: attrs, paragraphStyle: ps,
                                        style: TextStyle.of(attrs, typography), listKind: kind, listLevel: level))
        }
        return result
    }

    /// Runs (text, attributes) inside a range.
    static func runs(of text: NSAttributedString, in range: NSRange) -> [(String, [NSAttributedString.Key: Any])] {
        var out: [(String, [NSAttributedString.Key: Any])] = []
        guard range.length > 0 else { return out }
        text.enumerateAttributes(in: range, options: []) { attrs, r, _ in
            out.append(((text.string as NSString).substring(with: r), attrs))
        }
        return out
    }
}

enum XML {
    static func escape(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for scalar in s.unicodeScalars {
            switch scalar {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "\u{9}", "\u{A}", "\u{D}": out.unicodeScalars.append(scalar)
            default:
                if scalar.value < 0x20 || scalar.value == 0xFFFE || scalar.value == 0xFFFF { continue }
                out.unicodeScalars.append(scalar)
            }
        }
        return out
    }
}

enum ImageUtil {
    enum Kind { case png, jpeg, gif }
    static func kind(of data: Data) -> Kind? {
        guard data.count > 4 else { return nil }
        let b = [UInt8](data.prefix(4))
        if b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47 { return .png }
        if b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF { return .jpeg }
        if b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46 { return .gif }
        return nil
    }
    /// Returns image bytes Word (and browsers) accept, re-encoding TIFF/HEIC/etc. as PNG.
    static func normalized(_ data: Data) -> (Data, String, String)? {
        switch kind(of: data) {
        case .png: return (data, "png", "image/png")
        case .jpeg: return (data, "jpeg", "image/jpeg")
        case .gif: return (data, "gif", "image/gif")
        case nil:
            guard let rep = NSBitmapImageRep(data: data) ?? NSImage(data: data).flatMap({ NSBitmapImageRep(data: $0.tiffRepresentation ?? Data()) }),
                  let png = rep.representation(using: .png, properties: [:]) else { return nil }
            return (png, "png", "image/png")
        }
    }
    static func pngData(_ image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
    static func pixelSize(_ data: Data) -> NSSize? {
        guard let rep = NSBitmapImageRep(data: data) else { return nil }
        return NSSize(width: rep.pixelsWide, height: rep.pixelsHigh)
    }
}
