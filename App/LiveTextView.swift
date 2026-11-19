import AppKit

/// "Write" mode editor: a single editable text where the Markdown appears formatted.
/// Uses TextKit 1 (NSLayoutManager) on purpose: it allows hiding markers with null glyphs, drawing
/// per-range decorations and exact hit-testing of checkboxes; TextKit 2 does not expose that in a stable way.
final class LiveTextView: NSTextView, NSLayoutManagerDelegate {
    /// Maximum width of the text column (Coffee style).
    static let column: CGFloat = 700
    /// From this size on, restyling is grouped (debounced) so it does not block typing.
    static let debounceThreshold = 30_000

    var palette: Palette {
        didSet { if palette != oldValue { applyChrome(); restyleAll() } }
    }

    var fonts = FontSettings() {
        didSet { if fonts != oldValue { applyChrome(); restyleAll() } }
    }

    private var style: LiveStyle { LiveStyle(p: palette, fonts: fonts) }
    private var signature = LiveStyler.Signature()
    private var pendingEdit: (range: NSRange, newLength: Int)?
    private var needsFull = false
    private var inEdit = false
    private var revealed = NSRange(location: 0, length: 0)
    private var debounce: DispatchWorkItem?
    /// NSTextView does not retain its NSTextStorage when the TextKit 1 stack is assembled by hand.
    private var ownedStorage: NSTextStorage?

    static func makeScrollable(palette: Palette) -> (NSScrollView, LiveTextView) {
        let storage = NSTextStorage()
        let lm = NSLayoutManager()
        storage.addLayoutManager(lm)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        lm.addTextContainer(container)
        let tv = LiveTextView(frame: .zero, textContainer: container, palette: palette)
        tv.ownedStorage = storage
        lm.delegate = tv
        lm.allowsNonContiguousLayout = true

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = true
        scroll.documentView = tv
        return (scroll, tv)
    }

    init(frame: NSRect, textContainer: NSTextContainer?, palette: Palette) {
        self.palette = palette
        super.init(frame: frame, textContainer: textContainer)
        isRichText = false
        importsGraphics = false
        allowsUndo = true
        usesFindBar = true
        isIncrementalSearchingEnabled = true
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isAutomaticLinkDetectionEnabled = false
        isAutomaticDataDetectionEnabled = false
        isVerticallyResizable = true
        isHorizontallyResizable = false
        autoresizingMask = [.width]
        minSize = NSSize(width: 0, height: 0)
        maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textContainerInset = NSSize(width: 32, height: 44)
        applyChrome()
    }

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        self.palette = AppTheme.default.palette
        super.init(frame: frameRect, textContainer: container)
    }

    required init?(coder: NSCoder) { nil }

    // MARK: Content

    /// Replaces the whole text (initial load or external change) and restyles everything.
    func setMarkdown(_ text: String) {
        let sel = selectedRange()
        textStorage?.replaceCharacters(in: NSRange(location: 0, length: textStorage?.length ?? 0), with: text)
        setSelectedRange(NSRange(location: min(sel.location, (text as NSString).length), length: 0))
        restyleAll()
    }

    private func applyChrome() {
        let p = palette
        backgroundColor = NSColor(hex: p.bg)
        insertionPointColor = NSColor(hex: p.accent)
        selectedTextAttributes = [.backgroundColor: NSColor(hex: p.accent).withAlphaComponent(0.25)]
        enclosingScrollView?.backgroundColor = NSColor(hex: p.bg)
        typingAttributes = style.base
        needsDisplay = true
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        enclosingScrollView?.backgroundColor = NSColor(hex: palette.bg)
    }

    // MARK: Restyling

    func restyleAll() {
        needsFull = true
        pendingEdit = nil
        restyle()
    }

    private func restyle() {
        debounce?.cancel(); debounce = nil
        guard let storage = textStorage else { return }
        let text = storage.string
        let len = storage.length
        storage.beginEditing()
        defer {
            storage.endEditing()
            needsFull = false
            pendingEdit = nil
            sanitizeTypingAttributes()
        }
        guard len <= LiveStyler.maxStyled else {
            storage.setAttributes(style.base, range: NSRange(location: 0, length: len))
            signature = LiveStyler.Signature()
            return
        }
        let parsed = LiveStyler.parse(text)
        var region = NSRange(location: 0, length: len)
        if !needsFull, let e = pendingEdit,
           let r = LiveStyler.dirtyRegion(old: signature, new: parsed.signature, edit: e.range, newLength: e.newLength, textLength: len) {
            region = r
        }
        signature = parsed.signature
        LiveStyler.apply(to: storage, parsed: parsed, region: region, style: style)
        let active = activeRange()
        let lineRegion = (storage.string as NSString).lineRange(for: region)
        LiveStyler.conceal(storage, in: lineRegion, active: active)
        // The previously revealed area may fall outside the restyled region.
        let old = (storage.string as NSString).lineRange(for: LiveStyler.clamp(revealed, len))
        if NSIntersectionRange(old, lineRegion).length < old.length { LiveStyler.conceal(storage, in: old, active: active) }
        revealed = active
    }

    /// Lines where markers are shown: those of the selection; inside a code block, the whole block.
    private func activeRange() -> NSRange {
        guard let storage = textStorage else { return NSRange(location: 0, length: 0) }
        let ns = storage.string as NSString
        let sel = LiveStyler.clamp(selectedRange(), ns.length)
        var r = ns.lineRange(for: sel)
        if sel.location < storage.length, (storage.attribute(.mdDeco, at: sel.location, effectiveRange: nil) as? String) == "code" {
            var block = NSRange()
            _ = storage.attribute(.mdDeco, at: sel.location, longestEffectiveRange: &block, in: NSRange(location: 0, length: ns.length))
            r = NSUnionRange(r, block)
        }
        return r
    }

    private func updateConcealment() {
        guard let storage = textStorage, !inEdit, !hasMarkedText() else { return }
        let active = activeRange()
        guard active != revealed else { return }
        let ns = storage.string as NSString
        let region = NSUnionRange(ns.lineRange(for: LiveStyler.clamp(revealed, ns.length)), active)
        storage.beginEditing()
        LiveStyler.conceal(storage, in: region, active: active)
        storage.endEditing()
        revealed = active
        sanitizeTypingAttributes()
    }

    /// Typed text does not inherit internal attributes (hidden marker, decorations, links).
    private func sanitizeTypingAttributes() {
        var t = typingAttributes
        let wasMarker = t[.mdMarker] != nil
        for k in [NSAttributedString.Key.mdMarker, .mdHidden, .mdDeco, .mdLink] { t.removeValue(forKey: k) }
        if wasMarker || (t[.foregroundColor] as? NSColor) == .clear { t[.foregroundColor] = NSColor(hex: palette.fg) }
        typingAttributes = t
    }

    override func shouldChangeText(inRanges affectedRanges: [NSValue], replacementStrings: [String]?) -> Bool {
        let ok = super.shouldChangeText(inRanges: affectedRanges, replacementStrings: replacementStrings)
        guard ok else { return false }
        if pendingEdit != nil || affectedRanges.count != 1 || replacementStrings?.count != 1 {
            needsFull = true
        } else if let s = replacementStrings?.first {
            pendingEdit = (affectedRanges[0].rangeValue, (s as NSString).length)
        }
        inEdit = true
        return true
    }

    override func didChangeText() {
        inEdit = false
        super.didChangeText()
        if hasMarkedText() { needsFull = true; return }
        if (textStorage?.length ?? 0) > Self.debounceThreshold {
            needsFull = needsFull || pendingEdit == nil
            debounce?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.restyle() }
            debounce = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
        } else {
            restyle()
        }
    }

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        guard !stillSelecting else { return }
        if inEdit {
            // Safeguard: if an approved edit never reaches didChangeText, concealment must not stay frozen.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.inEdit else { return }
                self.inEdit = false
                self.restyleAll()
            }
        } else {
            updateConcealment()
        }
    }

    // MARK: Hidden glyphs

    func layoutManager(_ lm: NSLayoutManager, shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
                       properties props: UnsafePointer<NSLayoutManager.GlyphProperty>,
                       characterIndexes: UnsafePointer<Int>, font: NSFont, forGlyphRange range: NSRange) -> Int {
        guard let storage = lm.textStorage else { return 0 }
        var changed: [NSLayoutManager.GlyphProperty]?
        for i in 0..<range.length where storage.attribute(.mdHidden, at: characterIndexes[i], effectiveRange: nil) != nil {
            if changed == nil { changed = Array(UnsafeBufferPointer(start: props, count: range.length)) }
            changed?[i] = .null
        }
        guard let changed else { return 0 }
        changed.withUnsafeBufferPointer { buf in
            lm.setGlyphs(glyphs, properties: buf.baseAddress!, characterIndexes: characterIndexes, font: font, forGlyphRange: range)
        }
        return range.length
    }

    // MARK: Centered column

    override func setFrameSize(_ newSize: NSSize) {
        let pad = max(32, ((newSize.width - Self.column) / 2).rounded())
        if abs(textContainerInset.width - pad) > 0.5 { textContainerInset = NSSize(width: pad, height: 44) }
        super.setFrameSize(newSize)
    }

    // MARK: Decorations

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard let lm = layoutManager, let tc = textContainer, let storage = textStorage, storage.length > 0 else { return }
        let o = textContainerOrigin
        let glyphs = lm.glyphRange(forBoundingRect: rect.offsetBy(dx: -o.x, dy: -o.y), in: tc)
        guard glyphs.length > 0 else { return }
        let chars = lm.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        let all = NSRange(location: 0, length: storage.length)
        let p = palette
        var codeDone = Set<Int>()

        storage.enumerateAttribute(.mdDeco, in: chars) { value, r, _ in
            guard let kind = value as? String else { return }
            switch kind {
            case "code":
                var block = NSRange()
                _ = storage.attribute(.mdDeco, at: r.location, longestEffectiveRange: &block, in: all)
                guard codeDone.insert(block.location).inserted else { return }
                let box0 = fragments(block).reduce(NSRect.null) { $0.union($1) }
                guard !box0.isNull else { return }
                var box = box0
                box.origin.x = 0
                box.size.width = tc.size.width
                box = box.offsetBy(dx: o.x, dy: o.y).insetBy(dx: tc.lineFragmentPadding - 4, dy: 0)
                NSColor(hex: p.codeBg).setFill()
                NSBezierPath(roundedRect: box, xRadius: 10, yRadius: 10).fill()
            case let q where q.hasPrefix("quote:"):
                let parts = q.split(separator: ":")
                let depth = Int(parts[1]) ?? 1
                let color = NSColor(hex: String(parts[2]))
                for frag in fragments(r) {
                    for d in 1...max(1, depth) {
                        (d == depth ? color : NSColor(hex: p.bar)).setFill()
                        let x = o.x + tc.lineFragmentPadding + CGFloat(d - 1) * 18 + 2
                        NSRect(x: x, y: frag.minY + o.y, width: 2.5, height: frag.height).fill()
                    }
                }
            case "hr":
                guard storage.attribute(.mdHidden, at: r.location, effectiveRange: nil) != nil else { return }
                guard let frag = fragments(r).first else { return }
                NSColor(hex: p.rule).setFill()
                NSRect(x: o.x + tc.lineFragmentPadding, y: (frag.midY + o.y).rounded(), width: tc.size.width - 2 * tc.lineFragmentPadding, height: 1).fill()
            case "bullet":
                guard let (glyph, baseline, font) = glyphBox(r) else { return }
                let d: CGFloat = 5
                NSColor(hex: p.muted).setFill()
                NSBezierPath(ovalIn: NSRect(x: glyph.midX - d / 2, y: baseline - font.xHeight / 2 - d / 2, width: d, height: d)).fill()
            case "box", "boxOn":
                guard let rect = checkboxRect(r) else { return }
                let path = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
                if kind == "boxOn" {
                    NSColor(hex: p.box).setFill(); path.fill()
                    let check = NSBezierPath()
                    check.move(to: NSPoint(x: rect.minX + rect.width * 0.24, y: rect.midY + rect.height * 0.02))
                    check.line(to: NSPoint(x: rect.minX + rect.width * 0.43, y: rect.maxY - rect.height * 0.27))
                    check.line(to: NSPoint(x: rect.maxX - rect.width * 0.22, y: rect.minY + rect.height * 0.28))
                    check.lineWidth = 1.8
                    check.lineCapStyle = .round
                    check.lineJoinStyle = .round
                    NSColor(hex: p.boxFg).setStroke(); check.stroke()
                } else {
                    path.lineWidth = 1.5
                    NSColor(hex: p.bar).setStroke(); path.insetBy(0.75).stroke()
                }
            default: break
            }
        }
    }

    /// Line fragments of the lines in `r`. Computed from the first visible glyph of each line:
    /// TextKit 1 leaves the null glyphs at the start of a line (hidden markers) in the previous fragment.
    private func fragments(_ r: NSRange) -> [NSRect] {
        guard let lm = layoutManager, let storage = textStorage else { return [] }
        let ns = storage.string as NSString
        let full = ns.lineRange(for: LiveStyler.clamp(r, ns.length))
        var out: [NSRect] = []
        var loc = full.location
        while loc < NSMaxRange(full) {
            let line = ns.lineRange(for: NSRange(location: loc, length: 0))
            var glyphs = lm.glyphRange(forCharacterRange: line, actualCharacterRange: nil)
            while glyphs.length > 1, lm.propertyForGlyph(at: glyphs.location) == .null {
                glyphs.location += 1; glyphs.length -= 1
            }
            if glyphs.length > 0 {
                lm.enumerateLineFragments(forGlyphRange: glyphs) { frag, _, _, _, _ in out.append(frag) }
            }
            loc = NSMaxRange(line)
        }
        return out
    }

    /// Rect of the first glyph of `r`, its baseline (in view coordinates) and its font.
    private func glyphBox(_ r: NSRange) -> (NSRect, CGFloat, NSFont)? {
        guard let lm = layoutManager, let tc = textContainer, let storage = textStorage, r.location < storage.length else { return nil }
        let o = textContainerOrigin
        let g = lm.glyphIndexForCharacter(at: r.location)
        let rect = lm.boundingRect(forGlyphRange: lm.glyphRange(forCharacterRange: r, actualCharacterRange: nil), in: tc).offsetBy(dx: o.x, dy: o.y)
        let frag = lm.lineFragmentRect(forGlyphAt: g, effectiveRange: nil)
        let baseline = frag.minY + lm.location(forGlyphAt: g).y + o.y
        let font = (storage.attribute(.font, at: r.location, effectiveRange: nil) as? NSFont) ?? style.font(mono: false, size: style.size)
        return (rect, baseline, font)
    }

    private func checkboxRect(_ r: NSRange) -> NSRect? {
        guard let (glyph, baseline, _) = glyphBox(r) else { return nil }
        // Metrics of the normal text (the brackets use a small monospaced font so "[ ]" and "[x]" have the same width).
        let body = style.font(mono: false, size: style.size)
        let side = (body.pointSize * 0.95).rounded()
        let cy = baseline - body.capHeight / 2
        return NSRect(x: (glyph.minX + (glyph.width - side) / 2).rounded(), y: (cy - side / 2).rounded(), width: side, height: side)
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        if let (range, on) = checkbox(at: pt) {
            let sel = selectedRange()
            breakUndoCoalescing()
            apply(EditAssist.Edit(range: NSRange(location: range.location + 1, length: 1), text: on ? " " : "x", selection: sel),
                  actionName: "Toggle Task")
            return
        }
        if event.modifierFlags.contains(.command), let url = link(at: pt) {
            NSWorkspace.shared.open(url)
            return
        }
        super.mouseDown(with: event)
    }

    private func charIndex(at pt: NSPoint) -> Int? {
        guard let lm = layoutManager, let tc = textContainer, let storage = textStorage, storage.length > 0 else { return nil }
        let o = textContainerOrigin
        let local = NSPoint(x: pt.x - o.x, y: pt.y - o.y)
        let g = lm.glyphIndex(for: local, in: tc)
        let rect = lm.boundingRect(forGlyphRange: NSRange(location: g, length: 1), in: tc)
        guard rect.insetBy(dx: -2, dy: -2).contains(local) else { return nil }
        return lm.characterIndexForGlyph(at: g)
    }

    private func checkbox(at pt: NSPoint) -> (NSRange, Bool)? {
        guard let lm = layoutManager, let tc = textContainer, let storage = textStorage, storage.length > 0 else { return nil }
        let o = textContainerOrigin
        let g = lm.glyphIndex(for: NSPoint(x: pt.x - o.x, y: pt.y - o.y), in: tc)
        let line = (storage.string as NSString).lineRange(for: NSRange(location: lm.characterIndexForGlyph(at: g), length: 0))
        var found: (NSRange, Bool)?
        storage.enumerateAttribute(.mdDeco, in: line) { v, r, stop in
            guard let k = v as? String, k == "box" || k == "boxOn", let rect = checkboxRect(r),
                  rect.insetBy(dx: -4, dy: -4).contains(pt) else { return }
            let inner = (storage.string as NSString).substring(with: r)
            guard inner == "[ ]" || inner.lowercased() == "[x]" else { return }
            found = (r, k == "boxOn"); stop.pointee = true
        }
        return found
    }

    /// Link under the pointer: only http, https and mailto (same policy as the preview).
    private func link(at pt: NSPoint) -> URL? {
        guard let i = charIndex(at: pt), let raw = textStorage?.attribute(.mdLink, at: i, effectiveRange: nil) as? String,
              let safe = HTMLRenderer.safeURL(raw), let url = URL(string: safe),
              ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url
    }

    // MARK: Keyboard

    override func insertNewline(_ sender: Any?) {
        guard !inCodeBlock(), let e = EditAssist.newline(in: string as NSString, selection: selectedRange()) else {
            super.insertNewline(sender); return
        }
        apply(e, actionName: nil)
    }

    override func insertTab(_ sender: Any?) {
        guard !inCodeBlock(), let e = EditAssist.indent(in: string as NSString, selection: selectedRange(), outdent: false) else {
            super.insertTab(sender); return
        }
        apply(e, actionName: "Indent")
    }

    override func insertBacktab(_ sender: Any?) {
        guard !inCodeBlock(), let e = EditAssist.indent(in: string as NSString, selection: selectedRange(), outdent: true) else {
            super.insertBacktab(sender); return
        }
        apply(e, actionName: "Indent")
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self,
              event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
              let key = event.charactersIgnoringModifiers?.lowercased() else { return super.performKeyEquivalent(with: event) }
        switch key {
        case "b": apply(EditAssist.toggleWrap(in: string as NSString, selection: selectedRange(), marker: "**"), actionName: "Bold"); return true
        case "i": apply(EditAssist.toggleWrap(in: string as NSString, selection: selectedRange(), marker: "*"), actionName: "Italic"); return true
        default: return super.performKeyEquivalent(with: event)
        }
    }

    private func inCodeBlock() -> Bool {
        guard let storage = textStorage, storage.length > 0 else { return false }
        let i = min(selectedRange().location, storage.length - 1)
        return (storage.attribute(.mdDeco, at: i, effectiveRange: nil) as? String) == "code"
    }

    /// Applies a replacement with undo and the usual notifications.
    func apply(_ e: EditAssist.Edit, actionName: String?) {
        let r = LiveStyler.clamp(e.range, textStorage?.length ?? 0)
        guard shouldChangeText(in: r, replacementString: e.text) else { return }
        textStorage?.replaceCharacters(in: r, with: e.text)
        didChangeText()
        if let actionName { undoManager?.setActionName(actionName) }
        setSelectedRange(LiveStyler.clamp(e.selection, textStorage?.length ?? 0))
        scrollRangeToVisible(selectedRange())
    }
}

private extension NSBezierPath {
    func insetBy(_ d: CGFloat) -> NSBezierPath {
        let b = bounds.insetBy(dx: d, dy: d)
        return NSBezierPath(roundedRect: b, xRadius: 3.5, yRadius: 3.5)
    }
}
