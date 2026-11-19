import AppKit
import SwiftUI
import WebKit

/// Preview HTML renderizado con el mismo motor que la extensión de Quick Look.
/// Seguridad: JavaScript de contenido desactivado, almacenamiento no persistente y navegación bloqueada
/// (los enlaces http/https/mailto se abren en el navegador, nunca dentro de la vista).
struct PreviewWebView: NSViewRepresentable {
    let markdown: String
    let baseDir: URL
    let themeCSS: String
    let background: NSColor
    var scrollSync: ScrollSync?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.defaultWebpagePreferences.allowsContentJavaScript = false
        cfg.websiteDataStore = .nonPersistent()
        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.navigationDelegate = context.coordinator
        wv.underPageBackgroundColor = background
        context.coordinator.webView = wv
        context.coordinator.scrollSync = scrollSync
        scrollSync?.attach(preview: wv)
        return wv
    }

    func updateNSView(_ wv: WKWebView, context: Context) {
        wv.underPageBackgroundColor = background
        context.coordinator.schedule(markdown: markdown, baseDir: baseDir, themeCSS: themeCSS)
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        weak var webView: WKWebView?
        var scrollSync: ScrollSync?
        private var task: Task<Void, Never>?
        private var lastKey = ""
        private var pendingScroll: Double?

        func schedule(markdown: String, baseDir: URL, themeCSS: String) {
            let key = "\(markdown.hashValue)|\(baseDir.path)|\(themeCSS)"
            guard key != lastKey else { return }
            lastKey = key
            task?.cancel()
            task = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(140))
                guard !Task.isCancelled else { return }
                let html = await HTMLPage.render(markdown: markdown, baseDir: baseDir, extraCSS: themeCSS)
                guard !Task.isCancelled, let self, let wv = self.webView else { return }
                // Conserva la posición de scroll al recargar mientras se escribe.
                let y = try? await wv.evaluateJavaScript("window.scrollY") as? Double
                self.pendingScroll = y
                wv.loadHTMLString(html, baseURL: nil)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if let sync = scrollSync, let f = sync.editorFraction {
                // En Split el preview sigue la posición del editor.
                sync.scrollPreview(to: f)
            } else if let y = pendingScroll, y > 0 {
                webView.evaluateJavaScript("window.scrollTo(0, \(Int(y)))", completionHandler: nil)
            }
            pendingScroll = nil
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url,
               ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") {
                NSWorkspace.shared.open(url)
            }
            decisionHandler(navigationAction.navigationType == .other ? .allow : .cancel)
        }
    }
}
