import AppKit
import Markdown

// Modo "Escribir": estilo del Markdown en vivo sobre un NSTextStorage, a partir del AST de swift-markdown.
// El texto nunca se modifica al estilar: solo cambian atributos. Los marcadores (#, **, `, [](…)) se marcan
// con .mdMarker y la vista los oculta (glifo nulo) fuera de la línea activa.

extension NSAttributedString.Key {
    /// Rango de marcador Markdown (se revela en la línea activa).
    static let mdMarker = NSAttributedString.Key("georg.md.marker")
    /// Marcador oculto: el layout manager genera glifos nulos (ancho cero, sin dibujo).
    static let mdHidden = NSAttributedString.Key("georg.md.hidden")
    /// Decoración que dibuja la vista: "bullet", "box", "boxOn", "hr", "code", "quote:<nivel>:<#color>".
    static let mdDeco = NSAttributedString.Key("georg.md.deco")
    /// Destino de un enlace (String). Se abre solo con ⌘-clic y solo si es http/https/mailto.
    static let mdLink = NSAttributedString.Key("georg.md.link")
}

/// Convierte posiciones de swift-markdown (línea y columna en bytes UTF-8, base 1) a offsets UTF-16 de NSString.
struct SourceMap {
    private var starts: [Int] = []
    private var lengths: [Int] = []
    private var lines: [Substring] = []
    private var ascii: [Bool] = []
    let length: Int

    init(_ text: String) {
        var offset = 0
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let u16 = line.utf16.count
            starts.append(offset)
            lengths.append(u16)
            lines.append(line)
            ascii.append(line.utf8.count == u16 && line.utf8.allSatisfy { $0 < 0x80 })
            offset += u16 + 1
        }
        length = (text as NSString).length
    }

    func offset(_ loc: SourceLocation) -> Int {
        let li = loc.line - 1
        guard li >= 0 else { return 0 }
        guard li < starts.count else { return length }
        let col = max(0, loc.column - 1)
        let inLine: Int
        if ascii[li] {
            inLine = min(col, lengths[li])
        } else {
            let line = lines[li]
            let u8 = line.utf8
            let idx = u8.index(u8.startIndex, offsetBy: col, limitedBy: u8.endIndex) ?? u8.endIndex
            inLine = min(line.utf16.distance(from: line.startIndex, to: idx), lengths[li])
        }
        return min(starts[li] + inLine, length)
    }

    func range(_ r: SourceRange?) -> NSRange? {
        guard let r else { return nil }
        let a = offset(r.lowerBound), b = offset(r.upperBound)
        return b >= a ? NSRange(location: a, length: b - a) : nil
    }
}

/// Métricas y atributos derivados de la paleta.
struct LiveStyle {
    let p: Palette
    var fonts = FontSettings()
    var size: CGFloat { fonts.size }

    func font(mono: Bool, size: CGFloat, weight: CGFloat = 400) -> NSFont { fonts.font(mono: mono, size: size, weight: weight) }
    var codeSize: CGFloat { (size * 0.86).rounded() }
    var indentStep: CGFloat { 18 }

    func color(_ hex: String) -> NSColor { NSColor(hex: hex) }

    var bodyParagraph: NSParagraphStyle {
        let ps = NSMutableParagraphStyle()
        ps.lineHeightMultiple = 1.22
        ps.paragraphSpacing = 2
        return ps
    }

    var base: [NSAttributedString.Key: Any] {
        [.font: font(mono: false, size: size), .foregroundColor: color(p.fg), .paragraphStyle: bodyParagraph]
    }

    func headingSize(_ level: Int) -> CGFloat {
        switch level { case 1: size * 1.9; case 2: size * 1.42; case 3: size * 1.18; default: size }
    }
}

enum LiveStyler {
    /// Por encima de este tamaño el modo Escribir muestra texto plano (sin parseo ni estilos).
    static let maxStyled = 300_000

    struct Block: Equatable {
        let kind: String
        let range: NSRange
    }

    /// Firma estructural del documento: bloques de nivel superior y todos los nodos (tipo + rango + datos
    /// que afectan el estilo). Sirve para decidir si basta re-estilar el bloque editado.
    struct Signature: Equatable {
        var blocks: [Block] = []
        var nodes: [Block] = []
    }

    struct Parsed {
        let document: Document
        let map: SourceMap
        let signature: Signature
        let frontMatter: NSRange?
        /// Bloques de nivel superior con su extensión real (cmark a veces deja hijos fuera del rango del padre).
        let topLevel: [(node: Markup, range: NSRange)]
        /// Documento con anidamiento patológico: se muestra como texto plano (no se parsea).
        var plain = false
        var blocks: [Block] { signature.blocks }
    }

    // MARK: Parseo

    static func parse(_ text: String) -> Parsed {
        let ns = text as NSString
        if ns.length > maxStyled || MarkdownLimits.exceedsNesting(text) {
            var p = Parsed(document: Document(), map: SourceMap(""), signature: Signature(), frontMatter: nil, topLevel: [])
            p.plain = true
            return p
        }
        let fm = frontMatterRange(ns)
        var source = text
        if let fm {
            // El front matter se reemplaza por líneas vacías: así el parser no lo toma por título setext
            // y la numeración de líneas del resto del documento no cambia.
            let lines = ns.substring(with: fm).components(separatedBy: "\n").count
            source = String(repeating: "\n", count: max(0, lines - 1)) + ns.substring(from: NSMaxRange(fm))
        }
        let doc = Document(parsing: source)
        let map = SourceMap(text)
        var sig = Signature()
        if let fm { sig.blocks.append(Block(kind: "FrontMatter", range: fm)); sig.nodes.append(sig.blocks[0]) }
        var top: [(Markup, NSRange)] = []
        for child in doc.children {
            if let r = collect(child, map, &sig.nodes) {
                sig.blocks.append(Block(kind: String(describing: type(of: child)), range: r))
                top.append((child, r))
            }
        }
        return Parsed(document: doc, map: map, signature: sig, frontMatter: fm, topLevel: top)
    }

    /// Agrega el nodo y sus descendientes a `out`; devuelve la unión de sus rangos.
    @discardableResult
    private static func collect(_ m: Markup, _ map: SourceMap, _ out: inout [Block]) -> NSRange? {
        var extent = map.range(m.range)
        if let r = extent {
            var kind = String(describing: type(of: m))
            switch m {
            case let l as Link: kind += "|" + (l.destination ?? "")
            case let h as Heading: kind += "|\(h.level)"
            case let i as ListItem: kind += "|\(String(describing: i.checkbox))"
            case let c as CodeBlock: kind += "|" + (c.language ?? "")
            default: break
            }
            out.append(Block(kind: kind, range: r))
        }
        for child in m.children {
            if let r = collect(child, map, &out) { extent = extent.map { NSUnionRange($0, r) } ?? r }
        }
        return extent
    }

    /// Bloque YAML inicial `---` … `---` (mismas reglas que HTMLPage).
    static func frontMatterRange(_ ns: NSString) -> NSRange? {
        guard ns.hasPrefix("---\n") || ns.hasPrefix("---\r\n") else { return nil }
        var loc = ns.lineRange(for: NSRange(location: 0, length: 0)).length
        while loc < ns.length {
            let line = ns.lineRange(for: NSRange(location: loc, length: 0))
            let content = ns.substring(with: line).trimmingCharacters(in: .whitespacesAndNewlines)
            if content == "---" { return NSRange(location: 0, length: NSMaxRange(line)) }
            loc = NSMaxRange(line)
        }
        return nil
    }

    /// Región mínima a re-estilar tras una edición, o nil si la estructura cambió fuera del bloque editado.
    /// `edit` = rango reemplazado (en el texto anterior) y largo del texto nuevo.
    /// Fuera del bloque editado nada puede cambiar de tipo ni de rango: si cambia (subrayado setext, definición
    /// de referencia, continuación perezosa, fence que se abre…), se re-estila todo.
    static func dirtyRegion(old: Signature, new: Signature, edit: NSRange, newLength: Int, textLength: Int) -> NSRange? {
        let delta = newLength - edit.length
        let oldEnd = NSMaxRange(edit), newEnd = edit.location + newLength
        func prefix(_ a: [Block]) -> [Block] { a.filter { NSMaxRange($0.range) < edit.location } }
        func oldSuffix(_ a: [Block]) -> [Block] {
            a.filter { $0.range.location > oldEnd }
                .map { Block(kind: $0.kind, range: NSRange(location: $0.range.location + delta, length: $0.range.length)) }
        }
        func newSuffix(_ a: [Block]) -> [Block] { a.filter { $0.range.location > newEnd } }
        guard prefix(old.nodes) == prefix(new.nodes), oldSuffix(old.nodes) == newSuffix(new.nodes) else { return nil }
        let newPrefix = prefix(new.blocks), newSuffix = newSuffix(new.blocks)
        guard prefix(old.blocks) == newPrefix, oldSuffix(old.blocks) == newSuffix else { return nil }
        var start = newPrefix.last.map { NSMaxRange($0.range) } ?? 0
        var end = newSuffix.first?.range.location ?? textLength
        // Los bloques intermedios (viejos y nuevos) pueden extenderse sobre zonas que no cambiaron:
        // la región debe cubrir también lo que antes estilaban.
        func toNew(_ x: Int) -> Int { x <= edit.location ? x : (x >= oldEnd ? x + delta : newEnd) }
        for b in old.blocks where !(NSMaxRange(b.range) < edit.location) && !(b.range.location > oldEnd) {
            start = min(start, toNew(b.range.location)); end = max(end, toNew(NSMaxRange(b.range)))
        }
        for b in new.blocks where !(NSMaxRange(b.range) < edit.location) && !(b.range.location > newEnd) {
            start = min(start, b.range.location); end = max(end, NSMaxRange(b.range))
        }
        start = max(0, start); end = min(textLength, end)
        return end >= start ? NSRange(location: start, length: end - start) : nil
    }

    // MARK: Estilo

    /// Aplica estilos en `region` (líneas completas). Llamar entre beginEditing/endEditing.
    static func apply(to storage: NSTextStorage, parsed: Parsed, region: NSRange, style: LiveStyle) {
        let ns = storage.string as NSString
        var region = ns.lineRange(for: clamp(region, ns.length))
        guard ns.length <= maxStyled, !parsed.plain else {
            storage.setAttributes(style.base, range: NSRange(location: 0, length: ns.length))
            return
        }
        // Los bloques que tocan la región se re-estilan completos, así que la región se amplía a ellos
        // antes de reiniciar atributos (algunas reglas dependen del atributo previo, p. ej. el tamaño de fuente).
        var targets: [Markup] = []
        // Iterar hasta estabilizar: ampliar la región puede alcanzar otro bloque que comparte línea.
        var changed = true
        var taken = Set<Int>()
        var withFront = false
        if let fm = parsed.frontMatter, NSIntersectionRange(fm, region).length > 0 || fm.location == region.location {
            withFront = true
            region = NSUnionRange(region, fm)
        }
        while changed {
            changed = false
            for (i, item) in parsed.topLevel.enumerated() where !taken.contains(i) {
                let lines = ns.lineRange(for: item.range)
                if NSIntersectionRange(lines, region).length > 0 || (region.length == 0 && lines.location == region.location) {
                    taken.insert(i)
                    region = NSUnionRange(region, lines)
                    changed = true
                }
            }
        }
        targets = taken.sorted().map { parsed.topLevel[$0].node }
        storage.setAttributes(style.base, range: region)
        let w = Walker(storage: storage, ns: ns, str: storage.string, map: parsed.map, s: style)
        if withFront, let fm = parsed.frontMatter { w.frontMatter(fm) }
        for child in targets { w.visit(child, quote: 0) }
    }

    /// Oculta los marcadores de `region` salvo los que tocan `active`.
    static func conceal(_ storage: NSTextStorage, in region: NSRange, active: NSRange) {
        let region = clamp(region, storage.length)
        guard region.length > 0 else { return }
        storage.removeAttribute(.mdHidden, range: region)
        storage.enumerateAttribute(.mdMarker, in: region) { v, r, _ in
            guard v != nil else { return }
            let touches = NSIntersectionRange(r, active).length > 0
                || (active.length == 0 && active.location >= r.location && active.location <= NSMaxRange(r))
            if !touches { storage.addAttribute(.mdHidden, value: true, range: r) }
        }
    }

    static func clamp(_ r: NSRange, _ len: Int) -> NSRange {
        let loc = min(max(0, r.location), len)
        return NSRange(location: loc, length: min(max(0, r.length), len - loc))
    }
}

// MARK: - Recorrido del AST

private struct Walker {
    let storage: NSTextStorage
    let ns: NSString
    /// Copia única del texto para las expresiones regulares (puentear NSMutableString a String copia todo).
    let str: String
    let map: SourceMap
    let s: LiveStyle

    private static let mathRE = try! NSRegularExpression(pattern: #"\$\$[^$]+\$\$|\$[^$\s][^$\n]*?\$"#)
    private static let closingHashRE = try! NSRegularExpression(pattern: #"[ \t]+#+[ \t]*$"#)
    private static let quotePrefixRE = try! NSRegularExpression(pattern: #"^(?:[ \t]{0,3}>[ \t]?)+"#)

    func range(_ m: Markup) -> NSRange? { map.range(m.range) }

    // Utilidades -----------------------------------------------------------

    func add(_ attrs: [NSAttributedString.Key: Any], _ r: NSRange) {
        let r = LiveStyler.clamp(r, ns.length)
        if r.length > 0 { storage.addAttributes(attrs, range: r) }
    }

    /// Marcador: color atenuado y ocultable. Nunca incluye saltos de línea (ocultarlos uniría líneas).
    func marker(_ r: NSRange) {
        var r = LiveStyler.clamp(r, ns.length)
        while r.length > 0, isNewline(ns.character(at: NSMaxRange(r) - 1)) { r.length -= 1 }
        guard r.length > 0 else { return }
        if ns.substring(with: r).contains(where: { $0 == "\n" || $0 == "\r" }) {
            // Rango multilínea: se marca por líneas.
            var loc = r.location
            while loc < NSMaxRange(r) {
                let line = ns.lineRange(for: NSRange(location: loc, length: 0))
                marker(NSIntersectionRange(line, r))
                loc = NSMaxRange(line)
            }
            return
        }
        add([.mdMarker: true, .foregroundColor: s.color(s.p.muted), .underlineStyle: 0, .strikethroughStyle: 0], r)
    }

    func isNewline(_ c: unichar) -> Bool { c == 10 || c == 13 }

    /// Rango del contenido de una línea (sin el salto final).
    func lineContent(_ line: NSRange) -> NSRange {
        var r = line
        while r.length > 0, isNewline(ns.character(at: NSMaxRange(r) - 1)) { r.length -= 1 }
        return r
    }

    func lines(_ r: NSRange) -> [NSRange] {
        var out: [NSRange] = []
        let full = ns.lineRange(for: r)
        var loc = full.location
        while loc < NSMaxRange(full) {
            let line = ns.lineRange(for: NSRange(location: loc, length: 0))
            out.append(line)
            loc = NSMaxRange(line)
        }
        if out.isEmpty { out.append(full) }
        return out
    }

    /// Cambia el peso de todas las fuentes del rango, conservando tamaño y familia.
    func setWeight(_ weight: CGFloat, _ r: NSRange) {
        let r = LiveStyler.clamp(r, ns.length)
        guard r.length > 0 else { return }
        storage.enumerateAttribute(.font, in: r) { v, sub, _ in
            let f = (v as? NSFont) ?? s.font(mono: false, size: s.size)
            storage.addAttribute(.font, value: s.font(mono: f.isFixedPitch, size: f.pointSize, weight: weight), range: sub)
        }
    }

    func setParagraph(_ ps: NSParagraphStyle, _ r: NSRange) { add([.paragraphStyle: ps], ns.lineRange(for: r)) }

    /// Oculta los delimitadores de un nodo en línea: desde su inicio hasta el primer hijo y desde el último hijo al final.
    func delimiters(_ m: Markup, _ r: NSRange) {
        let kids = Array(m.children).compactMap { range($0) }
        guard let first = kids.first, let last = kids.last else { return }
        marker(NSRange(location: r.location, length: max(0, first.location - r.location)))
        marker(NSRange(location: NSMaxRange(last), length: max(0, NSMaxRange(r) - NSMaxRange(last))))
    }

    func run(of ch: unichar, at loc: Int, max limit: Int) -> Int {
        var n = 0
        while loc + n < ns.length, n < limit, ns.character(at: loc + n) == ch { n += 1 }
        return n
    }

    // Bloques ----------------------------------------------------------------

    func frontMatter(_ r: NSRange) {
        add([.font: s.font(mono: true, size: s.codeSize * 0.92), .foregroundColor: s.color(s.p.muted)], r)
    }

    func visit(_ m: Markup, quote: Int) {
        guard let r = range(m) else { return }
        switch m {
        case let h as Heading: heading(h, r)
        case let b as BlockQuote: blockQuote(b, r, depth: quote + 1)
        case let item as ListItem: listItem(item, r, quote: quote)
        case let c as CodeBlock: codeBlock(c, r)
        case is ThematicBreak:
            let line = lineContent(ns.lineRange(for: NSRange(location: r.location, length: 0)))
            marker(line)
            add([.mdDeco: "hr"], line)
        case let t as Table: table(t, r)
        case is HTMLBlock:
            add([.font: s.font(mono: true, size: s.codeSize), .foregroundColor: s.color(s.p.muted)], r)
        case is Paragraph:
            inline(m, r)
        default:
            for child in m.children { visit(child, quote: quote) }
        }
    }

    func heading(_ h: Heading, _ r: NSRange) {
        let level = min(max(h.level, 1), 6)
        let size = s.headingSize(level)
        let weight: CGFloat = level <= 2 ? 700 : 650
        let ps = NSMutableParagraphStyle()
        ps.lineHeightMultiple = 1.05
        ps.paragraphSpacingBefore = level <= 2 ? 10 : 6
        ps.paragraphSpacing = 4
        let lineSet = lines(r)
        setParagraph(ps, r)
        add([.font: s.font(mono: false, size: size, weight: weight),
             .foregroundColor: s.color(level >= 4 ? s.p.muted : s.p.fg)], r)
        let first = lineContent(lineSet[0])
        let hashes = run(of: 35 /* # */, at: first.location, max: 6)
        if hashes > 0 {
            var n = hashes
            while first.location + n < NSMaxRange(first), [32, 9].contains(ns.character(at: first.location + n)) { n += 1 }
            marker(NSRange(location: first.location, length: n))
            if let m = Self.closingHashRE.firstMatch(in: str, range: first) { marker(m.range) }
        } else if lineSet.count > 1 {
            // Setext: la línea de subrayado (=== o ---) es marcador.
            let underLine = lineSet[lineSet.count - 1]
            let under = lineContent(underLine)
            if NSIntersectionRange(under, r).length > 0 {
                // Oculto, el subrayado deja una línea vacía: se reduce a una altura discreta.
                add([.font: s.font(mono: false, size: s.size * 0.75)], underLine)
                marker(under)
            }
        }
        inline(h, r)
    }

    func blockQuote(_ b: BlockQuote, _ r: NSRange, depth: Int) {
        var barColor = s.p.bar
        // Avisos de GitHub (> [!NOTE] …): título en color y en negrita.
        if b.childCount > 0, let para = b.child(at: 0) as? Paragraph, para.childCount > 0,
           let t = para.child(at: 0) as? Markdown.Text, let kind = HTMLRenderer.alertKind(t.string), let tr = range(t) {
            barColor = Self.alertColor(kind)
            add([.foregroundColor: s.color(barColor)], tr)
            setWeight(650, tr)
        }
        let ps = NSMutableParagraphStyle()
        ps.setParagraphStyle(s.bodyParagraph)
        ps.firstLineHeadIndent = CGFloat(depth) * s.indentStep
        ps.headIndent = ps.firstLineHeadIndent
        setParagraph(ps, r)
        add([.foregroundColor: s.color(s.p.muted), .mdDeco: "quote:\(depth):\(barColor)"], ns.lineRange(for: r))
        for line in lines(r) {
            let content = lineContent(line)
            if let m = Self.quotePrefixRE.firstMatch(in: str, range: content) { marker(m.range) }
        }
        for child in b.children { visit(child, quote: depth) }
        // El título del aviso se repinta después de los hijos (que reponen el color atenuado).
        if barColor != s.p.bar, let para = b.child(at: 0) as? Paragraph, let t = para.child(at: 0), let tr = range(t) {
            add([.foregroundColor: s.color(barColor)], tr)
        }
    }

    static func alertColor(_ kind: String) -> String {
        switch kind { case "tip": "#3fa468"; case "important": "#9a6cf0"; case "warning": "#d19a2a"; case "caution": "#e0614f"; default: "#4c8bf5" }
    }

    func listItem(_ item: ListItem, _ r: NSRange, quote: Int) {
        let firstLine = lineContent(ns.lineRange(for: NSRange(location: r.location, length: 0)))
        let contentStart = (item.childCount > 0 ? item.child(at: 0).flatMap { range($0) }?.location : nil) ?? NSMaxRange(firstLine)
        let prefix = NSRange(location: r.location, length: max(0, min(contentStart, NSMaxRange(firstLine)) - r.location))
        let clear = NSColor.clear

        let ch = r.location < ns.length ? ns.character(at: r.location) : 0
        let bullet = ch == 45 || ch == 42 || ch == 43 // - * +
        if let cb = item.checkbox {
            // "- [ ] ": el guion queda invisible (conserva su ancho) y la casilla se dibuja sobre "[ ]".
            let pre = ns.substring(with: prefix) as NSString
            let open = pre.range(of: "[")
            if bullet { add([.foregroundColor: clear], NSRange(location: r.location, length: 1)) }
            else if open.location != NSNotFound { add([.foregroundColor: s.color(s.p.muted)], NSRange(location: r.location, length: open.location)) }
            if open.location != NSNotFound {
                let box = NSRange(location: prefix.location + open.location, length: 3)
                add([.foregroundColor: clear, .mdDeco: cb == .checked ? "boxOn" : "box",
                     .font: s.font(mono: true, size: (s.size * 0.8).rounded())], box)
            }
            if cb == .checked, item.childCount > 0, let first = item.child(at: 0).flatMap({ range($0) }) {
                add([.foregroundColor: s.color(s.p.muted)], first)
            }
        } else if bullet {
            add([.foregroundColor: clear, .mdDeco: "bullet"], NSRange(location: r.location, length: 1))
        } else {
            add([.foregroundColor: s.color(s.p.muted)], prefix)
        }

        // Sangría colgante: las líneas que continúan se alinean con el texto, no con el marcador.
        let font = s.font(mono: false, size: s.size)
        let lineStart = ns.lineRange(for: NSRange(location: r.location, length: 0)).location
        let lead = ns.substring(with: NSRange(location: lineStart, length: NSMaxRange(prefix) - lineStart))
        let width = (lead as NSString).size(withAttributes: [.font: font]).width
        let ps = NSMutableParagraphStyle()
        ps.setParagraphStyle(s.bodyParagraph)
        ps.firstLineHeadIndent = CGFloat(quote) * s.indentStep
        ps.headIndent = ps.firstLineHeadIndent + width
        ps.paragraphSpacing = 3
        setParagraph(ps, r)

        for child in item.children { visit(child, quote: quote) }
    }

    func codeBlock(_ c: CodeBlock, _ r: NSRange) {
        let full = ns.lineRange(for: r)
        let ps = NSMutableParagraphStyle()
        ps.lineHeightMultiple = 1.3
        ps.firstLineHeadIndent = 18
        ps.headIndent = 18
        ps.tailIndent = -18
        let mono = s.font(mono: true, size: s.codeSize)
        add([.font: mono, .foregroundColor: s.color(s.p.fg), .paragraphStyle: ps, .mdDeco: "code", .ligature: 0], full)

        let ls = lines(r)
        let firstText = ns.substring(with: lineContent(ls[0])).trimmingCharacters(in: .whitespaces)
        var body = full
        if firstText.hasPrefix("```") || firstText.hasPrefix("~~~") {
            let small = s.font(mono: true, size: s.codeSize * 0.85)
            let open = lineContent(ls[0])
            add([.font: small], open)
            marker(open)
            body = NSRange(location: NSMaxRange(ls[0]), length: max(0, NSMaxRange(full) - NSMaxRange(ls[0])))
            if ls.count > 1 {
                let lastLine = lineContent(ls[ls.count - 1])
                let t = ns.substring(with: lastLine).trimmingCharacters(in: .whitespaces)
                if t.hasPrefix(String(firstText.prefix(3))) {
                    add([.font: small], lastLine)
                    marker(lastLine)
                    body.length = max(0, lastLine.location - body.location)
                }
            }
        }
        // Resaltado con el mismo tokenizador del preview.
        let lang = String((c.language ?? "").split(separator: " ").first ?? "")
        guard !lang.isEmpty, body.length > 0 else { return }
        let code = ns.substring(with: body)
        for (cls, tr) in Highlighter.tokens(code, lang: lang) {
            let hex: String
            switch cls { case "k": hex = s.p.k; case "s": hex = s.p.s; case "c": hex = s.p.c; case "n": hex = s.p.n; case "f": hex = s.p.f; default: hex = s.p.t }
            var attrs: [NSAttributedString.Key: Any] = [.foregroundColor: s.color(hex)]
            if cls == "c" { attrs[.obliqueness] = 0.15 }
            add(attrs, NSRange(location: body.location + tr.location, length: tr.length))
        }
    }

    func table(_ t: Table, _ r: NSRange) {
        let full = ns.lineRange(for: r)
        add([.font: s.font(mono: false, size: s.size * 0.94)], full)
        if let head = range(t.head) { setWeight(650, head) }
        for line in lines(r) {
            let content = lineContent(line)
            let text = ns.substring(with: content)
            if text.allSatisfy({ "|-: \t".contains($0) }) {
                add([.foregroundColor: s.color(s.p.muted)], content)
                continue
            }
            let sub = text as NSString
            var loc = 0
            while loc < sub.length {
                let bar = sub.range(of: "|", range: NSRange(location: loc, length: sub.length - loc))
                guard bar.location != NSNotFound else { break }
                add([.foregroundColor: s.color(s.p.rule)], NSRange(location: content.location + bar.location, length: 1))
                loc = NSMaxRange(bar)
            }
        }
        for cell in t.head.cells { inline(cell, range(cell) ?? r) }
        for row in t.body.rows { for cell in row.cells { inline(cell, range(cell) ?? r) } }
    }

    // En línea ---------------------------------------------------------------

    func inline(_ m: Markup, _ r: NSRange) {
        for child in m.children {
            guard let cr = range(child) else { continue }
            switch child {
            case is Markdown.Text:
                for match in Self.mathRE.matches(in: str, range: cr) {
                    add([.foregroundColor: s.color(s.p.n)], match.range)
                }
            case is Emphasis:
                add([.obliqueness: 0.18], cr)
                delimiters(child, cr)
                inline(child, cr)
            case is Strong:
                setWeight(700, cr)
                delimiters(child, cr)
                inline(child, cr)
            case is Strikethrough:
                add([.strikethroughStyle: NSUnderlineStyle.single.rawValue, .foregroundColor: s.color(s.p.muted)], cr)
                delimiters(child, cr)
                inline(child, cr)
            case is InlineCode:
                let size = (storage.attribute(.font, at: cr.location, effectiveRange: nil) as? NSFont)?.pointSize ?? s.size
                add([.font: s.font(mono: true, size: (size * 0.86).rounded()),
                     .foregroundColor: s.color(s.p.codeFg), .backgroundColor: s.color(s.p.codeBg), .ligature: 0], cr)
                let ticks = run(of: 96 /* ` */, at: cr.location, max: 16)
                if ticks > 0, ticks * 2 <= cr.length {
                    marker(NSRange(location: cr.location, length: ticks))
                    marker(NSRange(location: NSMaxRange(cr) - ticks, length: ticks))
                }
            case let l as Link:
                var attrs: [NSAttributedString.Key: Any] = [
                    .foregroundColor: s.color(s.p.accent),
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                    .underlineColor: s.color(s.p.accent).withAlphaComponent(0.45)
                ]
                if let d = l.destination { attrs[.mdLink] = d }
                add(attrs, cr)
                delimiters(child, cr)
                inline(child, cr)
            case is Image:
                add([.foregroundColor: s.color(s.p.muted)], cr)
            case is InlineHTML:
                add([.foregroundColor: s.color(s.p.muted)], cr)
            default:
                inline(child, cr)
            }
        }
    }
}
