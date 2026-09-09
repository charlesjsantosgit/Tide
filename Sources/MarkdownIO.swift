import AppKit
import Foundation

// MARK: - Export

enum MarkdownExporter {
    private struct Deco: Equatable {
        var bold = false, italic = false, underline = false, strike = false, highlight = false
        var link: String? = nil
        var code = false
    }

    static func markdown(from text: NSAttributedString, typography: Typography) -> String {
        var lines: [String] = []
        var prevList: ListKind? = nil
        var counter = 0
        for p in DocumentWalker.paragraphs(of: text, typography: typography) {
            var line = ""
            if let kind = p.listKind {
                if prevList != kind { counter = 0 }
                counter += 1
                line += String(repeating: "  ", count: p.listLevel) + (kind == .bullet ? "- " : "\(counter). ")
            } else {
                counter = 0
                line += p.style.markdownPrefix
            }
            prevList = p.listKind

            // Collect (decoration, text) pieces, merging neighbours with identical decoration.
            var pieces: [(Deco?, String)] = []
            for (s, attrs) in DocumentWalker.runs(of: text, in: p.contentRange) {
                if let att = attrs[.attachment] as? NSTextAttachment {
                    pieces.append((nil, attachmentMarkdown(att)))
                    continue
                }
                let font = attrs[.font] as? NSFont
                let styleTag = attrs[.tideStyle] as? String
                var d = Deco()
                d.bold = (font?.isBold ?? false) && (styleTag == nil || styleTag == TextStyle.body.rawValue) && p.style == .body
                d.italic = font?.isItalic ?? false
                d.underline = (attrs[.underlineStyle] as? Int ?? 0) != 0
                d.strike = (attrs[.strikethroughStyle] as? Int ?? 0) != 0
                d.highlight = attrs[.tideHighlight] != nil || attrs[.backgroundColor] != nil
                d.code = font?.familyName == Typography.monoFamily
                if let l = attrs[.link] { d.link = (l as? URL)?.absoluteString ?? (l as? String) }
                let t = s.replacingOccurrences(of: "\u{2028}", with: "  \n").replacingOccurrences(of: "\u{FFFC}", with: "")
                if let last = pieces.last, last.0 == d { pieces[pieces.count - 1].1 += t } else { pieces.append((d, t)) }
            }
            var body = ""
            for (deco, t) in pieces {
                guard let d = deco else { body += t; continue }
                body += wrap(t, d)
            }
            lines.append(line + body)
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func wrap(_ text: String, _ d: Deco) -> String {
        let core = text.trimmingCharacters(in: .whitespaces)
        guard !core.isEmpty else { return text }
        let lead = String(text.prefix(while: { $0 == " " }))
        let trail = String(text.reversed().prefix(while: { $0 == " " }))
        var w = d.code ? "`\(core)`" : escape(core)
        if d.strike { w = "~~\(w)~~" }
        if d.underline { w = "<u>\(w)</u>" }
        if d.italic { w = "*\(w)*" }
        if d.bold { w = "**\(w)**" }
        if d.highlight { w = "==\(w)==" }
        if let link = d.link { w = "[\(w)](\(link))" }
        return lead + w + trail
    }

    private static func escape(_ s: String) -> String {
        var out = ""
        for ch in s {
            switch ch {
            case "*", "_", "`", "\\", "#", "[", "]", "~", "=": out.append("\\"); out.append(ch)
            default: out.append(ch)
            }
        }
        return out
    }

    private static func attachmentMarkdown(_ att: NSTextAttachment) -> String {
        if let eq = att.attachmentCell as? EquationCell {
            return eq.display ? "$$\(eq.source)$$" : "$\(eq.source)$"
        }
        if let chip = att.attachmentCell as? FileChipCell {
            let label = (chip.kind == .audio ? "🎵 " : "📎 ") + chip.name
            if let u = chip.fileURL { return "[\(label)](\(u.absoluteString))" }
            return label
        }
        if let data = att.fileWrapper?.regularFileContents ?? att.image.flatMap(ImageUtil.pngData),
           let (bytes, _, mime) = ImageUtil.normalized(data) {
            let name = att.fileWrapper?.preferredFilename ?? "image"
            return "![\(name)](data:\(mime);base64,\(bytes.base64EncodedString()))"
        }
        return ""
    }
}

// MARK: - Import

enum MarkdownImporter {
    static func attributedString(from markdown: String, typography: Typography, baseURL: URL?) -> NSAttributedString {
        var md = markdown.replacingOccurrences(of: "\r\n", with: "\n")
        // Obsidian-style YAML front matter
        if md.hasPrefix("---\n"), let close = md.range(of: "\n---", range: md.index(md.startIndex, offsetBy: 3)..<md.endIndex) {
            var rest = Substring(md[close.upperBound...])
            if let nl = rest.firstIndex(of: "\n") { rest = rest[rest.index(after: nl)...] } else { rest = "" }
            md = String(rest)
        }
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .full
        options.allowsExtendedAttributes = true
        options.failurePolicy = .returnPartiallyParsedIfPossible
        let parsed = (try? AttributedString(markdown: md, options: options, baseURL: baseURL)) ?? AttributedString(md)

        struct Block {
            var id = -1
            var style: TextStyle = .body
            var list: ListKind? = nil
            var listId = -1
            var level = 0
            var code = false
            var quote = false
        }

        let out = NSMutableAttributedString()
        var current: Block? = nil
        var blockStart = 0
        var listCounters: [Int: Int] = [:]
        var lastCell: Int? = nil
        var lastAttrs: [NSAttributedString.Key: Any] = typography.bodyAttributes()

        func close(_ b: Block) {
            let ps = typography.paragraphStyle(for: b.style)
            if let kind = b.list { ListSupport.configure(ps, kind: kind, level: b.level) }
            if b.quote { ps.headIndent = 24; ps.firstLineHeadIndent = 24 }
            let r = NSRange(location: blockStart, length: out.length - blockStart)
            if r.length > 0 {
                out.addAttribute(.paragraphStyle, value: ps, range: r)
                out.addAttribute(.tideStyle, value: b.style.rawValue, range: r)
            }
            lastAttrs[.paragraphStyle] = ps
        }

        for run in parsed.runs {
            var block = Block()
            var lists: [(Int, ListKind)] = []
            var thematic = false
            var cell: Int? = nil
            if let intent = run.presentationIntent {
                for comp in intent.components {
                    switch comp.kind {
                    case .paragraph: block.id = comp.identity
                    case .header(let level):
                        block.id = comp.identity
                        block.style = level <= 1 ? .title : (level == 2 ? .heading : .subheading)
                    case .codeBlock: block.id = comp.identity; block.code = true
                    case .blockQuote: block.quote = true
                    case .thematicBreak: block.id = comp.identity; thematic = true
                    case .orderedList: lists.append((comp.identity, .numbered))
                    case .unorderedList: lists.append((comp.identity, .bullet))
                    case .tableCell: cell = comp.identity
                    case .tableRow, .tableHeaderRow: if block.id < 0 { block.id = comp.identity }
                    default: break
                    }
                }
            }
            if let inner = lists.max(by: { $0.0 < $1.0 }) {
                block.list = inner.1
                block.listId = inner.0
                block.level = min(lists.count - 1, 2)
            }

            if current == nil || current!.id != block.id {
                if let c = current {
                    close(c)
                    out.append(NSAttributedString(string: "\n", attributes: lastAttrs))
                }
                blockStart = out.length
                current = block
                lastCell = cell
                if let kind = block.list {
                    let n = (listCounters[block.listId] ?? 0) + 1
                    listCounters[block.listId] = n
                    var attrs = typography.attributes(for: block.style)
                    attrs[.font] = typography.font(for: block.style, bold: false)
                    out.append(NSAttributedString(string: ListSupport.prefix(kind: kind, level: block.level, itemNumber: n), attributes: attrs))
                }
            } else if let cell, cell != lastCell {
                out.append(NSAttributedString(string: "\t", attributes: lastAttrs))
                lastCell = cell
            }

            var text = String(parsed[run.range].characters)
            let inline = run.inlinePresentationIntent ?? []
            if inline.contains(.softBreak) { text = " " }
            if inline.contains(.lineBreak) { text = "\u{2028}" }
            if thematic { text = "" }
            let code = inline.contains(.code) || block.code
            let bold = inline.contains(.stronglyEmphasized) || block.style.isBold
            let italic = inline.contains(.emphasized)
            var attrs: [NSAttributedString.Key: Any] = [
                .font: typography.font(family: code ? Typography.monoFamily : typography.family, size: typography.size(for: block.style) * (code ? 0.92 : 1), bold: bold, italic: italic),
                .foregroundColor: NSColor.textColor,
                .tideStyle: block.style.rawValue,
            ]
            if inline.contains(.strikethrough) { attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            if let link = run.link { attrs[.link] = link }

            if let imageURL = run.imageURL {
                var resolved = imageURL
                if !imageURL.isFileURL, imageURL.scheme == nil, let base = baseURL { resolved = base.deletingLastPathComponent().appendingPathComponent(imageURL.path) }
                if resolved.isFileURL, let data = try? Data(contentsOf: resolved),
                   let att = AttachmentFactory.imageAttachment(data: data, filename: resolved.lastPathComponent, displaySize: nil, maxWidth: 468) {
                    var a = attrs
                    a[.attachment] = att
                    out.append(NSAttributedString(string: "\u{FFFC}", attributes: a))
                    lastAttrs = attrs
                    continue
                }
                if text.isEmpty { text = "🖼 " + imageURL.lastPathComponent }
            }
            out.append(NSAttributedString(string: text, attributes: attrs))
            lastAttrs = attrs
        }
        if let c = current { close(c) }
        InlineMarkup.apply(out, typography: typography)
        return out
    }
}

/// `==highlight==` and `$equation$` are not markdown proper, but Obsidian users live on them.
enum InlineMarkup {
    static func apply(_ s: NSMutableAttributedString, typography: Typography) {
        replace(s, pattern: "==([^=\\n]+?)==") { inner, attrs in
            var a = attrs
            a[.backgroundColor] = Highlight.butter.color
            a[.tideHighlight] = Highlight.butter.rawValue
            return NSAttributedString(string: inner, attributes: a)
        }
        replace(s, pattern: "\\$\\$([^$]+?)\\$\\$") { inner, attrs in equation(inner, display: true, attrs: attrs) }
        replace(s, pattern: "(?<![\\\\$])\\$([^$\\n]+?)\\$") { inner, attrs in equation(inner, display: false, attrs: attrs) }
    }

    private static func equation(_ src: String, display: Bool, attrs: [NSAttributedString.Key: Any]) -> NSAttributedString {
        let source = src.trimmingCharacters(in: .whitespaces)
        let font = attrs[.font] as? NSFont ?? NSFont.systemFont(ofSize: 12)
        let est = NSSize(width: max(40, CGFloat(source.count) * font.pointSize * 0.62 + 16), height: font.pointSize * 1.9)
        let att = AttachmentFactory.equationAttachment(pngData: nil, source: source, display: display, displaySize: est, baselineDrop: font.pointSize * 0.5)
        var a = attrs
        a[.attachment] = att
        a[.tideEquation] = source
        return NSAttributedString(string: "\u{FFFC}", attributes: a)
    }

    private static func replace(_ s: NSMutableAttributedString, pattern: String, with builder: (String, [NSAttributedString.Key: Any]) -> NSAttributedString) {
        guard let re = try? NSRegularExpression(pattern: pattern, options: []) else { return }
        let matches = re.matches(in: s.string, options: [], range: NSRange(location: 0, length: s.length))
        for m in matches.reversed() {
            let inner = (s.string as NSString).substring(with: m.range(at: 1))
            let attrs = s.attributes(at: m.range.location, effectiveRange: nil)
            s.replaceCharacters(in: m.range, with: builder(inner, attrs))
        }
    }
}
