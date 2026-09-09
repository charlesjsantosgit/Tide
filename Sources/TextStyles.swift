import AppKit

extension NSAttributedString.Key {
    /// Paragraph style name ("title", "heading", "subheading", "body").
    static let tideStyle = NSAttributedString.Key("TideStyle")
    /// Highlight index (1...5) — see `Highlight`.
    static let tideHighlight = NSAttributedString.Key("TideHighlight")
    /// LaTeX source of an equation attachment (secondary to the cell's own copy).
    static let tideEquation = NSAttributedString.Key("TideEquation")
}

enum TextStyle: String, CaseIterable, Identifiable {
    case title, heading, subheading, body
    var id: String { rawValue }

    var label: String {
        switch self {
        case .title: return "Title"
        case .heading: return "Heading"
        case .subheading: return "Subheading"
        case .body: return "Body"
        }
    }
    var sizeMultiplier: CGFloat {
        switch self {
        case .title: return 2.2
        case .heading: return 1.5
        case .subheading: return 1.17
        case .body: return 1.0
        }
    }
    var isBold: Bool { self != .body }
    var spacingBefore: CGFloat {
        switch self {
        case .title: return 0
        case .heading: return 14
        case .subheading: return 10
        case .body: return 0
        }
    }
    var spacingAfter: CGFloat {
        switch self {
        case .title: return 10
        case .heading: return 4
        case .subheading: return 2
        case .body: return 6
        }
    }
    /// Word style id used in the .docx we write and recognised when we read.
    var docxStyleId: String? {
        switch self {
        case .title: return "Title"
        case .heading: return "Heading1"
        case .subheading: return "Heading2"
        case .body: return nil
        }
    }
    var markdownPrefix: String {
        switch self {
        case .title: return "# "
        case .heading: return "## "
        case .subheading: return "### "
        case .body: return ""
        }
    }
    var htmlTag: String {
        switch self {
        case .title: return "h1"
        case .heading: return "h2"
        case .subheading: return "h3"
        case .body: return "p"
        }
    }

    /// Reads the style of a run: the explicit tag if present, otherwise a guess from the font.
    static func of(_ attrs: [NSAttributedString.Key: Any], _ t: Typography) -> TextStyle {
        if let raw = attrs[.tideStyle] as? String, let s = TextStyle(rawValue: raw) { return s }
        guard let font = attrs[.font] as? NSFont else { return .body }
        let size = font.pointSize
        if size >= t.size(for: .title) * 0.92 { return .title }
        if size >= t.size(for: .heading) * 0.92 { return .heading }
        if size >= t.size(for: .subheading) * 0.97 && font.isBold { return .subheading }
        return .body
    }
}

extension NSFont {
    var isBold: Bool { fontDescriptor.symbolicTraits.contains(.bold) }
    var isItalic: Bool { fontDescriptor.symbolicTraits.contains(.italic) }
}

/// Resolves the user's font settings into concrete fonts and paragraph styles.
struct Typography: Equatable {
    var family: String
    var bodySize: CGFloat
    var lineSpacing: CGFloat

    static var current: Typography {
        Typography(family: Settings.fontFamily, bodySize: Settings.bodySize, lineSpacing: Settings.lineSpacing)
    }

    static let monoFamily = "Menlo"

    func size(for style: TextStyle) -> CGFloat { (bodySize * style.sizeMultiplier).rounded() }

    func font(for style: TextStyle, bold: Bool? = nil, italic: Bool = false) -> NSFont {
        font(family: family, size: size(for: style), bold: bold ?? style.isBold, italic: italic)
    }

    func font(family: String, size: CGFloat, bold: Bool, italic: Bool) -> NSFont {
        let fm = NSFontManager.shared
        if family == Settings.systemFamily || family.hasPrefix(".") {
            var f = NSFont.systemFont(ofSize: size, weight: bold ? .bold : .regular)
            if italic { f = fm.convert(f, toHaveTrait: .italicFontMask) }
            return f
        }
        var traits: NSFontTraitMask = []
        if bold { traits.insert(.boldFontMask) }
        if italic { traits.insert(.italicFontMask) }
        if let f = fm.font(withFamily: family, traits: traits, weight: bold ? 9 : 5, size: size) { return f }
        if var f = NSFont(name: family, size: size) {
            if bold { f = fm.convert(f, toHaveTrait: .boldFontMask) }
            if italic { f = fm.convert(f, toHaveTrait: .italicFontMask) }
            return f
        }
        var f = NSFont.systemFont(ofSize: size, weight: bold ? .bold : .regular)
        if italic { f = fm.convert(f, toHaveTrait: .italicFontMask) }
        return f
    }

    /// Re-targets an existing font at this typography (same traits, new family/size for the style).
    func restyled(_ font: NSFont, as style: TextStyle, keepFamily: Bool) -> NSFont {
        let fam = keepFamily ? (font.familyName ?? family) : family
        let bold = style.isBold || font.isBold
        return self.font(family: fam, size: size(for: style), bold: bold, italic: font.isItalic)
    }

    func paragraphStyle(for style: TextStyle, base: NSParagraphStyle? = nil) -> NSMutableParagraphStyle {
        let ps = (base?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
        ps.lineHeightMultiple = max(1.0, lineSpacing)
        ps.paragraphSpacingBefore = style.spacingBefore
        ps.paragraphSpacing = style.spacingAfter
        return ps
    }

    func bodyAttributes(alignment: NSTextAlignment = .natural) -> [NSAttributedString.Key: Any] {
        let ps = paragraphStyle(for: .body)
        ps.alignment = alignment
        return [.font: font(for: .body), .paragraphStyle: ps, .foregroundColor: NSColor.textColor, .tideStyle: TextStyle.body.rawValue]
    }

    func attributes(for style: TextStyle, bold: Bool? = nil, italic: Bool = false) -> [NSAttributedString.Key: Any] {
        [.font: font(for: style, bold: bold, italic: italic), .paragraphStyle: paragraphStyle(for: style), .foregroundColor: NSColor.textColor, .tideStyle: style.rawValue]
    }
}

// MARK: - Highlights

enum Highlight: Int, CaseIterable, Identifiable {
    case sky = 1, mint, butter, lilac, blush
    var id: Int { rawValue }

    var name: String {
        switch self {
        case .sky: return "Sky"
        case .mint: return "Mint"
        case .butter: return "Butter"
        case .lilac: return "Lilac"
        case .blush: return "Blush"
        }
    }
    var light: NSColor {
        switch self {
        case .sky: return NSColor(srgbRed: 0.80, green: 0.90, blue: 1.00, alpha: 1)
        case .mint: return NSColor(srgbRed: 0.79, green: 0.95, blue: 0.89, alpha: 1)
        case .butter: return NSColor(srgbRed: 1.00, green: 0.94, blue: 0.68, alpha: 1)
        case .lilac: return NSColor(srgbRed: 0.89, green: 0.86, blue: 1.00, alpha: 1)
        case .blush: return NSColor(srgbRed: 1.00, green: 0.85, blue: 0.90, alpha: 1)
        }
    }
    var dark: NSColor {
        switch self {
        case .sky: return NSColor(srgbRed: 0.14, green: 0.32, blue: 0.55, alpha: 1)
        case .mint: return NSColor(srgbRed: 0.11, green: 0.38, blue: 0.30, alpha: 1)
        case .butter: return NSColor(srgbRed: 0.45, green: 0.37, blue: 0.08, alpha: 1)
        case .lilac: return NSColor(srgbRed: 0.30, green: 0.24, blue: 0.55, alpha: 1)
        case .blush: return NSColor(srgbRed: 0.48, green: 0.19, blue: 0.30, alpha: 1)
        }
    }
    /// Appearance-aware colour used inside the editor.
    var color: NSColor {
        let l = light, d = dark
        return NSColor(name: "TideHighlight\(rawValue)") { app in
            app.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? d : l
        }
    }
    /// The light colour as RRGGBB, for exporters.
    var hex: String { light.hexString }

    /// Nearest palette entry for an imported colour, if it is reasonably close.
    static func nearest(to color: NSColor) -> Highlight? {
        guard let c = color.usingColorSpace(.sRGB) else { return nil }
        var best: (Highlight, CGFloat)? = nil
        for h in allCases {
            let l = h.light
            let d = abs(l.redComponent - c.redComponent) + abs(l.greenComponent - c.greenComponent) + abs(l.blueComponent - c.blueComponent)
            if best == nil || d < best!.1 { best = (h, d) }
        }
        if let b = best, b.1 < 0.22 { return b.0 }
        return nil
    }
}

extension NSColor {
    var hexString: String {
        guard let c = usingColorSpace(.sRGB) else { return "000000" }
        let r = Int((c.redComponent * 255).rounded()), g = Int((c.greenComponent * 255).rounded()), b = Int((c.blueComponent * 255).rounded())
        return String(format: "%02X%02X%02X", r, g, b)
    }
    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
    /// True for catalog/dynamic colours such as `.textColor`, which have no fixed RGB value.
    var isDynamic: Bool { type == .catalog }
}
