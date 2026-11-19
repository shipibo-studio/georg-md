import AppKit
import SwiftUI
import Markdown
import PDFKit

// Development tool (not distributed or embedded in the app).
// Not sandboxed so it can write to working paths without touching the app's container.
// Usage (environment variables, because AppKit interprets path arguments as documents):
//   MDQ_IN=samples/test.md MDQ_OUT=/tmp/out MDQ_TASK=pdf   → out.pdf + out-pN.png per page
//   MDQ_TASK=html                                           → out.html
//   MDQ_TASK=ast                                            → swift-markdown tree with ranges
//   MDQ_TASK=live [MDQ_THEME=…] [MDQ_CARET=n]                → out.png of Write mode
//   MDQ_TASK=test  (MDQ_IN = any .md in samples/)            → Write mode tests

@MainActor
func runTask() async -> Int32 {
    let env = ProcessInfo.processInfo.environment
    guard let inPath = env["MDQ_IN"], let outBase = env["MDQ_OUT"] else {
        print("Missing MDQ_IN / MDQ_OUT"); return 2
    }
    let input = URL(fileURLWithPath: inPath).standardizedFileURL
    let out = URL(fileURLWithPath: outBase)
    guard let text = try? String(contentsOf: input, encoding: .utf8) else { print("Not UTF-8"); return 1 }
    let dir = input.deletingLastPathComponent()
    do {
        switch env["MDQ_TASK"] ?? "pdf" {
        case "ast":
            print(Document(parsing: text).debugDescription(options: .printSourceLocations))
        case "perf":
            let style = LiveStyle(p: AppTheme.default.palette)
            var t = Date()
            func lap(_ n: String) { print(String(format: "%@ %.3fs", n, Date().timeIntervalSince(t))); t = Date() }
            let parsed = LiveStyler.parse(text); lap("parse")
            let st = NSTextStorage(string: text); lap("storage")
            st.beginEditing()
            LiveStyler.apply(to: st, parsed: parsed, region: NSRange(location: 0, length: st.length), style: style); lap("apply")
            LiveStyler.conceal(st, in: NSRange(location: 0, length: st.length), active: NSRange(location: 0, length: 0)); lap("conceal")
            st.endEditing(); lap("endEditing")
        case "deco":
            let st = LiveChecks.styled(text, LiveStyle(p: AppTheme.default.palette))
            st.enumerateAttribute(.mdDeco, in: NSRange(location: 0, length: st.length)) { v, r, _ in
                if let v { print(v, r, (st.string as NSString).substring(with: r).debugDescription) }
            }
        case "depth":
            // Parses and renders on a thread with a 512 KB stack (like a secondary thread of the extension).
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                let th = Thread {
                    let d = Document(parsing: MarkdownLimits.capNesting(text))
                    var r = HTMLRenderer(images: [:])
                    print("OK", r.visit(d).count)
                    c.resume()
                }
                th.stackSize = 512 * 1024
                th.start()
            }
        case "settings", "code":
            // Screenshot of Settings or of the Markdown editor (MDQ_THEME, MDQ_FONT, MDQ_SIZE as in "live").
            let theme = AppTheme.resolve(env["MDQ_THEME"] ?? "latte")
            UserDefaults.standard.set(theme.rawValue, forKey: "theme")
            NSApp.appearance = NSAppearance(named: theme.isDark ? .darkAqua : .aqua)
            let fonts = FontSettings(textRaw: env["MDQ_FONT"] ?? "geist", codeRaw: env["MDQ_CODEFONT"] ?? "geistMono",
                                     size: Double(env["MDQ_SIZE"] ?? "") ?? 16)
            let size = env["MDQ_TASK"] == "settings" ? NSSize(width: 540, height: 1180) : NSSize(width: 900, height: 900)
            let root: AnyView = env["MDQ_TASK"] == "settings"
                ? AnyView(SettingsView().frame(height: 1180))
                : AnyView(CodeEditor(text: .constant(text), palette: theme.palette, fonts: fonts))
            let host = NSHostingView(rootView: root)
            host.frame = NSRect(origin: .zero, size: size)
            let window = NSWindow(contentRect: NSRect(x: -30000, y: -30000, width: size.width, height: size.height),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSApp.appearance
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(300))
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return 1 }
            host.cacheDisplay(in: host.bounds, to: rep)
            let url = out.appendingPathExtension("png")
            try rep.representation(using: .png, properties: [:])?.write(to: url)
            window.close()
            print("PNG OK \(url.path)")
        case "test":
            return LiveChecks.runAll(samplesDir: dir)
        case "live":
            // MDQ_THEME=<theme>, MDQ_FONT=<TextFont>, MDQ_CODEFONT=<CodeFont>, MDQ_SIZE=n, MDQ_CARET=line (1-based)
            let theme = AppTheme.resolve(env["MDQ_THEME"] ?? "latte")
            let palette = theme.palette
            let fonts = FontSettings(textRaw: env["MDQ_FONT"] ?? "geist", codeRaw: env["MDQ_CODEFONT"] ?? "geistMono",
                                     size: Double(env["MDQ_SIZE"] ?? "") ?? 16)
            let url = out.appendingPathExtension("png")
            try LiveChecks.render(text: text, palette: palette, fonts: fonts, width: CGFloat(Double(env["MDQ_WIDTH"] ?? "") ?? 1000),
                                  caretLine: env["MDQ_CARET"].flatMap { Int($0) }, to: url)
            print("LIVE OK \(url.path)")
        case "html":
            let url = out.appendingPathExtension("html")
            try await Exporter.exportHTML(markdown: text, baseDir: dir, themeCSS: "", to: url)
            print("HTML OK \(url.path)")
        default:
            let paper: PaperSize = env["MDQ_PAPER"] == "letter" ? .letter : .a4
            let url = out.appendingPathExtension("pdf")
            try await Exporter.exportPDF(markdown: text, baseDir: dir, paper: paper, to: url)
            guard let pdf = PDFDocument(url: url) else { print("Unreadable PDF"); return 1 }
            print("PDF OK \(url.path) pages=\(pdf.pageCount) text=\(pdf.string?.count ?? 0)")
            for i in 0..<pdf.pageCount {
                guard let page = pdf.page(at: i) else { continue }
                let box = page.bounds(for: .mediaBox)
                let img = page.thumbnail(of: NSSize(width: box.width * 1.5, height: box.height * 1.5), for: .mediaBox)
                if let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                   let png = rep.representation(using: .png, properties: [:]) {
                    try png.write(to: URL(fileURLWithPath: "\(outBase)-p\(i + 1).png"))
                }
            }
        }
        return 0
    } catch {
        print("ERROR \(error)"); return 1
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
for name in ["Geist-Variable", "GeistMono-Variable"] {
    if let url = Bundle.main.url(forResource: name, withExtension: "ttf") {
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
}
Task { @MainActor in exit(await runTask()) }
app.run()
