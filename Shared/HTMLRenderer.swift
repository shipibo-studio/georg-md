import Foundation
import Markdown

/// Convierte el AST de swift-markdown a HTML.
/// Seguridad: todo texto se escapa, el HTML crudo del documento nunca se emite
/// (se muestra como texto) y los destinos de enlace pasan por una lista de esquemas permitidos.
struct HTMLRenderer: MarkupVisitor {
    typealias Result = String

    /// Imágenes ya resueltas a URIs data: (origen original -> URI).
    var images: [String: String] = [:]

    static func escape(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for c in s {
            switch c {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&#39;"
            default: out.append(c)
            }
        }
        return out
    }

    /// Solo http(s), mailto y enlaces relativos/anclas. Bloquea javascript:, data:, file:, etc.
    static func safeURL(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let stripped = trimmed.filter { !$0.isWhitespace && !$0.asciiValue.map { $0 < 0x20 }.orFalse }
        if let colon = stripped.firstIndex(of: ":") {
            let scheme = stripped[..<colon].lowercased()
            // Un ':' tras '/', '?' o '#' no es esquema.
            if !scheme.contains("/"), !scheme.contains("?"), !scheme.contains("#") {
                guard ["http", "https", "mailto"].contains(scheme) else { return nil }
            }
        }
        return trimmed
    }

    private mutating func children(_ m: Markup) -> String {
        var out = ""
        for child in m.children { out += visit(child) }
        return out
    }

    mutating func defaultVisit(_ markup: Markup) -> String { children(markup) }

    mutating func visitDocument(_ d: Document) -> String { children(d) }

    mutating func visitHeading(_ h: Heading) -> String {
        let l = min(max(h.level, 1), 6)
        return "<h\(l)>\(children(h))</h\(l)>\n"
    }

    mutating func visitParagraph(_ p: Paragraph) -> String { "<p>\(children(p))</p>\n" }

    mutating func visitText(_ t: Text) -> String { Self.escape(t.string) }

    mutating func visitEmphasis(_ e: Emphasis) -> String { "<em>\(children(e))</em>" }

    mutating func visitStrong(_ s: Strong) -> String { "<strong>\(children(s))</strong>" }

    mutating func visitStrikethrough(_ s: Strikethrough) -> String { "<del>\(children(s))</del>" }

    mutating func visitInlineCode(_ c: InlineCode) -> String { "<code>\(Self.escape(c.code))</code>" }

    mutating func visitCodeBlock(_ c: CodeBlock) -> String {
        let lang = (c.language ?? "").filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "+" || $0 == "#" }
        let label = lang.isEmpty ? "" : "<span class=\"lang\">\(Self.escape(lang))</span>"
        let first = String((c.language ?? "").split(separator: " ").first ?? "")
        var code = c.code
        if code.hasSuffix("\n") { code.removeLast() }
        return "<pre>\(label)<code>\(Highlighter.html(code, lang: first))</code></pre>\n"
    }

    static func alertKind(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespaces).lowercased()
        return ["note", "tip", "important", "warning", "caution"].first { t == "[!\($0)]" }
    }

    /// Avisos de GitHub: `> [!NOTE]`, `[!TIP]`, `[!IMPORTANT]`, `[!WARNING]`, `[!CAUTION]`.
    mutating func visitBlockQuote(_ b: BlockQuote) -> String {
        // Ojo: `children` es solo Sequence; `children.first` resolvería al método `first(where:)` y el cast fallaría siempre.
        if b.childCount > 0, let first = b.child(at: 0) as? Paragraph {
            let kids = Array(first.children)
            var acc = ""
            var consumed = 0
            var kind: String?
            for child in kids {
                guard let t = child as? Text else { break }
                acc += t.string
                consumed += 1
                if let k = Self.alertKind(acc) { kind = k; break }
                if acc.count > 14 { break }
            }
            if let kind {
                var inner = ""
                var skipped = false
                for child in kids.dropFirst(consumed) {
                    if !skipped, child is SoftBreak || child is LineBreak { skipped = true; continue }
                    skipped = true
                    inner += visit(child)
                }
                var rest = ""
                for child in b.children.dropFirst() { rest += visit(child) }
                let body = inner.isEmpty ? "" : "<p>\(inner)</p>"
                return "<div class=\"alert \(kind)\"><p class=\"alert-title\">\(kind.capitalized)</p>\(body)\(rest)</div>\n"
            }
        }
        return "<blockquote>\(children(b))</blockquote>\n"
    }

    mutating func visitThematicBreak(_ t: ThematicBreak) -> String { "<hr>\n" }

    mutating func visitSoftBreak(_ s: SoftBreak) -> String { "\n" }

    mutating func visitLineBreak(_ l: LineBreak) -> String { "<br>\n" }

    mutating func visitUnorderedList(_ l: UnorderedList) -> String { "<ul>\n\(children(l))</ul>\n" }

    mutating func visitOrderedList(_ l: OrderedList) -> String {
        let start = l.startIndex == 1 ? "" : " start=\"\(l.startIndex)\""
        return "<ol\(start)>\n\(children(l))</ol>\n"
    }

    mutating func visitListItem(_ i: ListItem) -> String {
        var box = ""
        var cls = ""
        if let cb = i.checkbox {
            cls = " class=\"task\""
            box = cb == .checked ? "<span class=\"box on\">✓</span>" : "<span class=\"box\"></span>"
        }
        return "<li\(cls)>\(box)\(children(i))</li>\n"
    }

    mutating func visitLink(_ l: Link) -> String {
        let inner = children(l)
        guard let url = Self.safeURL(l.destination) else { return inner }
        return "<a href=\"\(Self.escape(url))\">\(inner)</a>"
    }

    mutating func visitImage(_ i: Image) -> String {
        let alt = Self.escape(i.plainText)
        if let src = i.source, let uri = images[src] { return "<img src=\"\(uri)\" alt=\"\(alt)\">" }
        return "<span class=\"img\">▣ \(alt.isEmpty ? "image" : alt)</span>"
    }

    mutating func visitInlineHTML(_ h: InlineHTML) -> String { RawHTML.sanitize(h.rawHTML, images: images) }

    mutating func visitHTMLBlock(_ h: HTMLBlock) -> String { RawHTML.sanitize(h.rawHTML, images: images) + "\n" }

    mutating func visitTable(_ t: Table) -> String {
        let aligns = t.columnAlignments
        func cell(_ c: Table.Cell, _ tag: String, _ idx: Int) -> String {
            var r = self
            let style: String
            if idx < aligns.count, let a = aligns[idx] {
                switch a {
                case .left: style = " style=\"text-align:left\""
                case .center: style = " style=\"text-align:center\""
                case .right: style = " style=\"text-align:right\""
                }
            } else { style = "" }
            return "<\(tag)\(style)>\(r.children(c))</\(tag)>"
        }
        var out = "<div class=\"table-wrap\"><table>\n<thead><tr>"
        for (i, c) in t.head.cells.enumerated() { out += cell(c, "th", i) }
        out += "</tr></thead>\n<tbody>\n"
        for row in t.body.rows {
            out += "<tr>"
            for (i, c) in row.cells.enumerated() { out += cell(c, "td", i) }
            out += "</tr>\n"
        }
        return out + "</tbody></table></div>\n"
    }
}

private extension Optional where Wrapped == Bool {
    var orFalse: Bool { self ?? false }
}
