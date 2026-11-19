import Foundation

/// Ediciones asistidas del modo Escribir. Funciones puras: reciben el texto y la selección y devuelven
/// el reemplazo a aplicar (la vista lo aplica con soporte de deshacer).
enum EditAssist {
    struct Edit: Equatable {
        var range: NSRange      // rango a reemplazar, en el texto original
        var text: String        // texto nuevo
        var selection: NSRange  // selección resultante, en el texto nuevo
    }

    static let indentUnit = "    "

    private static let listRE = try! NSRegularExpression(pattern: #"^([ \t]*)([-*+]|(\d{1,9})([.)]))([ \t]+)(\[[ xX]\][ \t]+)?"#)
    private static let quoteRE = try! NSRegularExpression(pattern: #"^(?:[ \t]{0,3}>[ \t]?)+"#)

    private static func content(of line: NSRange, in ns: NSString) -> NSRange {
        var r = line
        while r.length > 0, [10, 13].contains(ns.character(at: NSMaxRange(r) - 1)) { r.length -= 1 }
        return r
    }

    static func isListLine(_ s: String) -> Bool {
        listRE.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length)) != nil
    }

    /// Return al final de un elemento de lista o cita: continúa el marcador. Si el elemento está vacío, lo termina.
    static func newline(in ns: NSString, selection sel: NSRange) -> Edit? {
        guard sel.length == 0, sel.location <= ns.length else { return nil }
        let line = content(of: ns.lineRange(for: sel), in: ns)
        let text = ns.substring(with: line)
        let full = NSRange(location: 0, length: (text as NSString).length)
        let caret = sel.location - line.location

        if let m = listRE.firstMatch(in: text, range: full) {
            guard caret >= m.range.length else { return nil }
            let rest = (text as NSString).substring(from: m.range.length)
            if rest.trimmingCharacters(in: .whitespaces).isEmpty {
                return Edit(range: line, text: "", selection: NSRange(location: line.location, length: 0))
            }
            let t = text as NSString
            let indent = t.substring(with: m.range(at: 1))
            var marker = t.substring(with: m.range(at: 2))
            if m.range(at: 3).location != NSNotFound, let n = Int(t.substring(with: m.range(at: 3))) {
                marker = "\(n + 1)" + t.substring(with: m.range(at: 4))
            }
            let task = m.range(at: 6).location != NSNotFound ? "[ ] " : ""
            let insert = "\n" + indent + marker + " " + task
            return Edit(range: sel, text: insert,
                        selection: NSRange(location: sel.location + (insert as NSString).length, length: 0))
        }
        if let m = quoteRE.firstMatch(in: text, range: full) {
            guard caret >= m.range.length else { return nil }
            let prefix = (text as NSString).substring(with: m.range)
            let rest = (text as NSString).substring(from: m.range.length)
            if rest.trimmingCharacters(in: .whitespaces).isEmpty {
                return Edit(range: line, text: "", selection: NSRange(location: line.location, length: 0))
            }
            let p = prefix.hasSuffix(" ") ? prefix : prefix + " "
            let insert = "\n" + p
            return Edit(range: sel, text: insert,
                        selection: NSRange(location: sel.location + (insert as NSString).length, length: 0))
        }
        return nil
    }

    /// Tab / Shift-Tab sobre líneas de lista: sangra o quita sangría a todas las líneas de lista seleccionadas.
    static func indent(in ns: NSString, selection sel: NSRange, outdent: Bool) -> Edit? {
        guard sel.location <= ns.length else { return nil }
        let block = ns.lineRange(for: sel)
        let first = ns.substring(with: content(of: ns.lineRange(for: NSRange(location: sel.location, length: 0)), in: ns))
        guard isListLine(first) else { return nil }

        var out = ""
        var firstDelta = 0, totalDelta = 0
        var loc = block.location
        var index = 0
        repeat {
            let lineR = ns.lineRange(for: NSRange(location: loc, length: 0))
            var line = ns.substring(with: lineR)
            var delta = 0
            if isListLine(line) {
                if outdent {
                    if line.hasPrefix("\t") { line.removeFirst(); delta = -1 }
                    else {
                        let n = min(indentUnit.count, line.prefix(while: { $0 == " " }).count)
                        line.removeFirst(n); delta = -n
                    }
                } else {
                    line = indentUnit + line; delta = indentUnit.count
                }
            }
            if index == 0 { firstDelta = delta }
            totalDelta += delta
            out += line
            loc = NSMaxRange(lineR)
            index += 1
        } while loc < NSMaxRange(block)
        guard totalDelta != 0 else { return nil }

        let lineStart = block.location
        let newLoc = max(lineStart, sel.location + firstDelta)
        let newLen = max(0, sel.length + totalDelta - firstDelta)
        return Edit(range: block, text: out, selection: NSRange(location: newLoc, length: sel.length == 0 ? 0 : newLen))
    }

    /// ⌘B / ⌘I: envuelve la selección con el marcador, o lo quita si ya está envuelta.
    static func toggleWrap(in ns: NSString, selection sel: NSRange, marker: String) -> Edit {
        let m = (marker as NSString).length
        let sel = NSRange(location: min(sel.location, ns.length), length: min(sel.length, ns.length - min(sel.location, ns.length)))
        if sel.location >= m, NSMaxRange(sel) + m <= ns.length,
           ns.substring(with: NSRange(location: sel.location - m, length: m)) == marker,
           ns.substring(with: NSRange(location: NSMaxRange(sel), length: m)) == marker {
            let outer = NSRange(location: sel.location - m, length: sel.length + 2 * m)
            return Edit(range: outer, text: ns.substring(with: sel), selection: NSRange(location: outer.location, length: sel.length))
        }
        let selected = ns.substring(with: sel)
        if sel.length >= 2 * m, selected.hasPrefix(marker), selected.hasSuffix(marker) {
            let inner = String(selected.dropFirst(marker.count).dropLast(marker.count))
            return Edit(range: sel, text: inner, selection: NSRange(location: sel.location, length: (inner as NSString).length))
        }
        return Edit(range: sel, text: marker + selected + marker, selection: NSRange(location: sel.location + m, length: sel.length))
    }
}
