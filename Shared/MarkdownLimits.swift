import Foundation

/// Límites defensivos antes de entregar Markdown a swift-markdown.
///
/// El parser y los visitantes son recursivos: miles de contenedores anidados (`>>>>…`, listas dentro de listas)
/// desbordan la pila y matan el proceso (la extensión de Quick Look corre en hilos con pila de 512 KB y cae
/// entre 100 y 200 niveles). El anidamiento de bloques solo puede venir del prefijo de cada línea
/// (`>`, marcadores de lista e indentación), así que basta con medir y recortar ese prefijo.
enum MarkdownLimits {
    static let maxDepth = 32

    /// Profundidad aproximada de contenedores que abre o continúa la línea, y el largo (UTF-16) de su prefijo
    /// hasta el punto en que se supera `limit` (nil si no se supera).
    private static func scan(_ line: Substring.UTF16View, limit: Int) -> (depth: Int, cut: Int?) {
        var depth = 0, cols = 0, i = 0
        var cut: Int?
        let chars = Array(line.prefix(4096))
        let n = chars.count
        func bump(_ by: Int, at k: Int) {
            depth += by
            if cut == nil, depth > limit { cut = k }
        }
        while i < n {
            let c = chars[i]
            switch c {
            case 32: cols += 1; if cols % 2 == 0 { bump(1, at: i) }; i += 1
            case 9: cols += 4; bump(2, at: i); i += 1
            case 62: bump(1, at: i); i += 1 // >
            case 45, 42, 43: // - * +  (marcador de lista solo si sigue espacio, tab o fin)
                if i + 1 == n || chars[i + 1] == 32 || chars[i + 1] == 9 { bump(1, at: i); i += 1 } else { return (depth, cut) }
            case 48...57:
                var j = i
                while j < n, j - i < 9, (48...57).contains(chars[j]) { j += 1 }
                if j < n, chars[j] == 46 || chars[j] == 41, j + 1 == n || chars[j + 1] == 32 || chars[j + 1] == 9 {
                    bump(1, at: i); i = j + 1
                } else { return (depth, cut) }
            default:
                return (depth, cut)
            }
        }
        return (depth, cut)
    }

    /// true si alguna línea supera la profundidad permitida.
    static func exceedsNesting(_ text: String, limit: Int = maxDepth) -> Bool {
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) where scan(line.utf16, limit: limit).cut != nil {
            return true
        }
        return false
    }

    /// Recorta el prefijo de contenedores de las líneas que superan el límite (el resto del texto se conserva).
    static func capNesting(_ text: String, limit: Int = maxDepth) -> String {
        guard exceedsNesting(text, limit: limit) else { return text }
        var out: [String] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            guard scan(line.utf16, limit: limit).cut != nil, let cut = scan(line.utf16, limit: max(1, limit - 2)).cut else {
                out.append(String(line)); continue
            }
            let u = line.utf16
            let cutIdx = u.index(u.startIndex, offsetBy: cut)
            // Se descarta el resto del prefijo (marcadores y espacios) y se conserva el contenido.
            var rest = line[cutIdx...]
            while let f = rest.first, " \t>-*+.)0123456789".contains(f) { rest = rest.dropFirst() }
            out.append(String(line[..<cutIdx]) + " " + String(rest))
        }
        return out.joined(separator: "\n")
    }
}
