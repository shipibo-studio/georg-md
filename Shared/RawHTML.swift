import Foundation

/// Subconjunto seguro de HTML permitido dentro del Markdown (típico de README).
/// Lista blanca de etiquetas y atributos; todo lo demás se muestra como texto escapado.
/// Nunca pasan: scripts, estilos, manejadores on*, iframes, formularios, atributos style/class/id.
enum RawHTML {
    private static let allowed: Set<String> = [
        "b", "strong", "i", "em", "u", "s", "del", "ins", "mark", "kbd", "code", "sub", "sup", "small", "br", "hr",
        "p", "div", "span", "a", "img", "details", "summary", "h1", "h2", "h3", "h4", "h5", "h6", "ul", "ol", "li",
        "blockquote", "pre", "table", "thead", "tbody", "tr", "th", "td", "caption", "picture", "center"
    ]
    private static let dropped: Set<String> = ["source", "track"]
    private static let voidTags: Set<String> = ["br", "hr", "img"]

    private static let tagRE = try! NSRegularExpression(pattern: #"<(/?)([A-Za-z][A-Za-z0-9]*)([^<>]*)>"#)
    private static let attrRE = try! NSRegularExpression(
        pattern: #"([A-Za-z][A-Za-z0-9\-:]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+))"#)
    private static let commentRE = try! NSRegularExpression(pattern: "<!--.*?-->", options: [.dotMatchesLineSeparators])

    private static func attributes(_ s: String) -> [String: String] {
        let ns = s as NSString
        var out: [String: String] = [:]
        for m in attrRE.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            let name = ns.substring(with: m.range(at: 1)).lowercased()
            var value = ""
            for g in 2...4 where m.range(at: g).location != NSNotFound { value = ns.substring(with: m.range(at: g)) }
            out[name] = value.replacingOccurrences(of: "&amp;", with: "&")
        }
        // Atributo booleano sin valor: <details open>
        if s.range(of: #"(?i)(^|\s)open(\s|$)"#, options: .regularExpression) != nil, out["open"] == nil { out["open"] = "" }
        return out
    }

    /// Orígenes de <img src=…> presentes en el HTML (para precargarlos).
    static func imageSources(in raw: String) -> [String] {
        let ns = raw as NSString
        var out: [String] = []
        for m in tagRE.matches(in: raw, range: NSRange(location: 0, length: ns.length)) {
            guard ns.substring(with: m.range(at: 1)).isEmpty,
                  ns.substring(with: m.range(at: 2)).lowercased() == "img" else { continue }
            if let src = attributes(ns.substring(with: m.range(at: 3)))["src"], !src.isEmpty { out.append(src) }
        }
        return out
    }

    static func sanitize(_ raw: String, images: [String: String]) -> String {
        let cleaned = commentRE.stringByReplacingMatches(
            in: raw, range: NSRange(location: 0, length: (raw as NSString).length), withTemplate: "")
        let c = cleaned as NSString
        var out = ""
        var last = 0
        for m in tagRE.matches(in: cleaned, range: NSRange(location: 0, length: c.length)) {
            out += HTMLRenderer.escape(c.substring(with: NSRange(location: last, length: m.range.location - last)))
            last = m.range.location + m.range.length
            let closing = c.substring(with: m.range(at: 1)) == "/"
            let name = c.substring(with: m.range(at: 2)).lowercased()
            if dropped.contains(name) { continue }
            guard allowed.contains(name) else {
                out += HTMLRenderer.escape(c.substring(with: m.range))
                continue
            }
            if closing {
                if !voidTags.contains(name) { out += "</\(name == "center" ? "div" : name)>" }
            } else {
                out += openTag(name, attributes(c.substring(with: m.range(at: 3))), images)
            }
        }
        out += HTMLRenderer.escape(c.substring(from: last))
        return out
    }

    private static func digits(_ v: String?) -> String? {
        guard let v, !v.isEmpty, v.count <= 4, v.allSatisfy(\.isNumber) else { return nil }
        return v
    }

    private static func openTag(_ name: String, _ a: [String: String], _ images: [String: String]) -> String {
        switch name {
        case "img":
            let alt = HTMLRenderer.escape(a["alt"] ?? "")
            guard let src = a["src"], let uri = images[src] else {
                return "<span class=\"img\">▣ \(alt.isEmpty ? "image" : alt)</span>"
            }
            var attrs = ""
            if let w = digits(a["width"]) { attrs += " width=\"\(w)\"" }
            if let h = digits(a["height"]) { attrs += " height=\"\(h)\"" }
            return "<img src=\"\(uri)\" alt=\"\(alt)\"\(attrs)>"
        case "a":
            guard let href = HTMLRenderer.safeURL(a["href"]) else { return "<a>" }
            return "<a href=\"\(HTMLRenderer.escape(href))\">"
        case "center":
            return "<div style=\"text-align:center\">"
        case "p", "div", "h1", "h2", "h3", "h4", "h5", "h6", "th", "td":
            var attrs = ""
            if let al = a["align"]?.lowercased(), ["left", "center", "right"].contains(al) {
                attrs += " style=\"text-align:\(al)\""
            }
            if name == "th" || name == "td" {
                if let cs = digits(a["colspan"]) { attrs += " colspan=\"\(cs)\"" }
                if let rs = digits(a["rowspan"]) { attrs += " rowspan=\"\(rs)\"" }
            }
            return "<\(name)\(attrs)>"
        case "details":
            return a["open"] != nil ? "<details open>" : "<details>"
        case "br", "hr":
            return "<\(name)>"
        default:
            return "<\(name)>"
        }
    }
}
