import AppKit
import Markdown

// Write mode tests and screenshots (development tool only).

@MainActor
enum LiveChecks {
    /// Rasterizes the live editor to PNG. `caretLine` (1-based) places the caret on that line.
    static func render(text: String, palette: Palette, fonts: FontSettings = FontSettings(), width: CGFloat, caretLine: Int?, to url: URL) throws {
        let (scroll, tv) = LiveTextView.makeScrollable(palette: palette)
        tv.fonts = fonts
        let window = NSWindow(contentRect: NSRect(x: -30000, y: -30000, width: width, height: 900),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = scroll
        scroll.frame = NSRect(x: 0, y: 0, width: width, height: 900)
        tv.frame = NSRect(x: 0, y: 0, width: width, height: 900)
        tv.setMarkdown(text)
        var caret = 0
        if let line = caretLine {
            let ns = text as NSString
            var l = 1
            while l < line, caret < ns.length { caret = NSMaxRange(ns.lineRange(for: NSRange(location: caret, length: 0))); l += 1 }
        }
        window.makeFirstResponder(tv)
        tv.setSelectedRange(NSRange(location: caret, length: 0))
        tv.layoutManager?.ensureLayout(for: tv.textContainer!)
        tv.sizeToFit()
        let h = max(400, (tv.layoutManager?.usedRect(for: tv.textContainer!).height ?? 800) + 100)
        tv.frame = NSRect(x: 0, y: 0, width: width, height: h)
        tv.layoutManager?.ensureLayout(for: tv.textContainer!)
        if ProcessInfo.processInfo.environment["MDQ_FRAGS"] != nil, let lm = tv.layoutManager {
            let ns = text as NSString
            var loc = 0
            while loc < ns.length {
                let line = ns.lineRange(for: NSRange(location: loc, length: 0))
                let g = lm.glyphIndexForCharacter(at: loc)
                var eff = NSRange()
                let frag = lm.lineFragmentRect(forGlyphAt: g, effectiveRange: &eff)
                print(String(format: "%5d y=%7.1f h=%5.1f ", loc, frag.minY, frag.height), ns.substring(with: line).prefix(30).debugDescription)
                loc = NSMaxRange(line)
            }
        }
        guard let rep = tv.bitmapImageRepForCachingDisplay(in: tv.bounds) else { throw CocoaError(.fileWriteUnknown) }
        tv.cacheDisplay(in: tv.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try png.write(to: url)
        window.close()
    }

    // MARK: Tests

    private static var failures = 0
    private static var passes = 0

    private static func check(_ cond: @autoclosure () -> Bool, _ msg: String) {
        if cond() { passes += 1 } else { failures += 1; print("  ✗ \(msg)") }
    }

    static func runAll(samplesDir: URL) -> Int32 {
        sourceMapTests()
        editAssistTests()
        highlighterTests()
        limitsTests()
        updateTests()
        var docs: [(String, String)] = []
        if let files = try? FileManager.default.contentsOfDirectory(at: samplesDir, includingPropertiesForKeys: nil) {
            for f in files where f.pathExtension == "md" {
                if let t = try? String(contentsOf: f, encoding: .utf8) { docs.append((f.lastPathComponent, t)) }
            }
        }
        docs += hostileDocs()
        let style = LiveStyle(p: AppTheme.default.palette)
        for (name, text) in docs {
            let t0 = Date()
            print("· \(name)", terminator: ""); fflush(stdout)
            defer { print(String(format: "  %.2fs", Date().timeIntervalSince(t0))); fflush(stdout) }
            styleInvariants(name, text, style)
            incrementalEquivalence(name, text, style)
        }
        print("Tests: \(passes) passed, \(failures) failed")
        return failures == 0 ? 0 : 1
    }

    static func hostileDocs() -> [(String, String)] {
        var out: [(String, String)] = [
            ("empty", ""),
            ("lone #", "#"),
            ("unclosed fence", "```swift\nlet a = 1\n\nmás texto"),
            ("crlf", "# T\r\n\r\n- a\r\n- [x] b\r\n\r\n**n**\r\n"),
            ("emoji zwj", "# 👨‍👩‍👧 título\n\n**👍🏽** y `🇨🇱` [é](https://x.cl) *ñ*\n"),
            ("nul and control", "a\u{0}b **c\u{1}** `\u{7}`\n"),
            ("stray markers", "** * ` [ ]( ![ ~~ > - [ ] 1. ---\n"),
            ("empty list", "- \n- [ ]\n1.\n"),
            ("setext", "Hola\n===\n\nChao\n---\n"),
            ("broken table", "| a | b\n|--\n| 1 |\n"),
            ("html", "<div>\n<script>alert(1)</script>\n</div>\n<b>x</b>"),
            ("front matter", "---\ntitle: x\n---\n# H\n"),
            ("unclosed front matter", "---\ntitle: x\n# H\n"),
            ("odd links", "[a](javascript:alert(1)) [b](<sp ace>) <https://x.cl> [c][ref]\n\n[ref]: https://y.cl\n"),
        ]
        out.append(("deep quotes", String(repeating: ">", count: 200) + " x\n"))
        out.append(("deep lists", (0..<60).map { String(repeating: "  ", count: $0) + "- n\($0)" }.joined(separator: "\n")))
        out.append(("extreme nesting, quotes", String(repeating: ">", count: 20000) + " x\n"))
        out.append(("extreme nesting, lists", (0..<3000).map { String(repeating: "  ", count: $0) + "- n" }.joined(separator: "\n")))
        out.append(("extreme nesting, single line", String(repeating: "- ", count: 5000) + "x\n" + String(repeating: "1. > ", count: 3000) + "y"))
        out.append(("huge line", String(repeating: "**a** `b` ", count: 5000)))
        out.append(("many emphasis markers", String(repeating: "*", count: 3000)))
        return out
    }

    static func sourceMapTests() {
        let text = "# Título con **negrita** ñ 🙂\nx"
        let doc = Document(parsing: text)
        let map = SourceMap(text)
        let ns = text as NSString
        if let h = doc.child(at: 0), let strong = h.child(at: 1), let r = map.range(strong.range) {
            check(ns.substring(with: r) == "**negrita**", "SourceMap strong → \(ns.substring(with: r))")
        } else { check(false, "SourceMap: nodes not found") }
        if let h = doc.child(at: 0), let tail = h.child(at: 2), let r = map.range(tail.range) {
            check(ns.substring(with: r) == " ñ 🙂", "SourceMap text with emoji → \(ns.substring(with: r))")
        }
    }

    static func editAssistTests() {
        func nl(_ s: String, _ caret: Int) -> String? {
            guard let e = EditAssist.newline(in: s as NSString, selection: NSRange(location: caret, length: 0)) else { return nil }
            return (s as NSString).replacingCharacters(in: e.range, with: e.text)
        }
        check(nl("- uno", 5) == "- uno\n- ", "continues bullet")
        check(nl("  * uno", 7) == "  * uno\n  * ", "continues nested bullet")
        check(nl("9. uno", 6) == "9. uno\n10. ", "increments numbered item")
        check(nl("3) uno", 6) == "3) uno\n4) ", "numbered item with parenthesis")
        check(nl("- [x] hecho", 11) == "- [x] hecho\n- [ ] ", "new task is unchecked")
        check(nl("- ", 2) == "", "Return on an empty item ends the list")
        check(nl("> cita", 6) == "> cita\n> ", "continues quote")
        check(nl("> ", 2) == "", "Return on an empty quote ends it")
        check(nl("texto", 5) == nil, "plain text is left alone")
        check(nl("- uno", 1) == nil, "caret inside the marker: normal Return")

        func ind(_ s: String, _ sel: NSRange, _ out: Bool) -> (String, NSRange)? {
            guard let e = EditAssist.indent(in: s as NSString, selection: sel, outdent: out) else { return nil }
            return ((s as NSString).replacingCharacters(in: e.range, with: e.text), e.selection)
        }
        check(ind("- a", NSRange(location: 3, length: 0), false)?.0 == "    - a", "Tab indents")
        check(ind("- a", NSRange(location: 3, length: 0), false)?.1 == NSRange(location: 7, length: 0), "Tab moves the caret")
        check(ind("    - a", NSRange(location: 7, length: 0), true)?.0 == "- a", "Shift-Tab outdents")
        check(ind("- a\n- b\nc", NSRange(location: 0, length: 9), false)?.0 == "    - a\n    - b\nc", "multi-line Tab only on lists")
        check(ind("texto", NSRange(location: 2, length: 0), false) == nil, "Tab outside a list: normal")

        func wrap(_ s: String, _ sel: NSRange, _ m: String) -> String {
            let e = EditAssist.toggleWrap(in: s as NSString, selection: sel, marker: m)
            return (s as NSString).replacingCharacters(in: e.range, with: e.text)
        }
        check(wrap("hola mundo", NSRange(location: 5, length: 5), "**") == "hola **mundo**", "⌘B wraps")
        check(wrap("hola **mundo**", NSRange(location: 7, length: 5), "**") == "hola mundo", "⌘B unwraps")
        check(wrap("hola **mundo**", NSRange(location: 5, length: 9), "**") == "hola mundo", "⌘B unwraps a selection that includes the markers")
        check(wrap("x", NSRange(location: 1, length: 0), "*") == "x**", "⌘I with no selection inserts a pair")
    }

    static func updateTests() {
        check(UpdateChecker.compare("1.10", "1.9") == .orderedDescending, "version 1.10 > 1.9")
        check(UpdateChecker.compare("1.0", "1.0.0") == .orderedSame, "version 1.0 == 1.0.0")
        check(UpdateChecker.isValidRepo("shipibo-studio/georg-md") && !UpdateChecker.isValidRepo("a/b/../c"), "valid repo")
        check(UpdateChecker.safeGitHubURL("https://evil.example/x.dmg") == nil, "rejects foreign host")
        check(UpdateChecker.safeGitHubURL("http://github.com/x") == nil, "rejects http")
        check(UpdateChecker.safeGitHubURL("https://user@github.com/x") == nil, "rejects credentials in URL")
        let newer = #"{"tag_name":"v1.2.0","html_url":"https://github.com/shipibo-studio/georg-md/releases/tag/v1.2.0","assets":[{"name":"Georg-md-1.2.0.dmg","browser_download_url":"https://github.com/shipibo-studio/georg-md/releases/download/v1.2.0/Georg-md-1.2.0.dmg"}]}"#
        if case .available(let v, _, let dl) = UpdateChecker.evaluate(Data(newer.utf8), current: "1.0.0") {
            check(v == "1.2.0" && dl?.lastPathComponent == "Georg-md-1.2.0.dmg", "detects new version with .dmg")
        } else { check(false, "detects new version") }
        check(UpdateChecker.evaluate(Data(newer.utf8), current: "1.2") == .upToDate("1.2"), "same version: up to date")
        let evil = #"{"tag_name":"v9.0","html_url":"https://evil.example/r","assets":[]}"#
        check(UpdateChecker.evaluate(Data(evil.utf8), current: "1.0") == .failed("Unexpected response."), "rejects page outside GitHub")
        let badTag = #"{"tag_name":"v9.0<script>","html_url":"https://github.com/a/b","assets":[]}"#
        check(UpdateChecker.evaluate(Data(badTag.utf8), current: "1.0") == .failed("Unexpected response."), "rejects non-numeric tag")
        let pre = #"{"tag_name":"v9.0","html_url":"https://github.com/a/b","prerelease":true}"#
        check(UpdateChecker.evaluate(Data(pre.utf8), current: "1.0") == .upToDate("1.0"), "ignores prerelease")
    }

    static func limitsTests() {
        check(!MarkdownLimits.exceedsNesting("> > - a\n    - b\n1. x"), "limits: normal document is left alone")
        check(MarkdownLimits.capNesting("# T\n\n- a\n  - b") == "# T\n\n- a\n  - b", "limits: capNesting leaves normal input unchanged")
        check(MarkdownLimits.exceedsNesting(String(repeating: ">", count: 40) + " x"), "limits: 40 quotes are detected")
        let capped = MarkdownLimits.capNesting(String(repeating: "- ", count: 100) + "hola")
        check(capped.hasSuffix("hola") && !MarkdownLimits.exceedsNesting(capped), "limits: trims and keeps the content → \(capped.suffix(12))")
    }

    static func highlighterTests() {
        let code = "let s = \"é🙂\" // c\nfunc f() {}"
        let toks = Highlighter.tokens(code, lang: "swift")
        let ns = code as NSString
        check(toks.contains { $0.cls == "s" && ns.substring(with: $0.range) == "\"é🙂\"" }, "tokens: string with emoji")
        check(toks.contains { $0.cls == "c" && ns.substring(with: $0.range) == "// c" }, "tokens: comment")
        check(Highlighter.html("a < b", lang: "swift") == "a &lt; b", "html escapes")
    }

    static func styled(_ text: String, _ style: LiveStyle) -> NSTextStorage {
        let st = NSTextStorage(string: text)
        let parsed = LiveStyler.parse(text)
        st.beginEditing()
        LiveStyler.apply(to: st, parsed: parsed, region: NSRange(location: 0, length: st.length), style: style)
        st.endEditing()
        return st
    }

    static func styleInvariants(_ name: String, _ text: String, _ style: LiveStyle) {
        let st = styled(text, style)
        check(st.string == text, "[\(name)] styling does not change the text")
        var newlineMarked = false
        st.enumerateAttribute(.mdMarker, in: NSRange(location: 0, length: st.length)) { v, r, _ in
            guard v != nil else { return }
            if (st.string as NSString).substring(with: r).contains(where: { $0 == "\n" || $0 == "\r" || $0 == "\r\n" }) { newlineMarked = true }
        }
        check(!newlineMarked, "[\(name)] no marker includes line breaks")
        LiveStyler.conceal(st, in: NSRange(location: 0, length: st.length), active: NSRange(location: 0, length: 0))
        check(st.string == text, "[\(name)] concealing does not change the text")
    }

    /// Random (reproducible) edits: partial restyling must give the same result as a full restyle.
    static func incrementalEquivalence(_ name: String, _ text: String, _ style: LiveStyle) {
        guard (text as NSString).length < 20_000 else { return }
        var rng = SplitMix(seed: UInt64(truncatingIfNeeded: text.utf8.count &* 2654435761 &+ 7))
        let inserts = ["x", "\n", "**", "# ", "- ", "`", "\n\n", "```\n", "> ", "| a |", "é", "🙂", ""]
        var current = text
        let st = styled(current, style)
        var sig = LiveStyler.parse(current).signature
        var partialUsed = 0
        for _ in 0..<40 {
            let ns = current as NSString
            let loc = ns.length == 0 ? 0 : Int(rng.next() % UInt64(ns.length + 1))
            let maxDel = min(3, ns.length - loc)
            var del = maxDel > 0 ? Int(rng.next() % UInt64(maxDel + 1)) : 0
            var r = NSRange(location: loc, length: del)
            // Do not split surrogate pairs or graphemes.
            if r.length > 0 { r = ns.rangeOfComposedCharacterSequences(for: r) }
            else if loc < ns.length { r.location = ns.rangeOfComposedCharacterSequence(at: loc).location }
            del = r.length
            let ins = inserts[Int(rng.next() % UInt64(inserts.count))]
            let before = current
            st.replaceCharacters(in: r, with: ins)
            current = st.string
            let parsed = LiveStyler.parse(current)
            let region = LiveStyler.dirtyRegion(old: sig, new: parsed.signature, edit: r, newLength: (ins as NSString).length, textLength: st.length)
            if region != nil { partialUsed += 1 }
            st.beginEditing()
            LiveStyler.apply(to: st, parsed: parsed, region: region ?? NSRange(location: 0, length: st.length), style: style)
            st.endEditing()
            sig = parsed.signature
            let full = styled(current, style)
            if !st.isEqual(to: full) {
                check(false, "[\(name)] partial ≠ full after replacing \(r) with \(ins.debugDescription) region=\(String(describing: region))")
                var i = 0
                while i < st.length {
                    var r1 = NSRange(), r2 = NSRange()
                    let a1 = st.attributes(at: i, effectiveRange: &r1), a2 = full.attributes(at: i, effectiveRange: &r2)
                    if !(a1 as NSDictionary).isEqual(to: a2) {
                        let ctx = (current as NSString).substring(with: (current as NSString).lineRange(for: NSRange(location: i, length: 0)))
                        print("    first differing index \(i) on line: \(ctx.debugDescription)")
                        let safe = name.filter { $0.isLetter }
                        try? current.write(toFile: "/tmp/georg-verify/fail-\(safe).md", atomically: true, encoding: .utf8)
                        try? before.write(toFile: "/tmp/georg-verify/fail-\(safe)-before.md", atomically: true, encoding: .utf8)
                        for k in Set(a1.keys).union(a2.keys) where !((a1[k] as AnyObject?)?.isEqual(a2[k]) ?? (a2[k] == nil)) {
                            print("      \(k.rawValue): partial=\(String(describing: a1[k])) full=\(String(describing: a2[k]))")
                        }
                        break
                    }
                    i = min(NSMaxRange(r1), NSMaxRange(r2))
                }
                return
            }
        }
        check(true, "[\(name)] incremental equivalence (\(partialUsed)/40 partial)")
    }
}

/// Seeded pseudo-random generator, so the tests are reproducible.
struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
