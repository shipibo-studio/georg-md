import AppKit
import UniformTypeIdentifiers
import WebKit

/// Exportación a HTML (autocontenido) y PDF paginado. Reutiliza el renderizador del preview.
@MainActor
enum Exporter {
    /// Hoja de impresión: paleta clara fija, sin márgenes de pantalla y con cortes de página razonables.
    private static func printCSS(_ fonts: FontSettings) -> String {
        AppTheme.latte.palette.css() + fonts.css(includeSize: false) + """
        html,body{-webkit-print-color-adjust:exact;print-color-adjust:exact}
        body{font-size:11pt;line-height:1.65}
        main{max-width:none;padding:0}
        main>:first-child{margin-top:0!important}
        main>:last-child{margin-bottom:0!important}
        pre,table,img,blockquote,.alert,.math,tr{break-inside:avoid}
        h1,h2,h3,h4{break-after:avoid}
        """
    }

    static func html(markdown: String, baseDir: URL, themeCSS: String) async -> String {
        await HTMLPage.render(markdown: markdown, baseDir: baseDir, extraCSS: themeCSS)
    }

    static func exportHTML(markdown: String, baseDir: URL, themeCSS: String, to url: URL) async throws {
        let page = await html(markdown: markdown, baseDir: baseDir, themeCSS: themeCSS)
        try Data(page.utf8).write(to: url, options: .atomic)
    }

    static func exportPDF(markdown: String, baseDir: URL, paper: PaperSize, fonts: FontSettings = FontSettings(), to url: URL) async throws {
        // En papel no se puede desplegar un <details>: se exporta abierto. Es seguro reemplazar el texto
        // porque RawHTML solo emite la etiqueta literal `<details>` (en el texto del usuario va escapada como &lt;).
        let page = await HTMLPage.render(markdown: markdown, baseDir: baseDir, extraCSS: printCSS(fonts))
            .replacingOccurrences(of: "<details>", with: "<details open>")
        let margin: CGFloat = 54
        let content = NSSize(width: paper.size.width - margin * 2, height: paper.size.height - margin * 2)

        let cfg = WKWebViewConfiguration()
        cfg.defaultWebpagePreferences.allowsContentJavaScript = false
        cfg.websiteDataStore = .nonPersistent()
        // Sin esto WebKit omite fondos al imprimir (bloques de código, avisos, casillas marcadas).
        cfg.preferences.shouldPrintBackgrounds = true
        let wv = WKWebView(frame: NSRect(origin: .zero, size: content), configuration: cfg)
        // Ventana fuera de pantalla: WebKit necesita una jerarquía de vistas para paginar.
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -20000, y: -20000), size: content),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = wv

        let loader = LoadWaiter()
        wv.navigationDelegate = loader
        try await loader.load(html: page, in: wv)

        let info = NSPrintInfo()
        info.paperSize = paper.size
        info.topMargin = margin; info.bottomMargin = margin; info.leftMargin = margin; info.rightMargin = margin
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url

        let op = wv.printOperation(with: info)
        op.showsPrintPanel = false
        op.showsProgressPanel = false
        op.view?.frame = NSRect(origin: .zero, size: content)
        let ok = await PrintRunner().run(op, window: window)
        window.close()
        guard ok, FileManager.default.fileExists(atPath: url.path) else {
            throw CocoaError(.fileWriteUnknown)
        }
    }
}

@MainActor
private final class LoadWaiter: NSObject, WKNavigationDelegate {
    private var cont: CheckedContinuation<Void, Error>?

    func load(html: String, in wv: WKWebView) async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            cont = c
            wv.loadHTMLString(html, baseURL: nil)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { cont?.resume(); cont = nil }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { cont?.resume(throwing: error); cont = nil }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { cont?.resume(throwing: error); cont = nil }
}

@MainActor
private final class PrintRunner: NSObject {
    private var cont: CheckedContinuation<Bool, Never>?

    func run(_ op: NSPrintOperation, window: NSWindow) async -> Bool {
        await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            cont = c
            op.runModal(for: window, delegate: self, didRun: #selector(didRun(_:success:contextInfo:)), contextInfo: nil)
        }
    }

    @objc func didRun(_ op: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?) {
        cont?.resume(returning: success); cont = nil
    }
}
