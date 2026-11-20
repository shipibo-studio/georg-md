import AppKit
import WebKit

/// Proportional scrolling between the Markdown editor and the preview in Split mode.
///
/// The preview runs no page JavaScript: the position is read and set with `evaluateJavaScript` in the
/// isolated `.defaultClient` world, only with numbers computed here (never document content).
/// WKWebView on macOS does not expose its scrolling, so preview scrolling is detected with a local
/// monitor of scroll-wheel/trackpad events over the view.
@MainActor
final class ScrollSync {
    private weak var editor: NSScrollView?
    private weak var preview: WKWebView?
    private var applyingToEditor = false
    private var queryInFlight = false
    private var queryPending = false
    private nonisolated(unsafe) var monitor: Any?
    private nonisolated(unsafe) var observer: NSObjectProtocol?

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func attach(editor scroll: NSScrollView) {
        editor = scroll
        if let observer { NotificationCenter.default.removeObserver(observer) }
        scroll.contentView.postsBoundsChangedNotifications = true
        observer = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification,
                                                          object: scroll.contentView, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.editorDidScroll() }
        }
    }

    func attach(preview wv: WKWebView) {
        preview = wv
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            let windowNumber = event.windowNumber, location = event.locationInWindow
            MainActor.assumeIsolated {
                guard let self, let wv = self.preview, let window = wv.window, window.windowNumber == windowNumber else { return }
                if wv.bounds.contains(wv.convert(location, from: nil)) { self.previewDidScroll() }
            }
            return event
        }
    }

    func detach() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        if let observer { NotificationCenter.default.removeObserver(observer) }
        monitor = nil; observer = nil
    }

    /// Current editor fraction (0…1), to reposition the preview after reloading it.
    var editorFraction: Double? {
        guard let s = editor, let doc = s.documentView else { return nil }
        let span = doc.frame.height - s.contentView.bounds.height
        guard span > 1 else { return 0 }
        return Double(s.contentView.bounds.origin.y / span)
    }

    // MARK: Editor → preview

    private func editorDidScroll() {
        guard !applyingToEditor, let f = editorFraction else { return }
        scrollPreview(to: f)
    }

    func scrollPreview(to fraction: Double) {
        guard let wv = preview, fraction.isFinite else { return }
        let f = String(format: "%.6f", min(max(fraction, 0), 1))
        let js = "window.scrollTo(0, Math.max(0, document.documentElement.scrollHeight - window.innerHeight) * \(f))"
        wv.evaluateJavaScript(js, in: nil, in: .defaultClient, completionHandler: nil)
    }

    // MARK: Preview → editor

    private func previewDidScroll() {
        // Applied after WebKit processes the event; queries are coalesced to avoid flooding.
        if queryInFlight { queryPending = true; return }
        queryInFlight = true
        DispatchQueue.main.async { [weak self] in self?.queryPreview() }
    }

    private func queryPreview() {
        guard let wv = preview else { queryInFlight = false; return }
        let js = "[window.scrollY, Math.max(0, document.documentElement.scrollHeight - window.innerHeight)]"
        wv.evaluateJavaScript(js, in: nil, in: .defaultClient) { [weak self] result in
            guard let self else { return }
            if case .success(let value) = result, let arr = value as? [NSNumber], arr.count == 2 {
                let y = arr[0].doubleValue, span = arr[1].doubleValue
                self.scrollEditor(to: span > 1 ? y / span : 0)
            }
            self.queryInFlight = false
            if self.queryPending { self.queryPending = false; self.previewDidScroll() }
        }
    }

    private func scrollEditor(to fraction: Double) {
        guard let s = editor, let doc = s.documentView, fraction.isFinite else { return }
        let span = doc.frame.height - s.contentView.bounds.height
        guard span > 1 else { return }
        applyingToEditor = true
        let f = CGFloat(min(max(fraction, 0), 1))
        s.contentView.scroll(to: NSPoint(x: s.contentView.bounds.origin.x, y: (f * span).rounded()))
        s.reflectScrolledClipView(s.contentView)
        applyingToEditor = false
    }
}
