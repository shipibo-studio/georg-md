import AppKit
import SwiftUI

/// Envoltorio SwiftUI del modo "Escribir" (LiveTextView).
struct LiveEditor: NSViewRepresentable {
    @Binding var text: String
    var palette: Palette
    var fonts: FontSettings

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let (scroll, tv) = LiveTextView.makeScrollable(palette: palette)
        tv.fonts = fonts
        tv.delegate = context.coordinator
        tv.setMarkdown(text)
        tv.setSelectedRange(NSRange(location: 0, length: 0))
        context.coordinator.textView = tv
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let c = context.coordinator
        c.parent = self
        guard let tv = c.textView else { return }
        if tv.palette != palette { tv.palette = palette }
        if tv.fonts != fonts { tv.fonts = fonts }
        // Cambio externo (p. ej. revertir a una versión): se recarga todo el texto.
        if tv.string != text { tv.setMarkdown(text) }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: LiveEditor
        weak var textView: LiveTextView?

        init(_ parent: LiveEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = textView else { return }
            parent.text = tv.string
        }
    }
}
