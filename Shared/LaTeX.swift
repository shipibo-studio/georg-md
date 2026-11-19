import Foundation

/// Converts a subset of LaTeX to MathML (rendered natively by WebKit, without JavaScript).
/// Security: the output is built only from fixed tags and escaped text; size and depth limits.
enum LaTeX {
    static func mathML(_ src: String, display: Bool) -> String {
        var p = Parser(toks: tokenize(String(src.prefix(4000))))
        let body = p.sequence(until: { _ in false })
        return "<math xmlns=\"http://www.w3.org/1998/Math/MathML\" display=\"\(display ? "block" : "inline")\"><mrow>\(body)</mrow></math>"
    }

    static func tokenize(_ s: String) -> [String] {
        let c = Array(s)
        var t: [String] = []
        var i = 0
        while i < c.count {
            let ch = c[i]
            if ch == "\\" {
                if i + 1 < c.count {
                    if c[i + 1].isLetter {
                        var j = i + 1
                        while j < c.count && c[j].isLetter { j += 1 }
                        t.append(String(c[i..<j])); i = j
                    } else {
                        t.append(String(c[i...i + 1])); i += 2
                    }
                } else { i += 1 }
            } else if ch.isWhitespace {
                if t.last != " " { t.append(" ") }
                i += 1
            } else {
                t.append(String(ch)); i += 1
            }
        }
        return t
    }

    static func esc(_ s: String) -> String { HTMLRenderer.escape(s) }

    // MARK: Symbol tables

    static let greek: [String: String] = [
        "\\alpha": "α", "\\beta": "β", "\\gamma": "γ", "\\delta": "δ", "\\epsilon": "ϵ", "\\varepsilon": "ε",
        "\\zeta": "ζ", "\\eta": "η", "\\theta": "θ", "\\vartheta": "ϑ", "\\iota": "ι", "\\kappa": "κ",
        "\\lambda": "λ", "\\mu": "μ", "\\nu": "ν", "\\xi": "ξ", "\\pi": "π", "\\varpi": "ϖ", "\\rho": "ρ",
        "\\varrho": "ϱ", "\\sigma": "σ", "\\varsigma": "ς", "\\tau": "τ", "\\upsilon": "υ", "\\phi": "ϕ",
        "\\varphi": "φ", "\\chi": "χ", "\\psi": "ψ", "\\omega": "ω",
        "\\Gamma": "Γ", "\\Delta": "Δ", "\\Theta": "Θ", "\\Lambda": "Λ", "\\Xi": "Ξ", "\\Pi": "Π",
        "\\Sigma": "Σ", "\\Upsilon": "Υ", "\\Phi": "Φ", "\\Psi": "Ψ", "\\Omega": "Ω",
        "\\ell": "ℓ", "\\hbar": "ℏ", "\\aleph": "ℵ", "\\Re": "ℜ", "\\Im": "ℑ", "\\emptyset": "∅", "\\varnothing": "∅"
    ]

    static let ops: [String: String] = [
        "\\cdot": "⋅", "\\times": "×", "\\div": "÷", "\\pm": "±", "\\mp": "∓", "\\ast": "∗", "\\star": "⋆",
        "\\circ": "∘", "\\bullet": "∙", "\\oplus": "⊕", "\\otimes": "⊗", "\\leq": "≤", "\\le": "≤",
        "\\geq": "≥", "\\ge": "≥", "\\neq": "≠", "\\ne": "≠", "\\approx": "≈", "\\equiv": "≡", "\\sim": "∼",
        "\\simeq": "≃", "\\cong": "≅", "\\propto": "∝", "\\ll": "≪", "\\gg": "≫", "\\infty": "∞",
        "\\partial": "∂", "\\nabla": "∇", "\\in": "∈", "\\notin": "∉", "\\ni": "∋", "\\subset": "⊂",
        "\\subseteq": "⊆", "\\supset": "⊃", "\\supseteq": "⊇", "\\cup": "∪", "\\cap": "∩",
        "\\setminus": "∖", "\\forall": "∀", "\\exists": "∃", "\\neg": "¬", "\\lnot": "¬", "\\land": "∧",
        "\\wedge": "∧", "\\lor": "∨", "\\vee": "∨", "\\to": "→", "\\rightarrow": "→", "\\leftarrow": "←",
        "\\gets": "←", "\\leftrightarrow": "↔", "\\Rightarrow": "⇒", "\\Leftarrow": "⇐",
        "\\Leftrightarrow": "⇔", "\\implies": "⟹", "\\iff": "⟺", "\\mapsto": "↦", "\\uparrow": "↑",
        "\\downarrow": "↓", "\\ldots": "…", "\\dots": "…", "\\cdots": "⋯", "\\vdots": "⋮", "\\ddots": "⋱",
        "\\perp": "⟂", "\\parallel": "∥", "\\angle": "∠", "\\triangle": "△", "\\therefore": "∴",
        "\\because": "∵", "\\prime": "′", "\\degree": "°", "\\langle": "⟨", "\\rangle": "⟩",
        "\\lfloor": "⌊", "\\rfloor": "⌋", "\\lceil": "⌈", "\\rceil": "⌉", "\\vert": "|", "\\Vert": "‖",
        "\\|": "‖", "\\{": "{", "\\}": "}", "\\lbrace": "{", "\\rbrace": "}", "\\%": "%", "\\&": "&",
        "\\#": "#", "\\_": "_", "\\$": "$", "\\mid": "∣", "\\nmid": "∤"
    ]

    /// Large operators: (symbol, limits above/below).
    static let bigOps: [String: (String, Bool)] = [
        "\\sum": ("∑", true), "\\prod": ("∏", true), "\\coprod": ("∐", true),
        "\\bigcup": ("⋃", true), "\\bigcap": ("⋂", true), "\\bigoplus": ("⨁", true),
        "\\bigotimes": ("⨂", true), "\\bigvee": ("⋁", true), "\\bigwedge": ("⋀", true),
        "\\int": ("∫", false), "\\iint": ("∬", false), "\\iiint": ("∭", false), "\\oint": ("∮", false)
    ]

    /// Named functions; true if their limits go below.
    static let funcs: [String: Bool] = [
        "sin": false, "cos": false, "tan": false, "cot": false, "sec": false, "csc": false,
        "arcsin": false, "arccos": false, "arctan": false, "sinh": false, "cosh": false, "tanh": false,
        "log": false, "ln": false, "lg": false, "exp": false, "dim": false, "ker": false, "deg": false,
        "arg": false, "hom": false, "Pr": true, "det": true, "gcd": true, "lim": true, "max": true,
        "min": true, "sup": true, "inf": true, "limsup": true, "liminf": true
    ]

    static let spaces: [String: String] = [
        "\\,": "0.17em", "\\:": "0.22em", "\\;": "0.28em", "\\ ": "0.28em", "\\quad": "1em",
        "\\qquad": "2em", "\\!": "-0.17em"
    ]

    static let accents: [String: String] = [
        "\\hat": "^", "\\widehat": "^", "\\bar": "‾", "\\overline": "‾", "\\vec": "→", "\\dot": "˙",
        "\\ddot": "¨", "\\tilde": "~", "\\widetilde": "~", "\\overrightarrow": "→"
    ]

    static let blackboard: [Character: String] = [
        "R": "ℝ", "N": "ℕ", "Z": "ℤ", "Q": "ℚ", "C": "ℂ", "P": "ℙ", "H": "ℍ"
    ]

    static let variants: [String: String] = [
        "\\mathrm": "normal", "\\operatorname": "normal", "\\mathit": "italic", "\\mathbf": "bold",
        "\\boldsymbol": "bold", "\\bm": "bold", "\\mathsf": "sans-serif", "\\mathtt": "monospace",
        "\\mathcal": "script", "\\mathscr": "script", "\\mathfrak": "fraktur", "\\mathbb": "double-struck"
    ]

    // MARK: Parser

    private struct Atom {
        var ml: String
        var limits = false
    }

    private struct Parser {
        let toks: [String]
        var i = 0
        var depth = 0

        init(toks: [String]) { self.toks = toks }

        mutating func skipSpaces() { while i < toks.count && toks[i] == " " { i += 1 } }

        mutating func sequence(until stop: (String) -> Bool) -> String {
            var out = ""
            while true {
                skipSpaces()
                guard i < toks.count, !stop(toks[i]) else { break }
                out += scripted()
            }
            return out
        }

        mutating func scripted() -> String {
            let base = atom()
            var sub: String?
            var sup: String?
            var primes = ""
            while true {
                skipSpaces()
                guard i < toks.count else { break }
                if toks[i] == "^" { i += 1; sup = arg() }
                else if toks[i] == "_" { i += 1; sub = arg() }
                else if toks[i] == "'" { i += 1; primes += "′" }
                else { break }
            }
            if !primes.isEmpty { sup = "<mrow><mo>\(primes)</mo>\(sup ?? "")</mrow>" }
            switch (sub, sup) {
            case (nil, nil): return base.ml
            case (let b?, nil): return base.limits ? "<munder>\(base.ml)\(b)</munder>" : "<msub>\(base.ml)\(b)</msub>"
            case (nil, let p?): return base.limits ? "<mover>\(base.ml)\(p)</mover>" : "<msup>\(base.ml)\(p)</msup>"
            case (let b?, let p?):
                return base.limits ? "<munderover>\(base.ml)\(b)\(p)</munderover>" : "<msubsup>\(base.ml)\(b)\(p)</msubsup>"
            }
        }

        mutating func arg() -> String {
            skipSpaces()
            guard i < toks.count else { return "<mrow></mrow>" }
            if toks[i] == "{" { return "<mrow>\(group())</mrow>" }
            return atom().ml
        }

        /// At "{": consumes up to the matching "}".
        mutating func group() -> String {
            i += 1
            depth += 1
            defer { depth -= 1 }
            let body = sequence(until: { $0 == "}" })
            if i < toks.count, toks[i] == "}" { i += 1 }
            return body
        }

        mutating func rawGroup() -> String {
            skipSpaces()
            guard i < toks.count else { return "" }
            if toks[i] != "{" { let t = toks[i]; i += 1; return t.hasPrefix("\\") ? String(t.dropFirst()) : t }
            i += 1
            var d = 1
            var s = ""
            while i < toks.count {
                let t = toks[i]; i += 1
                if t == "{" { d += 1 }
                else if t == "}" { d -= 1; if d == 0 { break } }
                s += (t.hasPrefix("\\") && t.count > 1) ? String(t.dropFirst()) : t
            }
            return s
        }

        mutating func delim() -> String {
            guard i < toks.count else { return "" }
            let t = toks[i]; i += 1
            if t == "." { return "" }
            if let o = LaTeX.ops[t] { return o }
            return t.hasPrefix("\\") ? "" : LaTeX.esc(t)
        }

        mutating func atom() -> Atom {
            skipSpaces()
            guard i < toks.count, depth < 40 else { i = toks.count; return Atom(ml: "") }
            let t = toks[i]; i += 1
            switch t {
            case "{":
                i -= 1
                return Atom(ml: "<mrow>\(group())</mrow>")
            case "\\left":
                skipSpaces()
                let open = delim()
                depth += 1
                let body = sequence(until: { $0 == "\\right" })
                depth -= 1
                var close = ""
                if i < toks.count { i += 1; skipSpaces(); close = delim() }
                let o = open.isEmpty ? "" : "<mo fence=\"true\">\(open)</mo>"
                let c = close.isEmpty ? "" : "<mo fence=\"true\">\(close)</mo>"
                return Atom(ml: "<mrow>\(o)\(body)\(c)</mrow>")
            case "\\frac", "\\dfrac", "\\tfrac":
                let a = arg(), b = arg()
                return Atom(ml: "<mfrac>\(a)\(b)</mfrac>")
            case "\\binom":
                let a = arg(), b = arg()
                return Atom(ml: "<mrow><mo>(</mo><mfrac linethickness=\"0\">\(a)\(b)</mfrac><mo>)</mo></mrow>")
            case "\\sqrt":
                skipSpaces()
                if i < toks.count, toks[i] == "[" {
                    i += 1
                    let idx = sequence(until: { $0 == "]" })
                    if i < toks.count { i += 1 }
                    let x = arg()
                    return Atom(ml: "<mroot>\(x)<mrow>\(idx)</mrow></mroot>")
                }
                return Atom(ml: "<msqrt>\(arg())</msqrt>")
            case "\\text", "\\textrm", "\\textit", "\\textbf", "\\mbox":
                return Atom(ml: "<mtext>\(LaTeX.esc(rawGroup()))</mtext>")
            case "\\begin":
                return Atom(ml: environment(rawGroup()))
            case "\\underline":
                return Atom(ml: "<munder>\(arg())<mo>_</mo></munder>")
            case "\\\\", "\\end", "\\right", "&":
                return Atom(ml: "")
            default:
                break
            }
            if let variant = LaTeX.variants[t] {
                let raw = rawGroup()
                if variant == "double-struck", raw.count == 1, let m = LaTeX.blackboard[raw.first!] {
                    return Atom(ml: "<mi>\(m)</mi>")
                }
                return Atom(ml: "<mi mathvariant=\"\(variant)\">\(LaTeX.esc(raw))</mi>")
            }
            if let acc = LaTeX.accents[t] {
                return Atom(ml: "<mover accent=\"true\">\(arg())<mo>\(acc)</mo></mover>")
            }
            if let w = LaTeX.spaces[t] { return Atom(ml: "<mspace width=\"\(w)\"></mspace>") }
            if let g = LaTeX.greek[t] { return Atom(ml: "<mi>\(g)</mi>") }
            if let big = LaTeX.bigOps[t] { return Atom(ml: "<mo>\(big.0)</mo>", limits: big.1) }
            if let o = LaTeX.ops[t] { return Atom(ml: "<mo>\(LaTeX.esc(o))</mo>") }
            if t.hasPrefix("\\") {
                let name = String(t.dropFirst())
                if let lim = LaTeX.funcs[name] {
                    // U+2061 (function application) leaves the thin space between "sin" and its argument.
                    return Atom(ml: "<mi mathvariant=\"normal\">\(name)</mi>" + (lim ? "" : "<mo>\u{2061}</mo>"), limits: lim)
                }
                return Atom(ml: "<mi mathvariant=\"normal\">\(LaTeX.esc(name))</mi>")
            }
            guard let ch = t.first else { return Atom(ml: "") }
            if ch.isNumber {
                var s = t
                while i < toks.count {
                    let nx = toks[i]
                    if let f = nx.first, f.isNumber { s += nx; i += 1 }
                    else if nx == ".", i + 1 < toks.count, let f = toks[i + 1].first, f.isNumber { s += "."; i += 1 }
                    else { break }
                }
                return Atom(ml: "<mn>\(LaTeX.esc(s))</mn>")
            }
            if ch.isLetter { return Atom(ml: "<mi>\(LaTeX.esc(t))</mi>") }
            switch t {
            case "-": return Atom(ml: "<mo>−</mo>")
            case "*": return Atom(ml: "<mo>∗</mo>")
            default: return Atom(ml: "<mo>\(LaTeX.esc(t))</mo>")
            }
        }

        mutating func environment(_ name: String) -> String {
            if name == "array" { _ = rawGroup() }
            depth += 1
            defer { depth -= 1 }
            var rows: [[String]] = []
            var cur: [String] = []
            while true {
                let c = sequence(until: { $0 == "&" || $0 == "\\\\" || $0 == "\\end" })
                cur.append("<mtd>\(c)</mtd>")
                if i >= toks.count { break }
                let t = toks[i]; i += 1
                if t == "&" { continue }
                if t == "\\\\" { rows.append(cur); cur = []; continue }
                if t == "\\end" { _ = rawGroup(); break }
            }
            if !(cur.count == 1 && cur[0] == "<mtd></mtd>") { rows.append(cur) }
            let body = rows.prefix(60).map { "<mtr>\($0.prefix(30).joined())</mtr>" }.joined()
            let align: String
            switch name {
            case "cases": align = "left left"
            case "aligned", "align", "align*", "split", "alignedat": align = "right left"
            default: align = "center"
            }
            let table = "<mtable columnalign=\"\(align)\" columnspacing=\"1em\" rowspacing=\"0.4em\">\(body)</mtable>"
            switch name {
            case "pmatrix": return "<mrow><mo>(</mo>\(table)<mo>)</mo></mrow>"
            case "bmatrix": return "<mrow><mo>[</mo>\(table)<mo>]</mo></mrow>"
            case "Bmatrix": return "<mrow><mo>{</mo>\(table)<mo>}</mo></mrow>"
            case "vmatrix": return "<mrow><mo>|</mo>\(table)<mo>|</mo></mrow>"
            case "Vmatrix": return "<mrow><mo>‖</mo>\(table)<mo>‖</mo></mrow>"
            case "cases": return "<mrow><mo>{</mo>\(table)</mrow>"
            default: return table
            }
        }
    }
}

/// Pulls the formulas out of the Markdown before parsing (respecting code) and reinserts them afterwards.
enum MathExtractor {
    typealias Item = (display: Bool, src: String)

    static func extract(_ md: String) -> (String, [Item]) {
        let c = Array(md)
        let n = c.count
        var out = ""
        var maths: [Item] = []
        var i = 0

        func token(_ display: Bool, _ src: String) -> String {
            maths.append((display, src))
            return "\u{E000}\(display ? "B" : "I")\(maths.count - 1)\u{E001}"
        }
        func fence(at k: Int) -> String? {
            var j = k, sp = 0
            while j < n && c[j] == " " && sp < 3 { j += 1; sp += 1 }
            guard j + 3 <= n else { return nil }
            let head = String(c[j..<j + 3])
            return (head == "```" || head == "~~~") ? head : nil
        }

        while i < n {
            let ch = c[i]

            if i == 0 || c[i - 1] == "\n", let f = fence(at: i) {
                var j = i
                var first = true
                while j < n {
                    var e = j
                    while e < n && c[e] != "\n" { e += 1 }
                    let line = String(c[j..<e])
                    out += line
                    if e < n { out += "\n" }
                    j = min(n, e + 1)
                    if !first, line.trimmingCharacters(in: .whitespaces).hasPrefix(f) { break }
                    first = false
                }
                i = j; continue
            }
            if ch == "`" {
                var run = 0
                while i + run < n && c[i + run] == "`" { run += 1 }
                var j = i + run
                var found = -1
                while j < n {
                    if c[j] == "`" {
                        var r = 0
                        while j + r < n && c[j + r] == "`" { r += 1 }
                        if r == run { found = j + r; break }
                        j += r
                    } else { j += 1 }
                }
                if found > 0 { out += String(c[i..<found]); i = found }
                else { out += String(c[i..<i + run]); i += run }
                continue
            }
            if ch == "\\", i + 1 < n {
                out.append(ch); out.append(c[i + 1]); i += 2; continue
            }
            if ch == "$", maths.count < 500 {
                if i + 1 < n, c[i + 1] == "$" {
                    var j = i + 2
                    var found = -1
                    while j + 1 < n, j - i < 5000 {
                        if c[j] == "$" && c[j + 1] == "$" { found = j; break }
                        j += 1
                    }
                    if found >= 0 {
                        out += "\n\n" + token(true, String(c[i + 2..<found])) + "\n\n"
                        i = found + 2; continue
                    }
                } else {
                    var j = i + 1
                    var found = -1
                    while j < n && c[j] != "\n" && j - i < 500 {
                        if c[j] == "\\" { j += 2; continue }
                        if c[j] == "$" { found = j; break }
                        j += 1
                    }
                    if found > i + 1 {
                        let body = c[i + 1..<found]
                        let nextDigit = found + 1 < n && c[found + 1].isNumber
                        if !body.first!.isWhitespace, !body.last!.isWhitespace, !nextDigit {
                            out += token(false, String(body))
                            i = found + 1; continue
                        }
                    }
                }
            }
            out.append(ch); i += 1
        }
        return (out, maths)
    }

    static func restore(_ html: String, _ maths: [Item]) -> String {
        var h = html
        for (idx, m) in maths.enumerated() {
            let tok = "\u{E000}\(m.display ? "B" : "I")\(idx)\u{E001}"
            let ml = LaTeX.mathML(m.src, display: m.display)
            if m.display {
                let div = "<div class=\"math\">\(ml)</div>"
                h = h.replacingOccurrences(of: "<p>\(tok)</p>", with: div)
                h = h.replacingOccurrences(of: tok, with: div)
            } else {
                h = h.replacingOccurrences(of: tok, with: "<span class=\"math-inline\">\(ml)</span>")
            }
        }
        return h
    }
}
