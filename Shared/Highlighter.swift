import Foundation

/// Resaltado de sintaxis liviano, sin dependencias ni JavaScript.
/// Emite <span class="k|s|c|n|f|t"> con todo el texto escapado.
enum Highlighter {
    struct Spec {
        var keywords: Set<String>
        var line: [String] = ["//"]
        var block: (open: String, close: String)? = ("/*", "*/")
        var quotes: Set<Character> = ["\"", "'", "`"]
        var tripleQuotes = false
        var dollarVars = false
        var caseInsensitive = false
        var jsonKeys = false
        var types = true
    }

    private static func words(_ s: String) -> Set<String> {
        Set(s.split(separator: " ").map(String.init))
    }

    private static let cLike = words("""
    if else for while do switch case break continue return default new delete this super class struct enum \
    interface extends implements import export from package public private protected static final const let var \
    func fn function async await try catch throw throws finally in is as of typeof instanceof void null nil true \
    false self where guard defer init extension protocol mut impl pub use mod match loop type trait yield with \
    int float double char bool boolean string long short unsigned signed namespace using template typename \
    override open internal lazy some any inout operator subscript get set val object data fun when Self
    """)

    private static let python = words("""
    False None True and as assert async await break class continue def del elif else except finally for from \
    global if import in is lambda nonlocal not or pass raise return try while with yield self match case
    """)

    private static let shell = words("""
    if then else elif fi for while until do done case esac in function select time return exit export local \
    readonly unset set echo cd source alias true false sudo
    """)

    private static let ruby = words("""
    def end class module if elsif else unless while until for in do begin rescue ensure return yield self nil \
    true false and or not then case when require include extend attr_accessor puts lambda proc
    """)

    private static let sql = words("""
    select from where and or not insert into values update set delete create table alter drop index join left \
    right inner outer on group by order having limit offset as distinct union all null is in like between case \
    when then else end primary key foreign references default unique constraint with returning asc desc
    """)

    private static func spec(for lang: String) -> Spec? {
        switch lang {
        case "swift", "js", "javascript", "jsx", "ts", "typescript", "tsx", "java", "kotlin", "kt", "c", "h",
             "cpp", "c++", "cc", "hpp", "cs", "csharp", "go", "golang", "rust", "rs", "php", "dart", "scala",
             "objc", "objective-c", "zig", "solidity":
            return Spec(keywords: cLike)
        case "py", "python":
            return Spec(keywords: python, line: ["#"], block: nil, quotes: ["\"", "'"], tripleQuotes: true)
        case "sh", "bash", "zsh", "shell", "console", "fish":
            return Spec(keywords: shell, line: ["#"], block: nil, quotes: ["\"", "'"], dollarVars: true, types: false)
        case "rb", "ruby":
            return Spec(keywords: ruby, line: ["#"], block: nil, quotes: ["\"", "'"])
        case "sql":
            return Spec(keywords: sql, line: ["--"], caseInsensitive: true, types: false)
        case "json", "jsonc", "json5":
            return Spec(keywords: words("true false null"), quotes: ["\""], jsonKeys: true, types: false)
        case "yaml", "yml", "toml", "ini":
            return Spec(keywords: words("true false null yes no on off"), line: ["#"], block: nil,
                        quotes: ["\"", "'"], types: false)
        case "css", "scss":
            return Spec(keywords: words("important"), quotes: ["\"", "'"], types: false)
        default:
            return nil
        }
    }

    static func html(_ code: String, lang: String) -> String {
        guard let spec = spec(for: lang.lowercased()) else { return HTMLRenderer.escape(code) }
        let c = Array(code)
        var out = ""
        scan(c, spec) { cls, from, to in
            let text = HTMLRenderer.escape(String(c[from..<to]))
            out += cls.map { "<span class=\"\($0)\">\(text)</span>" } ?? text
        }
        return out
    }

    /// Tokens con clase (k, s, c, n, f, t) y su rango en unidades UTF-16, para estilar un NSTextStorage.
    static func tokens(_ code: String, lang: String) -> [(cls: String, range: NSRange)] {
        guard let spec = spec(for: lang.lowercased()) else { return [] }
        let c = Array(code)
        // Prefijo acumulado de longitudes UTF-16 por carácter (los grafemas pueden ocupar varias unidades).
        var u16 = [Int](repeating: 0, count: c.count + 1)
        for (i, ch) in c.enumerated() { u16[i + 1] = u16[i] + ch.utf16.count }
        var out: [(String, NSRange)] = []
        scan(c, spec) { cls, from, to in
            if let cls { out.append((cls, NSRange(location: u16[from], length: u16[to] - u16[from]))) }
        }
        return out
    }

    /// Recorre el código y emite segmentos contiguos que cubren todo el texto (clase nil = texto plano).
    private static func scan(_ c: [Character], _ spec: Spec, emit: (String?, Int, Int) -> Void) {
        let n = c.count
        var i = 0

        func starts(_ p: String, at k: Int) -> Bool {
            let a = Array(p)
            guard !a.isEmpty, k + a.count <= n else { return false }
            for (o, ch) in a.enumerated() where c[k + o] != ch { return false }
            return true
        }
        func isWord(_ ch: Character) -> Bool { ch.isLetter || ch.isNumber || ch == "_" }

        while i < n {
            let ch = c[i]

            if spec.line.contains(where: { starts($0, at: i) }) {
                var j = i
                while j < n && c[j] != "\n" { j += 1 }
                emit("c", i, j); i = j; continue
            }
            if let b = spec.block, starts(b.open, at: i) {
                var j = i + b.open.count
                while j < n && !starts(b.close, at: j) { j += 1 }
                j = min(n, j + b.close.count)
                emit("c", i, j); i = j; continue
            }
            if spec.tripleQuotes, starts("\"\"\"", at: i) || starts("'''", at: i) {
                let q = String(c[i..<i + 3])
                var j = i + 3
                while j < n && !starts(q, at: j) { j += 1 }
                j = min(n, j + 3)
                emit("s", i, j); i = j; continue
            }
            if spec.quotes.contains(ch) {
                var j = i + 1
                while j < n && c[j] != ch && !(c[j] == "\n" && ch != "`") {
                    j += (c[j] == "\\") ? 2 : 1
                }
                let end = (j < n && c[j] == ch) ? j + 1 : min(j, n)
                var cls = "s"
                if spec.jsonKeys {
                    var k = end
                    while k < n && (c[k] == " " || c[k] == "\t") { k += 1 }
                    if k < n && c[k] == ":" { cls = "t" }
                }
                emit(cls, i, end); i = end; continue
            }
            if ch.isNumber, i == 0 || !isWord(c[i - 1]) {
                var j = i
                while j < n {
                    let d = c[j]
                    if isWord(d) { j += 1 }
                    else if d == ".", j + 1 < n, c[j + 1].isNumber { j += 1 }
                    else { break }
                }
                emit("n", i, j); i = j; continue
            }
            if spec.dollarVars, ch == "$" {
                var j = i + 1
                while j < n && (isWord(c[j]) || c[j] == "{" || c[j] == "}") { j += 1 }
                emit("t", i, max(j, i + 1)); i = max(j, i + 1); continue
            }
            if ch.isLetter || ch == "_" {
                var j = i
                while j < n && isWord(c[j]) { j += 1 }
                let word = String(c[i..<j])
                let key = spec.caseInsensitive ? word.lowercased() : word
                if spec.keywords.contains(key) { emit("k", i, j) }
                else if j < n && c[j] == "(" { emit("f", i, j) }
                else if spec.types, let f = word.first, f.isUppercase, word.count > 1 { emit("t", i, j) }
                else { emit(nil, i, j) }
                i = j; continue
            }
            // Corrida de texto plano hasta el siguiente carácter relevante.
            var j = i + 1
            while j < n, !(isWord(c[j]) || spec.quotes.contains(c[j]) || c[j] == "$"
                           || spec.line.contains(where: { starts($0, at: j) })
                           || (spec.block.map { starts($0.open, at: j) } ?? false)) { j += 1 }
            emit(nil, i, j); i = j
        }
    }
}
