import Foundation

/// Defensive limits before handing Markdown to swift-markdown.
///
/// The parser and the visitors are recursive: thousands of nested containers (`>>>>…`, lists inside lists)
/// overflow the stack and kill the process (the Quick Look extension runs on threads with a 512 KB stack and crashes
/// between 100 and 200 levels). Block nesting can only come from each line's prefix
/// (`>`, list markers and indentation), so measuring and trimming that prefix is enough.
enum MarkdownLimits {
    static let maxDepth = 32

    /// Approximate depth of the containers the line opens or continues, and the (UTF-16) length of its prefix
    /// up to the point where `limit` is exceeded (nil if it is not exceeded).
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
            case 45, 42, 43: // - * +  (list marker only if followed by a space, tab or end)
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

    /// true if any line exceeds the allowed depth.
    static func exceedsNesting(_ text: String, limit: Int = maxDepth) -> Bool {
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) where scan(line.utf16, limit: limit).cut != nil {
            return true
        }
        return false
    }

    /// Trims the container prefix of the lines that exceed the limit (the rest of the text is kept).
    static func capNesting(_ text: String, limit: Int = maxDepth) -> String {
        guard exceedsNesting(text, limit: limit) else { return text }
        var out: [String] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            guard scan(line.utf16, limit: limit).cut != nil, let cut = scan(line.utf16, limit: max(1, limit - 2)).cut else {
                out.append(String(line)); continue
            }
            let u = line.utf16
            let cutIdx = u.index(u.startIndex, offsetBy: cut)
            // The rest of the prefix (markers and spaces) is dropped and the content is kept.
            var rest = line[cutIdx...]
            while let f = rest.first, " \t>-*+.)0123456789".contains(f) { rest = rest.dropFirst() }
            out.append(String(line[..<cutIdx]) + " " + String(rest))
        }
        return out.joined(separator: "\n")
    }
}
