import AppKit
import CoreText
import SwiftUI

@main
struct GeorgMDApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    init() {
        // Registra Geist para el editor (solo en este proceso).
        for name in ["Geist-Variable", "GeistMono-Variable"] {
            if let url = Bundle.main.url(forResource: name, withExtension: "ttf") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }

    var body: some Scene {
        DocumentGroup(newDocument: MarkdownDocument()) { file in
            EditorView(document: file.$document, fileURL: file.fileURL)
        }
        .defaultSize(width: 1100, height: 760)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .toolbar) { ModeCommands() }
            CommandGroup(after: .appSettings) {
                Button("Lock Now") { AppLock.shared.lock() }
                    .keyboardShortcut("l", modifiers: [.command, .control])
            }
        }

        Settings { SettingsView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Modo de pruebas (solo Debug): con MDQ_EXPORT_IN y MDQ_EXPORT_OUT genera el PDF y termina.
    /// Se usan variables de entorno porque macOS trata los argumentos con rutas como documentos a abrir.
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            AppLock.shared.start()
            AppearanceController.apply(theme: AppTheme.resolve(UserDefaults.standard.string(forKey: "theme") ?? ""))
        }
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        guard let inPath = env["MDQ_EXPORT_IN"], let outPath = env["MDQ_EXPORT_OUT"] else { return }
        let input = URL(fileURLWithPath: inPath), output = URL(fileURLWithPath: outPath)
        Task { @MainActor in
            do {
                let text = try String(contentsOf: input, encoding: .utf8)
                try await Exporter.exportPDF(markdown: text, baseDir: input.deletingLastPathComponent(), paper: .a4, to: output)
                print("PDF OK \(output.path)")
                exit(0)
            } catch {
                print("PDF ERROR \(error)")
                exit(1)
            }
        }
        #endif
    }
}
