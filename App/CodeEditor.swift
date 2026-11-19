import AppKit
import SwiftUI

/// Markdown text editor (Markdown mode and the left pane of Split): monospaced, dimmed markers.
struct CodeEditor: NSViewRepresentable {
    @Binding var text: String
    var palette: Palette
    var fonts: FontSettings
    var scrollSync: ScrollSync?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let tv = CenteredTextView(frame: .zero)
        tv.delegate = context.coordinator
        tv.isRichText = false
        tv.importsGraphics = false
        tv.allowsUndo = true
        tv.usesFindBar = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isAutomaticLinkDetectionEnabled = false
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.string = text

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = true
        scroll.documentView = tv
        context.coordinator.textView = tv
        context.coordinator.restyle(force: true)
        scrollSync?.attach(editor: scroll)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let c = context.coordinator
        c.parent = self
        guard let tv = c.textView else { return }
        if tv.string != text {
            let sel = tv.selectedRange()
            tv.string = text
            tv.setSelectedRange(NSRange(location: min(sel.location, (text as NSString).length), length: 0))
            c.restyle(force: true)
        } else if c.applied?.0 != palette || c.applied?.1 != fonts {
            c.restyle(force: true)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeEditor
        weak var textView: NSTextView?
        var applied: (Palette, FontSettings)?

        init(_ parent: CodeEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = textView else { return }
            parent.text = tv.string
            if !tv.hasMarkedText() { restyle(force: false) }
        }

        func restyle(force: Bool) {
            guard let tv = textView, let storage = tv.textStorage else { return }
            let p = parent.palette, fonts = parent.fonts
            if force || applied?.0 != p || applied?.1 != fonts {
                tv.backgroundColor = NSColor(hex: p.bg)
                tv.insertionPointColor = NSColor(hex: p.accent)
                tv.selectedTextAttributes = [.backgroundColor: NSColor(hex: p.accent).withAlphaComponent(0.25)]
                tv.enclosingScrollView?.backgroundColor = NSColor(hex: p.bg)
                applied = (p, fonts)
            }
            tv.typingAttributes = MarkdownStyler.baseAttributes(palette: p, fonts: fonts)
            storage.beginEditing()
            MarkdownStyler.apply(to: storage, palette: p, fonts: fonts)
            storage.endEditing()
        }
    }
}

/// NSTextView with the text column centered when the window is wide.
final class CenteredTextView: NSTextView {
    static let column: CGFloat = 760

    override func setFrameSize(_ newSize: NSSize) {
        let pad = max(28, ((newSize.width - Self.column) / 2).rounded())
        if abs(textContainerInset.width - pad) > 0.5 { textContainerInset = NSSize(width: pad, height: 32) }
        super.setFrameSize(newSize)
    }
}

enum MarkdownStyler {
    static let maxStyled = 300_000

    static func size(_ fonts: FontSettings) -> CGFloat { max(12, fonts.size - 2) }

    static func baseAttributes(palette p: Palette, fonts: FontSettings) -> [NSAttributedString.Key: Any] {
        let ps = NSMutableParagraphStyle()
        ps.lineHeightMultiple = 1.3
        return [.font: fonts.font(mono: true, size: size(fonts)), .foregroundColor: NSColor(hex: p.fg),
                .ligature: 0, .paragraphStyle: ps]
    }

    /// (expression, groups to dim, group to highlight, kind)
    private static let rules: [(NSRegularExpression, String)] = {
        func re(_ p: String) -> NSRegularExpression { try! NSRegularExpression(pattern: p, options: [.anchorsMatchLines]) }
        return [
            (re(#"^(#{1,6})[ \t]+(.*)$"#), "heading"),
            (re(#"^([ \t]*(?:>[ \t]?)+)"#), "quote"),
            (re(#"^[ \t]*([-*+]|\d{1,9}[.)])[ \t]+(\[[ xX]\][ \t])?"#), "list"),
            (re(#"(\*\*|__)(?=[^\s*_])([^*_\n]{1,500}?)(?<=\S)\1"#), "bold"),
            (re(#"(?<![*\w])([*_])(?=[^\s*_])([^*_\n]+?)(?<=\S)\1(?![*\w])"#), "italic"),
            (re(#"(~~)(?=[^\s~])([^~\n]{1,500}?)(?<=\S)~~"#), "strike"),
            (re(#"(`+)([^`\n]+?)\1"#), "code"),
            (re(#"!?(\[)([^\]\n]*)(\]\([^)\n]*\))"#), "link"),
            (re(#"</?[A-Za-z][^<>\n]*>"#), "html"),
            (re(#"\$\$?[^$\n]+\$\$?"#), "math"),
            (re(#"^[ \t]*\|.*\|[ \t]*$"#), "table"),
        ]
    }()

    static func apply(to storage: NSTextStorage, palette p: Palette, fonts: FontSettings) {
        let text = storage.string as NSString
        let full = NSRange(location: 0, length: text.length)
        storage.setAttributes(baseAttributes(palette: p, fonts: fonts), range: full)
        guard text.length <= maxStyled else { return }

        let muted = NSColor(hex: p.muted), accent = NSColor(hex: p.accent), rule = NSColor(hex: p.rule)
        let bold = fonts.font(mono: true, size: size(fonts), weight: 700)
        let str = storage.string
        func g(_ m: NSTextCheckingResult, _ i: Int) -> NSRange? {
            i < m.numberOfRanges && m.range(at: i).location != NSNotFound ? m.range(at: i) : nil
        }
        for (regex, kind) in rules {
            regex.enumerateMatches(in: str, range: full) { m, _, _ in
                guard let m else { return }
                switch kind {
                case "heading":
                    if let r = g(m, 1) { storage.addAttribute(.foregroundColor, value: muted, range: r) }
                    if let r = g(m, 2) { storage.addAttribute(.font, value: bold, range: r) }
                case "quote", "list":
                    for i in 1..<m.numberOfRanges { if let r = g(m, i) { storage.addAttribute(.foregroundColor, value: muted, range: r) } }
                case "bold":
                    storage.addAttribute(.font, value: bold, range: m.range)
                    if let r = g(m, 1) {
                        storage.addAttribute(.foregroundColor, value: muted, range: r)
                        storage.addAttribute(.foregroundColor, value: muted, range: NSRange(location: NSMaxRange(m.range) - r.length, length: r.length))
                    }
                case "italic", "strike":
                    if let r = g(m, 2) {
                        storage.addAttribute(kind == "italic" ? .obliqueness : .strikethroughStyle,
                                             value: kind == "italic" ? 0.15 as NSNumber : NSUnderlineStyle.single.rawValue as NSNumber, range: r)
                    }
                    if let r = g(m, 1) {
                        storage.addAttribute(.foregroundColor, value: muted, range: r)
                        storage.addAttribute(.foregroundColor, value: muted, range: NSRange(location: NSMaxRange(m.range) - r.length, length: r.length))
                    }
                case "code":
                    if let r = g(m, 1) {
                        storage.addAttribute(.foregroundColor, value: muted, range: r)
                        storage.addAttribute(.foregroundColor, value: muted, range: NSRange(location: NSMaxRange(m.range) - r.length, length: r.length))
                    }
                case "link":
                    storage.addAttribute(.foregroundColor, value: muted, range: m.range)
                    if let r = g(m, 2) { storage.addAttribute(.foregroundColor, value: accent, range: r) }
                case "html":
                    storage.addAttribute(.foregroundColor, value: muted, range: m.range)
                case "math":
                    storage.addAttribute(.foregroundColor, value: NSColor(hex: p.n), range: m.range)
                case "table":
                    let line = text.substring(with: m.range) as NSString
                    var loc = 0
                    while loc < line.length {
                        let bar = line.range(of: "|", range: NSRange(location: loc, length: line.length - loc))
                        guard bar.location != NSNotFound else { break }
                        storage.addAttribute(.foregroundColor, value: rule, range: NSRange(location: m.range.location + bar.location, length: 1))
                        loc = NSMaxRange(bar)
                    }
                    if line.trimmingCharacters(in: .whitespaces).allSatisfy({ "|-: ".contains($0) }) {
                        storage.addAttribute(.foregroundColor, value: rule, range: m.range)
                    }
                default: break
                }
            }
        }
        // Code blocks: painted last so they take precedence over the other rules.
        let base = fonts.font(mono: true, size: size(fonts))
        var inFence = false
        text.enumerateSubstrings(in: full, options: [.byLines, .substringNotRequired]) { _, lineRange, enclosing, _ in
            let line = text.substring(with: lineRange).trimmingCharacters(in: .whitespaces)
            let isFence = line.hasPrefix("```") || line.hasPrefix("~~~")
            if isFence {
                storage.addAttributes([.foregroundColor: muted, .font: base], range: enclosing)
                inFence.toggle()
            } else if inFence {
                storage.addAttributes([.foregroundColor: NSColor(hex: p.fg), .font: base], range: enclosing)
                storage.removeAttribute(.obliqueness, range: enclosing)
                storage.removeAttribute(.strikethroughStyle, range: enclosing)
            }
        }
    }
}
