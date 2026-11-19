import SwiftUI
import UniformTypeIdentifiers

enum ViewMode: String, CaseIterable, Identifiable {
    case write, code, split
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .write: "eye"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .split: "rectangle.split.2x1"
        }
    }
    var title: String {
        switch self { case .write: "Write"; case .code: "Markdown"; case .split: "Split" }
    }
    var help: String {
        switch self { case .write: "Write (⌘/)"; case .code: "Markdown (⌘/)"; case .split: "Split (⌥⌘/)" }
    }
    /// Valor guardado → modo (el antiguo "preview" pasa a Write).
    static func resolve(_ raw: String) -> ViewMode { ViewMode(rawValue: raw) ?? .write }
}

struct ViewModeKey: FocusedValueKey { typealias Value = Binding<String> }

extension FocusedValues {
    var viewMode: Binding<String>? {
        get { self[ViewModeKey.self] }
        set { self[ViewModeKey.self] = newValue }
    }
}

struct EditorView: View {
    @Binding var document: MarkdownDocument
    let fileURL: URL?

    @AppStorage("theme") private var themeRaw = AppTheme.default.rawValue
    @AppStorage("fontText") private var fontTextRaw = TextFont.geist.rawValue
    @AppStorage("fontCode") private var fontCodeRaw = CodeFont.geistMono.rawValue
    @AppStorage("fontSize") private var fontSize = 16.0
    @AppStorage("paper") private var paperRaw = PaperSize.a4.rawValue
    @SceneStorage("mode") private var modeRaw = ViewMode.write.rawValue
    @ObservedObject private var lock = AppLock.shared
    @State private var sync = ScrollSync()
    @State private var exportError: String?

    private var theme: AppTheme { AppTheme.resolve(themeRaw) }
    private var palette: Palette { theme.palette }
    private var fonts: FontSettings { FontSettings(textRaw: fontTextRaw, codeRaw: fontCodeRaw, size: fontSize) }
    private var paper: PaperSize { PaperSize(rawValue: paperRaw) ?? .a4 }
    private var mode: ViewMode { ViewMode.resolve(modeRaw) }
    private var bg: Color { Color(nsColor: NSColor(hex: palette.bg)) }
    private var baseDir: URL { fileURL?.deletingLastPathComponent() ?? FileManager.default.homeDirectoryForCurrentUser }

    var body: some View {
        content
            .background(bg)
            .overlay { if lock.isLocked { LockOverlay(lock: lock, palette: palette) } }
            .frame(minWidth: 560, minHeight: 360)
            // Toda la ventana (también la barra de título) usa el color del tema, como Coffee.
            .containerBackground(bg, for: .window)
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            .preferredColorScheme(theme.isDark ? .dark : .light)
            .focusedSceneValue(\.viewMode, $modeRaw)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Picker("Mode", selection: $modeRaw) {
                        ForEach(ViewMode.allCases) { m in
                            Label(m.title, systemImage: m.symbol).help(m.help).tag(m.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelStyle(.iconOnly)
                    .help("Write, Markdown or Split")
                    .disabled(lock.isLocked)

                    Menu {
                        Button("PDF…") { export(.pdf) }
                        Button("HTML…") { export(.html) }
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    .labelStyle(.titleAndIcon)
                    .help("Export as PDF or HTML")
                    .disabled(lock.isLocked)

                    Button { lock.lock() } label: {
                        Label("Lock", systemImage: lock.isLocked ? "lock.fill" : "lock")
                    }
                    .help("Lock (⌃⌘L)")
                    .disabled(lock.isLocked)
                }
            }
            .onAppear { AppearanceController.apply(theme: theme) }
            .onChange(of: themeRaw) { AppearanceController.apply(theme: theme) }
            .alert("Export failed", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(exportError ?? "") }
    }

    @ViewBuilder private var content: some View {
        switch mode {
        case .write:
            LiveEditor(text: $document.text, palette: palette, fonts: fonts)
        case .code:
            CodeEditor(text: $document.text, palette: palette, fonts: fonts)
        case .split:
            HSplitView {
                CodeEditor(text: $document.text, palette: palette, fonts: fonts, scrollSync: sync)
                    .frame(minWidth: 260)
                PreviewWebView(markdown: document.text, baseDir: baseDir,
                               themeCSS: palette.css() + fonts.css() + "main{padding:40px 36px 96px}",
                               background: NSColor(hex: palette.bg), scrollSync: sync)
                    .frame(minWidth: 260)
            }
        }
    }

    private enum ExportKind { case pdf, html }

    private func export(_ kind: ExportKind) {
        guard !lock.isLocked else { return }
        let panel = NSSavePanel()
        let base = fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled"
        panel.allowedContentTypes = [kind == .pdf ? .pdf : .html]
        panel.nameFieldStringValue = base + (kind == .pdf ? ".pdf" : ".html")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let text = document.text, dir = baseDir, css = palette.css() + fonts.css(), paper = paper, fonts = fonts
        Task {
            do {
                switch kind {
                case .pdf: try await Exporter.exportPDF(markdown: text, baseDir: dir, paper: paper, fonts: fonts, to: url)
                case .html: try await Exporter.exportHTML(markdown: text, baseDir: dir, themeCSS: css, to: url)
                }
            } catch {
                exportError = error.localizedDescription
            }
        }
    }
}

/// Comandos del menú View: alternar modos con atajos, como Coffee.
struct ModeCommands: View {
    @FocusedBinding(\.viewMode) private var mode: String?

    var body: some View {
        Button("Toggle Markdown") {
            mode = ViewMode.resolve(mode ?? "") == .code ? ViewMode.write.rawValue : ViewMode.code.rawValue
        }
        .keyboardShortcut("/", modifiers: .command)
        .disabled(mode == nil)
        Button("Toggle Split View") {
            mode = ViewMode.resolve(mode ?? "") == .split ? ViewMode.write.rawValue : ViewMode.split.rawValue
        }
        .keyboardShortcut("/", modifiers: [.command, .option])
        .disabled(mode == nil)
    }
}
