import AppKit
import CoreText
import SwiftUI

@main
struct GeorgMDApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    init() {
        // Registers Geist for the editor (in this process only).
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
    /// Test mode (Debug only): with MDQ_EXPORT_IN and MDQ_EXPORT_OUT, generates the PDF and exits.
    /// Environment variables are used because macOS treats path arguments as documents to open.
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            AppLock.shared.start()
            DefaultApp.claimOnFirstLaunch()
            AppearanceController.apply(theme: AppTheme.resolve(UserDefaults.standard.string(forKey: "theme") ?? ""))
        }
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        // Test (Debug only): can the sandboxed app set itself as the default for Markdown?
        if env["GMD_TEST_DEFAULT"] != nil {
            Task { @MainActor in
                do {
                    try await DefaultApp.makeDefault()
                    print("DEFAULT OK isDefault=\(DefaultApp.isDefault) current=\(DefaultApp.current?.path ?? "-")")
                    exit(0)
                } catch {
                    print("DEFAULT ERROR \(error)")
                    exit(1)
                }
            }
            return
        }
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
