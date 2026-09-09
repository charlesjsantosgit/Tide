import AppKit
import WebKit

// MARK: - LaTeX (a practical subset) → MathML

enum LaTeXToMathML {
    static func convert(_ latex: String, display: Bool) -> String {
        var p = Parser(latex)
        let body = p.parseSequence(terminator: nil, stopAtRight: false)
        return "<math xmlns=\"http://www.w3.org/1998/Math/MathML\" display=\"\(display ? "block" : "inline")\"><mrow>\(body.joined())</mrow></math>"
    }

    static func esc(_ c: Character) -> String { esc(String(c)) }
    static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }
    static func mrow(_ parts: [String]) -> String {
        parts.count == 1 ? parts[0] : "<mrow>\(parts.joined())</mrow>"
    }

    static let identifiers: [String: String] = [
        "alpha": "α", "beta": "β", "gamma": "γ", "delta": "δ", "epsilon": "ϵ", "varepsilon": "ε", "zeta": "ζ", "eta": "η",
        "theta": "θ", "vartheta": "ϑ", "iota": "ι", "kappa": "κ", "lambda": "λ", "mu": "μ", "nu": "ν", "xi": "ξ", "pi": "π",
        "varpi": "ϖ", "rho": "ρ", "varrho": "ϱ", "sigma": "σ", "varsigma": "ς", "tau": "τ", "upsilon": "υ", "phi": "ϕ",
        "varphi": "φ", "chi": "χ", "psi": "ψ", "omega": "ω",
        "infty": "∞", "partial": "∂", "hbar": "ℏ", "ell": "ℓ", "Re": "ℜ", "Im": "ℑ", "aleph": "ℵ", "emptyset": "∅",
        "varnothing": "∅", "imath": "ı", "jmath": "ȷ", "wp": "℘", "nabla": "∇",
    ]
    static let uprightIdentifiers: [String: String] = [
        "Gamma": "Γ", "Delta": "Δ", "Theta": "Θ", "Lambda": "Λ", "Xi": "Ξ", "Pi": "Π", "Sigma": "Σ", "Upsilon": "Υ",
        "Phi": "Φ", "Psi": "Ψ", "Omega": "Ω",
    ]
    static let operators: [String: String] = [
        "pm": "±", "mp": "∓", "times": "×", "cdot": "⋅", "div": "÷", "ast": "∗", "star": "⋆", "circ": "∘", "bullet": "∙",
        "oplus": "⊕", "ominus": "⊖", "otimes": "⊗", "odot": "⊙", "leq": "≤", "le": "≤", "geq": "≥", "ge": "≥", "neq": "≠",
        "ne": "≠", "approx": "≈", "equiv": "≡", "sim": "∼", "simeq": "≃", "cong": "≅", "propto": "∝", "ll": "≪", "gg": "≫",
        "subset": "⊂", "supset": "⊃", "subseteq": "⊆", "supseteq": "⊇", "in": "∈", "notin": "∉", "ni": "∋", "cup": "∪",
        "cap": "∩", "setminus": "∖", "land": "∧", "wedge": "∧", "lor": "∨", "vee": "∨", "neg": "¬", "lnot": "¬",
        "forall": "∀", "exists": "∃", "nexists": "∄", "to": "→", "rightarrow": "→", "leftarrow": "←", "Rightarrow": "⇒",
        "Leftarrow": "⇐", "leftrightarrow": "↔", "Leftrightarrow": "⇔", "mapsto": "↦", "longrightarrow": "⟶",
        "uparrow": "↑", "downarrow": "↓", "perp": "⊥", "parallel": "∥", "angle": "∠", "therefore": "∴", "because": "∵",
        "mid": "∣", "nmid": "∤", "vdash": "⊢", "models": "⊨", "langle": "⟨", "rangle": "⟩", "lceil": "⌈", "rceil": "⌉",
        "lfloor": "⌊", "rfloor": "⌋", "cdots": "⋯", "ldots": "…", "dots": "…", "vdots": "⋮", "ddots": "⋱", "prime": "′",
        "degree": "°", "colon": ":", "lvert": "|", "rvert": "|", "lVert": "‖", "rVert": "‖", "vert": "|", "Vert": "‖",
        "implies": "⟹", "iff": "⟺", "hookrightarrow": "↪", "nearrow": "↗", "searrow": "↘", "top": "⊤", "bot": "⊥",
        "sqcup": "⊔", "sqcap": "⊓", "triangle": "△", "square": "□", "diamond": "⋄", "leadsto": "⇝",
    ]
    static let largeOperators: [String: String] = [
        "sum": "∑", "prod": "∏", "coprod": "∐", "bigcup": "⋃", "bigcap": "⋂", "bigoplus": "⨁", "bigotimes": "⨂",
        "bigvee": "⋁", "bigwedge": "⋀", "lim": "lim", "limsup": "lim sup", "liminf": "lim inf", "max": "max", "min": "min",
        "sup": "sup", "inf": "inf", "argmax": "arg max", "argmin": "arg min",
    ]
    static let integrals: [String: String] = ["int": "∫", "iint": "∬", "iiint": "∭", "oint": "∮"]
    static let functions: Set<String> = [
        "sin", "cos", "tan", "cot", "sec", "csc", "arcsin", "arccos", "arctan", "sinh", "cosh", "tanh", "coth", "log", "ln",
        "lg", "exp", "det", "gcd", "deg", "arg", "dim", "ker", "hom", "Pr", "mod",
    ]

    struct Atom { var xml: String; var largeOp = false }

    struct Parser {
        let c: [Character]
        var i = 0
        init(_ s: String) { c = Array(s) }

        mutating func skipSpaces() { while i < c.count, c[i].isWhitespace { i += 1 } }

        func peekCommandName() -> String? {
            guard i < c.count, c[i] == "\\" else { return nil }
            var j = i + 1
            var name = ""
            while j < c.count, c[j].isLetter { name.append(c[j]); j += 1 }
            return name
        }

        mutating func parseSequence(terminator: Character?, stopAtRight: Bool) -> [String] {
            var out: [String] = []
            while i < c.count {
                let ch = c[i]
                if let t = terminator, ch == t { return out }
                if ch == "}" || ch == "&" || ch.isWhitespace { i += 1; continue }
                if ch == "\\" {
                    let name = peekCommandName() ?? ""
                    if stopAtRight && name == "right" { return out }
                    if name == "end" { return out }
                    if i + 1 < c.count, c[i + 1] == "\\" { i += 2; continue }
                }
                var atom = parseAtom()
                atom = parseScripts(atom)
                out.append(atom.xml)
            }
            return out
        }

        mutating func parseAtom() -> Atom {
            let ch = c[i]
            if ch == "{" {
                i += 1
                let inner = parseSequence(terminator: "}", stopAtRight: false)
                if i < c.count, c[i] == "}" { i += 1 }
                return Atom(xml: mrow(inner))
            }
            if ch == "\\" { return parseCommand() }
            if ch.isNumber {
                var s = ""
                while i < c.count, c[i].isNumber || (c[i] == "." && i + 1 < c.count && c[i + 1].isNumber) { s.append(c[i]); i += 1 }
                return Atom(xml: "<mn>\(s)</mn>")
            }
            if ch.isLetter { i += 1; return Atom(xml: "<mi>\(ch)</mi>") }
            i += 1
            switch ch {
            case "-": return Atom(xml: "<mo>−</mo>")
            case "*": return Atom(xml: "<mo>∗</mo>")
            case "'": return Atom(xml: "<mo>′</mo>")
            case "<": return Atom(xml: "<mo>&lt;</mo>")
            case ">": return Atom(xml: "<mo>&gt;</mo>")
            case "(", ")", "[", "]", "|": return Atom(xml: "<mo stretchy=\"false\">\(esc(ch))</mo>")
            case "~": return Atom(xml: "<mspace width=\"0.35em\"/>")
            default: return Atom(xml: "<mo>\(esc(ch))</mo>")
            }
        }

        mutating func parseScripts(_ base: Atom) -> Atom {
            var sub: String? = nil, sup: String? = nil
            while i < c.count, c[i] == "^" || c[i] == "_" {
                let which = c[i]
                i += 1
                let arg = parseArgument()
                if which == "^" { sup = arg } else { sub = arg }
            }
            guard sub != nil || sup != nil else { return base }
            if base.largeOp {
                switch (sub, sup) {
                case let (s?, p?): return Atom(xml: "<munderover>\(base.xml)\(s)\(p)</munderover>")
                case let (s?, nil): return Atom(xml: "<munder>\(base.xml)\(s)</munder>")
                case let (nil, p?): return Atom(xml: "<mover>\(base.xml)\(p)</mover>")
                default: return base
                }
            }
            switch (sub, sup) {
            case let (s?, p?): return Atom(xml: "<msubsup>\(base.xml)\(s)\(p)</msubsup>")
            case let (s?, nil): return Atom(xml: "<msub>\(base.xml)\(s)</msub>")
            case let (nil, p?): return Atom(xml: "<msup>\(base.xml)\(p)</msup>")
            default: return base
            }
        }

        mutating func parseArgument() -> String {
            skipSpaces()
            guard i < c.count else { return "<mrow></mrow>" }
            if c[i] == "{" {
                i += 1
                let inner = parseSequence(terminator: "}", stopAtRight: false)
                if i < c.count, c[i] == "}" { i += 1 }
                return mrow(inner)
            }
            if c[i] == "\\" { return parseCommand().xml }
            let ch = c[i]
            i += 1
            if ch.isNumber { return "<mn>\(ch)</mn>" }
            if ch.isLetter { return "<mi>\(ch)</mi>" }
            if ch == "-" { return "<mo>−</mo>" }
            return "<mo>\(esc(ch))</mo>"
        }

        mutating func parseRawGroup() -> String {
            skipSpaces()
            guard i < c.count else { return "" }
            if c[i] != "{" { let ch = c[i]; i += 1; return String(ch) }
            i += 1
            var depth = 1
            var s = ""
            while i < c.count {
                let ch = c[i]
                i += 1
                if ch == "{" { depth += 1 } else if ch == "}" { depth -= 1; if depth == 0 { break } }
                s.append(ch)
            }
            return s
        }

        mutating func parseCommandNameOrChar() -> String {
            i += 1
            guard i < c.count else { return "" }
            if !c[i].isLetter { let ch = c[i]; i += 1; return String(ch) }
            var name = ""
            while i < c.count, c[i].isLetter { name.append(c[i]); i += 1 }
            return name
        }

        mutating func parseDelimiter() -> String {
            skipSpaces()
            guard i < c.count else { return "" }
            if c[i] == "\\" {
                let name = parseCommandNameOrChar()
                switch name {
                case "{": return "{"
                case "}": return "}"
                case "|", "Vert", "lVert", "rVert": return "‖"
                case "vert", "lvert", "rvert": return "|"
                case "langle": return "⟨"
                case "rangle": return "⟩"
                case "lceil": return "⌈"
                case "rceil": return "⌉"
                case "lfloor": return "⌊"
                case "rfloor": return "⌋"
                default: return ""
                }
            }
            let ch = c[i]
            i += 1
            if ch == "." { return "" }
            return esc(ch)
        }

        mutating func accent(_ mark: String, stretchy: Bool = false) -> Atom {
            let arg = parseArgument()
            return Atom(xml: "<mover accent=\"true\">\(arg)<mo\(stretchy ? "" : " stretchy=\"false\"")>\(mark)</mo></mover>")
        }

        mutating func styled(_ variant: String) -> Atom {
            Atom(xml: "<mstyle mathvariant=\"\(variant)\">\(parseArgument())</mstyle>")
        }

        mutating func parseCommand() -> Atom {
            let name = parseCommandNameOrChar()
            switch name {
            case "frac", "dfrac", "tfrac":
                let n = parseArgument(); let d = parseArgument()
                return Atom(xml: "<mfrac>\(n)\(d)</mfrac>")
            case "binom":
                let n = parseArgument(); let d = parseArgument()
                return Atom(xml: "<mrow><mo>(</mo><mfrac linethickness=\"0\">\(n)\(d)</mfrac><mo>)</mo></mrow>")
            case "sqrt":
                skipSpaces()
                if i < c.count, c[i] == "[" {
                    i += 1
                    let idx = parseSequence(terminator: "]", stopAtRight: false)
                    if i < c.count { i += 1 }
                    let body = parseArgument()
                    return Atom(xml: "<mroot>\(body)\(mrow(idx))</mroot>")
                }
                return Atom(xml: "<msqrt>\(parseArgument())</msqrt>")
            case "text", "textrm", "mbox", "textit", "textbf", "textnormal":
                return Atom(xml: "<mtext>\(esc(parseRawGroup()))</mtext>")
            case "mathrm", "operatorname":
                return Atom(xml: "<mi mathvariant=\"normal\">\(esc(parseRawGroup()))</mi>")
            case "mathbf": return styled("bold")
            case "boldsymbol", "bm": return styled("bold-italic")
            case "mathit": return styled("italic")
            case "mathcal": return styled("script")
            case "mathbb": return styled("double-struck")
            case "mathfrak": return styled("fraktur")
            case "mathsf": return styled("sans-serif")
            case "mathtt": return styled("monospace")
            case "vec": return accent("→")
            case "overrightarrow": return accent("→", stretchy: true)
            case "hat": return accent("ˆ")
            case "widehat": return accent("ˆ", stretchy: true)
            case "bar": return accent("¯")
            case "overline": return accent("‾", stretchy: true)
            case "dot": return accent("˙")
            case "ddot": return accent("¨")
            case "tilde": return accent("˜")
            case "widetilde": return accent("˜", stretchy: true)
            case "underline":
                return Atom(xml: "<munder accentunder=\"true\">\(parseArgument())<mo>‾</mo></munder>")
            case "underbrace":
                return Atom(xml: "<munder accentunder=\"true\">\(parseArgument())<mo>⏟</mo></munder>")
            case "overbrace":
                return Atom(xml: "<mover accent=\"true\">\(parseArgument())<mo>⏞</mo></mover>")
            case "left":
                let open = parseDelimiter()
                let inner = parseSequence(terminator: nil, stopAtRight: true)
                var close = ""
                if peekCommandName() == "right" { _ = parseCommandNameOrChar(); close = parseDelimiter() }
                return Atom(xml: "<mrow><mo>\(open)</mo>\(mrow(inner))<mo>\(close)</mo></mrow>")
            case "right":
                _ = parseDelimiter()
                return Atom(xml: "")
            case "begin": return parseEnvironment()
            case "end":
                _ = parseRawGroup()
                return Atom(xml: "")
            case "quad": return Atom(xml: "<mspace width=\"1em\"/>")
            case "qquad": return Atom(xml: "<mspace width=\"2em\"/>")
            case ",": return Atom(xml: "<mspace width=\"0.17em\"/>")
            case ":": return Atom(xml: "<mspace width=\"0.22em\"/>")
            case ";": return Atom(xml: "<mspace width=\"0.28em\"/>")
            case "!": return Atom(xml: "<mspace width=\"-0.17em\"/>")
            case " ": return Atom(xml: "<mspace width=\"0.35em\"/>")
            case "{": return Atom(xml: "<mo>{</mo>")
            case "}": return Atom(xml: "<mo>}</mo>")
            case "|": return Atom(xml: "<mo>‖</mo>")
            case "%", "#", "$", "_", "&": return Atom(xml: "<mo>\(esc(name))</mo>")
            case "displaystyle", "textstyle", "scriptstyle", "limits", "nolimits", "nonumber", "cr", "over", "notag":
                return Atom(xml: "")
            case "not":
                skipSpaces()
                if let next = peekCommandName(), !next.isEmpty {
                    _ = parseCommandNameOrChar()
                    switch next {
                    case "in": return Atom(xml: "<mo>∉</mo>")
                    case "equiv": return Atom(xml: "<mo>≢</mo>")
                    case "subset": return Atom(xml: "<mo>⊄</mo>")
                    case "subseteq": return Atom(xml: "<mo>⊈</mo>")
                    case "exists": return Atom(xml: "<mo>∄</mo>")
                    default: return Atom(xml: "<mo>¬</mo><mo>\(LaTeXToMathML.operators[next] ?? next)</mo>")
                    }
                }
                if i < c.count, c[i] == "=" { i += 1; return Atom(xml: "<mo>≠</mo>") }
                return Atom(xml: "<mo>¬</mo>")
            default:
                if let s = LaTeXToMathML.identifiers[name] { return Atom(xml: "<mi>\(s)</mi>") }
                if let s = LaTeXToMathML.uprightIdentifiers[name] { return Atom(xml: "<mi mathvariant=\"normal\">\(s)</mi>") }
                if let s = LaTeXToMathML.operators[name] { return Atom(xml: "<mo>\(s)</mo>") }
                if let s = LaTeXToMathML.largeOperators[name] { return Atom(xml: "<mo>\(s)</mo>", largeOp: true) }
                if let s = LaTeXToMathML.integrals[name] { return Atom(xml: "<mo>\(s)</mo>") }
                if LaTeXToMathML.functions.contains(name) { return Atom(xml: "<mi>\(name)</mi><mo>&#x2061;</mo>") }
                return Atom(xml: "<mtext>\\\(esc(name))</mtext>")
            }
        }

        mutating func parseEnvironment() -> Atom {
            let env = parseRawGroup()
            var rows: [[String]] = [[]]
            var cell: [String] = []
            func pushCell() { rows[rows.count - 1].append(mrow(cell)); cell = [] }
            while i < c.count {
                let ch = c[i]
                if ch.isWhitespace { i += 1; continue }
                if ch == "&" { i += 1; pushCell(); continue }
                if ch == "\\" {
                    if i + 1 < c.count, c[i + 1] == "\\" { i += 2; pushCell(); rows.append([]); continue }
                    let name = peekCommandName() ?? ""
                    if name == "end" { _ = parseCommandNameOrChar(); _ = parseRawGroup(); break }
                    if name == "hline" { _ = parseCommandNameOrChar(); continue }
                }
                if ch == "}" { i += 1; continue }
                var atom = parseAtom()
                atom = parseScripts(atom)
                cell.append(atom.xml)
            }
            if !cell.isEmpty { pushCell() }
            if rows.last?.isEmpty == true { rows.removeLast() }
            let align = (env == "cases" || env.hasPrefix("align")) ? " columnalign=\"left\"" : ""
            let table = "<mtable\(align)>" + rows.map { "<mtr>" + $0.map { "<mtd>\($0)</mtd>" }.joined() + "</mtr>" }.joined() + "</mtable>"
            switch env {
            case "pmatrix": return Atom(xml: "<mrow><mo>(</mo>\(table)<mo>)</mo></mrow>")
            case "bmatrix": return Atom(xml: "<mrow><mo>[</mo>\(table)<mo>]</mo></mrow>")
            case "Bmatrix": return Atom(xml: "<mrow><mo>{</mo>\(table)<mo>}</mo></mrow>")
            case "vmatrix": return Atom(xml: "<mrow><mo>|</mo>\(table)<mo>|</mo></mrow>")
            case "Vmatrix": return Atom(xml: "<mrow><mo>‖</mo>\(table)<mo>‖</mo></mrow>")
            case "cases": return Atom(xml: "<mrow><mo>{</mo>\(table)</mrow>")
            default: return Atom(xml: table)
            }
        }
    }
}

// MARK: - Renderer (offscreen WebKit → PNG at 2x)

final class EquationRenderer: NSObject, WKNavigationDelegate {
    static let shared = EquationRenderer()

    struct Result {
        let png: Data
        let image: NSImage
        let size: NSSize
        let baselineDrop: CGFloat
    }

    private let web: WKWebView
    private let window: NSWindow
    private var queue: [(html: String, completion: (Result?) -> Void)] = []
    private var busy = false
    private var current: ((Result?) -> Void)?
    private var timeout: DispatchWorkItem?

    private override init() {
        let cfg = WKWebViewConfiguration()
        web = WKWebView(frame: NSRect(x: 0, y: 0, width: 1400, height: 400), configuration: cfg)
        web.setValue(false, forKey: "drawsBackground")
        window = NSWindow(contentRect: web.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = web
        super.init()
        web.navigationDelegate = self
    }

    static func html(for latex: String, display: Bool, fontSize: CGFloat) -> String {
        let math = LaTeXToMathML.convert(latex, display: display)
        return """
        <!doctype html><html><head><meta charset="utf-8"><style>
        html,body{margin:0;padding:0;background:transparent}
        #wrap{display:inline-block;padding:3px 4px;font-family:'STIX Two Math','Latin Modern Math','Cambria Math',serif;font-size:\(fontSize)px;color:#000;line-height:normal;white-space:nowrap}
        math{font-family:inherit}
        #bl{display:inline-block;width:0;height:0}
        </style></head><body><span id="wrap">\(math)<span id="bl"></span></span></body></html>
        """
    }

    func render(latex: String, display: Bool, fontSize: CGFloat, completion: @escaping (Result?) -> Void) {
        let trimmed = latex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { completion(nil); return }
        queue.append((Self.html(for: trimmed, display: display, fontSize: fontSize), completion))
        pump()
    }

    /// Blocks the caller (spinning the run loop) until the equation is rendered. For tests and imports.
    func renderSync(latex: String, display: Bool, fontSize: CGFloat, timeout seconds: TimeInterval = 5) -> Result? {
        var result: Result? = nil
        var done = false
        render(latex: latex, display: display, fontSize: fontSize) { r in result = r; done = true }
        let deadline = Date().addingTimeInterval(seconds)
        while !done && Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
        return result
    }

    private func pump() {
        guard !busy, !queue.isEmpty else { return }
        let next = queue.removeFirst()
        busy = true
        current = next.completion
        web.frame = NSRect(x: 0, y: 0, width: 1400, height: 400)
        window.setContentSize(web.frame.size)
        let t = DispatchWorkItem { [weak self] in self?.finish(nil) }
        timeout = t
        DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: t)
        web.loadHTMLString(next.html, baseURL: nil)
    }

    private func finish(_ r: Result?) {
        timeout?.cancel()
        timeout = nil
        busy = false
        let c = current
        current = nil
        c?(r)
        pump()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let js = "(function(){var w=document.getElementById('wrap').getBoundingClientRect();var b=document.getElementById('bl').getBoundingClientRect();return [Math.ceil(w.width), Math.ceil(w.height), Math.max(0, Math.round(w.bottom - b.bottom))];})()"
        webView.evaluateJavaScript(js) { [weak self] value, _ in
            guard let self else { return }
            guard let arr = value as? [Double], arr.count == 3, arr[0] > 0, arr[1] > 0 else { self.finish(nil); return }
            let size = NSSize(width: arr[0], height: arr[1])
            let baseline = CGFloat(arr[2])
            webView.frame = NSRect(origin: .zero, size: size)
            self.window.setContentSize(size)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                let cfg = WKSnapshotConfiguration()
                cfg.snapshotWidth = NSNumber(value: Int(size.width * 2))
                webView.takeSnapshot(with: cfg) { image, _ in
                    guard let image, let png = Self.alphaMask(from: image) else { self.finish(nil); return }
                    let img = NSImage(data: png) ?? image
                    img.isTemplate = true
                    self.finish(Result(png: png, image: img, size: size, baselineDrop: baseline))
                }
            }
        }
    }

    /// Turns the snapshot (black glyphs on a not-quite-transparent backdrop) into a pure alpha mask:
    /// alpha = darkness, colour = black. Cells tint it with the text colour when drawing.
    static func alphaMask(from image: NSImage) -> Data? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let w = cg.width, h = cg.height
        guard w > 0, h > 0, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let bytesPerRow = w * 4
        var buf = [UInt8](repeating: 0, count: bytesPerRow * h)
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        let drawn: Bool = buf.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: space, bitmapInfo: info) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return nil }
        var i = 0
        while i < buf.count {
            let a = Int(buf[i + 3])
            let lum = (Int(buf[i]) + Int(buf[i + 1]) + Int(buf[i + 2])) / 3   // premultiplied
            let dark = max(0, a - lum)
            buf[i] = 0; buf[i + 1] = 0; buf[i + 2] = 0; buf[i + 3] = UInt8(dark)
            i += 4
        }
        let out: CGImage? = buf.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: space, bitmapInfo: info) else { return nil }
            return ctx.makeImage()
        }
        guard let masked = out else { return nil }
        return NSBitmapImageRep(cgImage: masked).representation(using: .png, properties: [:])
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finish(nil) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { finish(nil) }
}
