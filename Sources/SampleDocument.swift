import AppKit

/// The document shown in screenshots and exercised by the self-test.
enum SampleDocument {
    static func make(typography t: Typography, renderEquations: Bool) -> NSAttributedString {
        let s = NSMutableAttributedString()

        func para(_ text: String, _ style: TextStyle = .body) {
            s.append(NSAttributedString(string: text + "\n", attributes: t.attributes(for: style)))
        }
        func run(_ text: String, bold: Bool = false, italic: Bool = false, underline: Bool = false, highlight: Highlight? = nil, link: String? = nil) {
            var a = t.attributes(for: .body, bold: bold, italic: italic)
            if underline { a[.underlineStyle] = NSUnderlineStyle.single.rawValue }
            if let h = highlight { a[.backgroundColor] = h.color; a[.tideHighlight] = h.rawValue }
            if let l = link, let url = URL(string: l) { a[.link] = url }
            s.append(NSAttributedString(string: text, attributes: a))
        }
        func newline(_ style: TextStyle = .body, alignment: NSTextAlignment = .natural) {
            var a = t.attributes(for: style)
            if alignment != .natural { let ps = t.paragraphStyle(for: style); ps.alignment = alignment; a[.paragraphStyle] = ps }
            s.append(NSAttributedString(string: "\n", attributes: a))
        }
        func list(_ items: [String], _ kind: ListKind) {
            for (i, item) in items.enumerated() {
                var a = t.attributes(for: .body)
                let ps = t.paragraphStyle(for: .body)
                ListSupport.configure(ps, kind: kind, level: 0)
                a[.paragraphStyle] = ps
                s.append(NSAttributedString(string: ListSupport.prefix(kind: kind, level: 0, itemNumber: i + 1) + item + "\n", attributes: a))
            }
        }
        func equation(_ src: String, display: Bool) {
            var a = t.attributes(for: .body)
            if display {
                let ps = t.paragraphStyle(for: .body)
                ps.alignment = .center
                a[.paragraphStyle] = ps
            }
            var att: NSTextAttachment
            if renderEquations, let r = EquationRenderer.shared.renderSync(latex: src, display: display, fontSize: (t.bodySize * (display ? 1.35 : 1.15)).rounded()) {
                att = AttachmentFactory.equationAttachment(pngData: r.png, source: src, display: display, displaySize: r.size, baselineDrop: r.baselineDrop)
            } else {
                att = AttachmentFactory.equationAttachment(pngData: nil, source: src, display: display, displaySize: NSSize(width: CGFloat(src.count) * 7 + 16, height: 24), baselineDrop: 6)
            }
            a[.attachment] = att
            a[.tideEquation] = src
            s.append(NSAttributedString(string: "\u{FFFC}", attributes: a))
            if display { s.append(NSAttributedString(string: "\n", attributes: a)) }
        }

        para("The Tide Manual", .title)
        run("Tide is a small word processor for people who would rather write than fiddle with toolbars. Everything you see here is a real ")
        run("Word document", bold: true)
        run(", saved as .docx, so it opens in Word, Pages and Google Docs with the formatting intact.")
        newline()

        para("Why it feels light", .heading)
        run("Hover over the oval on the side of the window and it opens into the whole toolbox. Text can be ")
        run("bold", bold: true); run(", "); run("italic", italic: true); run(", "); run("underlined", underline: true)
        run(", or highlighted in "); run("sky", highlight: .sky); run(", "); run("mint", highlight: .mint); run(", ")
        run("butter", highlight: .butter); run(", "); run("lilac", highlight: .lilac); run(" and "); run("blush", highlight: .blush)
        run(" — five colours picked to sit well on blue glass.")
        newline()

        para("What is in the box", .subheading)
        list(["Titles, headings and body text that export as real Word styles",
              "Five highlight colours, bulleted and numbered lists, alignment and indents",
              "Images, files, audio clips, links and LaTeX equations"], .bullet)

        para("Getting started", .subheading)
        list(["Open the panel by hovering over it (or click, if you set it that way)",
              "Pick a style, or just start typing — Return after a heading gives you body text",
              "Press ⌘S and you have a .docx"], .numbered)

        para("Equations", .heading)
        run("Tide renders LaTeX with the system's math fonts. Inline, like ")
        equation("E = mc^2", display: false)
        run(", or on a line of their own:")
        newline()
        equation("x = \\frac{-b \\pm \\sqrt{b^2 - 4ac}}{2a}", display: true)

        para("Pictures and files", .heading)
        run("Images sit inline and scale to the page. Files and audio become chips — click an audio chip to play it. ")
        run("Links", link: "https://www.apple.com/macos/")
        run(" work too.")
        newline()
        if let png = sampleImagePNG(), let att = AttachmentFactory.imageAttachment(data: png, filename: "tide-sample.png", displaySize: nil, maxWidth: 468) {
            var a = t.attributes(for: .body)
            a[.attachment] = att
            s.append(NSAttributedString(string: "\u{FFFC}", attributes: a))
            newline()
        }
        if let wav = sampleWAV(), let att = AttachmentFactory.chipAttachment(fileURL: wav) {
            run("Recorded idea: ")
            var a = t.attributes(for: .body)
            a[.attachment] = att
            s.append(NSAttributedString(string: "\u{FFFC}", attributes: a))
            newline()
        }
        return s
    }

    static func sampleImagePNG() -> Data? {
        let size = NSSize(width: 900, height: 420)
        let img = NSImage(size: size, flipped: false) { rect in
            let g = NSGradient(colors: [NSColor(srgbRed: 0.40, green: 0.68, blue: 1.0, alpha: 1), NSColor(srgbRed: 0.10, green: 0.32, blue: 0.85, alpha: 1)])!
            g.draw(in: rect, angle: -60)
            for (i, alpha) in [0.10, 0.14, 0.18].enumerated() {
                let p = NSBezierPath()
                let base = rect.height * (0.28 + CGFloat(i) * 0.12)
                p.move(to: NSPoint(x: 0, y: 0))
                p.line(to: NSPoint(x: 0, y: base))
                var x: CGFloat = 0
                while x <= rect.width {
                    p.line(to: NSPoint(x: x, y: base + sin(x / rect.width * .pi * 2 + CGFloat(i)) * 26))
                    x += 6
                }
                p.line(to: NSPoint(x: rect.width, y: 0))
                p.close()
                NSColor.white.withAlphaComponent(alpha).setFill()
                p.fill()
            }
            NSColor.white.withAlphaComponent(0.9).setFill()
            NSBezierPath(ovalIn: NSRect(x: rect.width * 0.72, y: rect.height * 0.55, width: 90, height: 90)).fill()
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 44, weight: .bold), .foregroundColor: NSColor.white]
            ("high tide" as NSString).draw(at: NSPoint(x: 48, y: rect.height - 110), withAttributes: attrs)
            return true
        }
        return ImageUtil.pngData(img)
    }

    /// A short 440 Hz tone as a WAV file in the temporary directory.
    static func sampleWAV() -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tide-sample-tone.wav")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        let rate = 22050
        let seconds = 0.8
        let count = Int(Double(rate) * seconds)
        var samples = Data(capacity: count * 2)
        for i in 0..<count {
            let tm = Double(i) / Double(rate)
            let env = min(1, tm * 20) * min(1, (seconds - tm) * 6)
            let v = Int16(sin(tm * 2 * .pi * 440) * 0.4 * env * 32767)
            var le = v.littleEndian
            withUnsafeBytes(of: &le) { samples.append(contentsOf: $0) }
        }
        var d = Data()
        func u32(_ v: UInt32) { var x = v.littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { var x = v.littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
        d.append(contentsOf: Array("RIFF".utf8)); u32(UInt32(36 + samples.count)); d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(1); u32(UInt32(rate)); u32(UInt32(rate * 2)); u16(2); u16(16)
        d.append(contentsOf: Array("data".utf8)); u32(UInt32(samples.count)); d.append(samples)
        do { try d.write(to: url) } catch { return nil }
        return url
    }
}
