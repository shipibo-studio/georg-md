import Foundation
import Markdown

private struct ImageCollector: MarkupWalker {
    var sources: [String] = []
    mutating func visitImage(_ image: Image) {
        if let s = image.source, !s.isEmpty { sources.append(s) }
    }
    mutating func visitInlineHTML(_ h: InlineHTML) { sources += RawHTML.imageSources(in: h.rawHTML) }
    mutating func visitHTMLBlock(_ h: HTMLBlock) { sources += RawHTML.imageSources(in: h.rawHTML) }
}

/// Lets us locate the bundle (app or extension) that compiles this file, to load the fonts.
private final class BundleToken {}

enum HTMLPage {
    static func render(markdown: String, baseDir: URL, extraCSS: String = "") async -> String {
        let (front, body) = splitFrontMatter(markdown)
        // Trims pathological nesting before parsing (avoids overflowing the stack; see MarkdownLimits).
        let (stripped, maths) = MathExtractor.extract(MarkdownLimits.capNesting(body))
        let document = Document(parsing: stripped)
        var collector = ImageCollector()
        collector.visit(document)
        let images = await ImageLoader.load(collector.sources, baseDir: baseDir)
        var renderer = HTMLRenderer(images: images)
        let content = MathExtractor.restore(renderer.visit(document), maths)
        let fm = front.map { "<pre class=\"front\"><code>\(HTMLRenderer.escape($0))</code></pre>\n" } ?? ""

        // CSP: no scripts, no network; only inline styles, fonts and embedded data.
        return """
        <!doctype html>
        <html lang="en"><head><meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; font-src data:; img-src data:">
        <meta name="color-scheme" content="light dark">
        <style>\(fontFaces)\(css)\(extraCSS)</style></head>
        <body><main>\(fm)\(content)</main></body></html>
        """
    }

    /// Splits off a leading YAML block delimited by `---`.
    private static func splitFrontMatter(_ s: String) -> (String?, String) {
        guard s.hasPrefix("---\n") || s.hasPrefix("---\r\n") else { return (nil, s) }
        let lines = s.split(separator: "\n", omittingEmptySubsequences: false)
        guard let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) else {
            return (nil, s)
        }
        let front = lines[1..<end].joined(separator: "\n")
        let rest = lines[(end + 1)...].joined(separator: "\n")
        return (front, rest)
    }

    private static let fontFaces: String = {
        func face(_ name: String, family: String) -> String {
            guard let url = Bundle(for: BundleToken.self).url(forResource: name, withExtension: "ttf"),
                  let data = try? Data(contentsOf: url) else { return "" }
            return "@font-face{font-family:'\(family)';font-weight:100 900;src:url(data:font/ttf;base64,\(data.base64EncodedString())) format('truetype')}\n"
        }
        return face("Geist-Variable", family: "Geist") + face("GeistMono-Variable", family: "Geist Mono")
    }()

    private static let css = """
    :root{--k:#a2432b;--s:#3f7a3a;--c:#8b867c;--n:#9a5b00;--f:#1f6c8a;--t:#7a4a96;--bg:#ffffff;--fg:#141414;--muted:#6f6e6b;--rule:#e6e5e2;--code-bg:#f4f4f1;--code-fg:#141414;--accent:#8a5a2b;--bar:#d6d5d1;--box:#141414;--box-fg:#fff}
    @media (prefers-color-scheme: dark){:root{--k:#e0905f;--s:#a9c27c;--c:#7f786d;--n:#dbaa6a;--f:#7fb7cd;--t:#c9a6d8;--bg:#1b1a18;--fg:#ece6dc;--muted:#8f887d;--rule:#34312c;--code-bg:#252421;--code-fg:#d9a869;--accent:#d9a869;--bar:#4a463f;--box:#ece6dc;--box-fg:#1b1a18}}
    *{box-sizing:border-box}
    html{background:var(--bg)}
    body{margin:0;background:var(--bg);color:var(--fg);font:17px/1.75 'Geist',-apple-system,system-ui,sans-serif;-webkit-font-smoothing:antialiased}
    main{max-width:660px;margin:0 auto;padding:56px 40px 96px}
    h1,h2,h3,h4,h5,h6{line-height:1.2;font-weight:700;letter-spacing:-.025em;margin:2em 0 .55em}
    h1{font-size:2.35em;margin-top:0;letter-spacing:-.035em;line-height:1.1}
    h2{font-size:1.55em;font-weight:650}
    h3{font-size:1.25em;font-weight:650}
    h4,h5,h6{font-size:1em;color:var(--muted)}
    p{margin:1em 0}
    a{color:var(--accent);text-decoration:underline;text-decoration-thickness:1px;text-decoration-color:color-mix(in srgb,var(--accent) 45%,transparent);text-underline-offset:3px}
    code{font:.86em 'Geist Mono',ui-monospace,Menlo,monospace;background:var(--code-bg);color:var(--code-fg);padding:.18em .45em;border-radius:6px}
    pre{position:relative;background:var(--code-bg);border-radius:14px;padding:22px 26px;overflow-x:auto;margin:1.5em 0}
    pre code{background:none;padding:0;font-size:.86em;line-height:1.85;white-space:pre;color:var(--fg);opacity:.92}
    pre .lang{position:absolute;top:12px;right:18px;font:12px 'Geist Mono',monospace;color:var(--muted);text-transform:uppercase;letter-spacing:.08em}
    pre.front{padding:14px 20px;margin:0 0 2.2em;border-radius:12px}
    pre.front code{font-size:.76em;line-height:1.6;color:var(--muted)}
    blockquote{margin:1.4em 0;padding:.05em 0 .05em 1.3em;border-left:2px solid var(--bar);color:var(--muted)}
    blockquote p{margin:.5em 0}
    hr{border:0;border-top:1px solid var(--rule);margin:2.6em 0}
    ul,ol{padding-left:1.4em;margin:1em 0}
    li{margin:.4em 0;padding-left:.2em}
    li::marker{color:var(--muted)}
    li.task{list-style:none;margin-left:-1.6em}
    li>p{margin:0}
    li.task>p:first-of-type{display:inline}
    li>ul,li>ol{margin:.3em 0}
    .box{display:inline-block;width:1.15em;height:1.15em;border:1.5px solid var(--bar);border-radius:5px;margin-right:.65em;vertical-align:-.22em;text-align:center;font-size:.85em;line-height:1.05em}
    .box.on{background:var(--box);border-color:var(--box);color:var(--box-fg);font-weight:700}
    li.task:has(.box.on){color:var(--muted)}
    .table-wrap{overflow-x:auto;margin:1.6em 0}
    table{border-collapse:collapse;width:100%;font-size:.97em}
    th,td{padding:10px 20px;border-bottom:1px solid var(--rule);text-align:left;vertical-align:middle}
    th{font-weight:650;border-bottom:2px solid var(--rule);padding-top:14px}
    td p{margin:0}
    del{color:var(--muted)}
    code,kbd,pre{font-variant-ligatures:none;font-feature-settings:"liga" 0,"calt" 0}
    pre code .k{color:var(--k)} pre code .s{color:var(--s)} pre code .n{color:var(--n)}
    pre code .f{color:var(--f)} pre code .t{color:var(--t)} pre code .c{color:var(--c);font-style:italic}
    .math{margin:1.6em 0;overflow-x:auto;text-align:center}
    math{font-family:'STIX Two Math','Latin Modern Math','Cambria Math',math,serif;font-size:1.12em}
    .math math{font-size:1.25em}
    .math-inline math{font-size:1.05em}
    mark{background:#f6e58d55;color:inherit;border-radius:3px;padding:0 .15em}
    .img{color:var(--muted);font-size:.9em}
    img{max-width:100%;height:auto;vertical-align:middle}
    p>img:only-child{display:block;margin:1.5em 0;border-radius:10px}
    p[style*="center"]>img:only-child{margin-left:auto;margin-right:auto}
    p[style*="right"]>img:only-child{margin-left:auto;margin-right:0}
    details{margin:1.1em 0}
    summary{cursor:pointer;font-weight:600}
    kbd{font:.8em 'Geist Mono',ui-monospace,monospace;border:1px solid var(--rule);border-bottom-width:2px;border-radius:6px;padding:.1em .45em;background:var(--code-bg)}
    .alert{--a:#4c8bf5;margin:1.5em 0;padding:14px 20px;border-radius:12px;background:var(--code-bg);border-left:3px solid var(--a)}
    .alert.tip{--a:#3fa468} .alert.important{--a:#9a6cf0} .alert.warning{--a:#d19a2a} .alert.caution{--a:#e0614f}
    .alert p{margin:.45em 0}
    .alert-title{font-weight:650;color:var(--a);margin:.1em 0 .2em}
    """
}
