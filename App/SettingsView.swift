import AppKit
import SwiftUI

struct SettingsView: View {
    @AppStorage("theme") private var themeRaw = AppTheme.default.rawValue
    @AppStorage("fontText") private var fontTextRaw = TextFont.geist.rawValue
    @AppStorage("fontCode") private var fontCodeRaw = CodeFont.geistMono.rawValue
    @AppStorage("fontSize") private var fontSize = 16.0
    @AppStorage("paper") private var paperRaw = PaperSize.a4.rawValue
    @AppStorage(AppLock.minutesKey) private var lockMinutes = 0
    @State private var copied = false
    @StateObject private var updates = UpdateChecker()
    @State private var defaultApp: URL? = DefaultApp.current
    @State private var defaultError: String?

    private var theme: AppTheme { AppTheme.resolve(themeRaw) }
    private var fonts: FontSettings { FontSettings(textRaw: fontTextRaw, codeRaw: fontCodeRaw, size: fontSize) }

    /// Command to link the `georg` tool (paths in single quotes, escaped).
    static var cliCommand: String {
        let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/georg").path
        let quoted = "'" + helper.replacingOccurrences(of: "'", with: "'\\''") + "'"
        return "sudo mkdir -p /usr/local/bin && sudo ln -sf \(quoted) /usr/local/bin/georg"
    }

    var body: some View {
        Form {
            Section("About") {
                LabeledContent("Georg md") {
                    Text("Version \(UpdateChecker.current) (\(UpdateChecker.build))").foregroundStyle(.secondary).textSelection(.enabled)
                }
                LabeledContent {
                    Button("Check for Updates") { Task { await updates.check() } }
                        .disabled(updates.state == .checking)
                } label: {
                    updateStatus
                }
            }

            Section("Default App") {
                LabeledContent {
                    Button("Make Default") {
                        Task {
                            do { try await DefaultApp.makeDefault(); defaultError = nil }
                            catch { defaultError = error.localizedDescription }
                            defaultApp = DefaultApp.current
                        }
                    }
                    .disabled(isDefaultApp)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(isDefaultApp ? "Georg md opens your Markdown files."
                             : "Markdown files open with \(defaultApp.map { $0.deletingPathExtension().lastPathComponent } ?? "no app").")
                        if let defaultError { Text(defaultError).font(.caption).foregroundStyle(.red) }
                    }
                }
            }

            Section("Theme") {
                swatches("Light", AppTheme.light)
                swatches("Dark", AppTheme.dark)
            }

            Section("Font") {
                Picker("Text", selection: $fontTextRaw) {
                    ForEach(TextFont.allCases) { Text($0.title).tag($0.rawValue) }
                }
                Picker("Code", selection: $fontCodeRaw) {
                    ForEach(CodeFont.allCases) { Text($0.title).tag($0.rawValue) }
                }
                LabeledContent("Size") {
                    HStack {
                        Slider(value: $fontSize, in: FontSettings.sizes, step: 1).frame(maxWidth: 200)
                        Text("\(Int(fontSize)) pt").monospacedDigit().foregroundStyle(.secondary).frame(width: 40, alignment: .trailing)
                    }
                }
                sample
            }

            Section("Privacy") {
                Picker("Lock after inactivity", selection: $lockMinutes) {
                    Text("Never").tag(0)
                    ForEach(AppLock.choices.filter { $0 > 0 }, id: \.self) { m in Text("\(m) min").tag(m) }
                }
                LabeledContent {
                    Button("Lock Now") { AppLock.shared.lock() }
                } label: {
                    Text("Hides open documents until you unlock with Touch ID or your Mac password. Also locks when the Mac sleeps. Files on disk are not encrypted.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }

            Section("Export") {
                Picker("PDF page size", selection: $paperRaw) {
                    ForEach(PaperSize.allCases) { p in Text(p.title).tag(p.rawValue) }
                }
                .pickerStyle(.segmented)
            }

            Section("Command Line") {
                Text("Open files from Terminal with `georg notes.md` (creates the file if it doesn't exist). Run this once in Terminal:")
                    .font(.callout).foregroundStyle(.secondary)
                HStack(alignment: .top) {
                    Text(Self.cliCommand)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button(copied ? "Copied" : "Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(Self.cliCommand, forType: .string)
                        copied = true
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 540, height: 680)
        .onAppear {
            AppearanceController.apply(theme: theme)
            defaultApp = DefaultApp.current
        }
    }

    private var isDefaultApp: Bool {
        guard let url = defaultApp, let id = Bundle(url: url)?.bundleIdentifier else { return false }
        return id == Bundle.main.bundleIdentifier
    }

    @ViewBuilder private var updateStatus: some View {
        switch updates.state {
        case .idle:
            Text("Checks GitHub for a newer signed release.").font(.callout).foregroundStyle(.secondary)
        case .checking:
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Checking…").foregroundStyle(.secondary) }
        case .upToDate(let v):
            Label("Georg md \(v) is up to date.", systemImage: "checkmark.circle").foregroundStyle(.secondary)
        case .available(let v, let page, let download):
            HStack {
                Label("Version \(v) is available.", systemImage: "arrow.down.circle")
                Button("Download") { NSWorkspace.shared.open(download ?? page) }
                Button("Release Notes") { NSWorkspace.shared.open(page) }.buttonStyle(.link)
            }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary)
        }
    }

    private func swatches(_ title: String, _ themes: [AppTheme]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(104), spacing: 10), count: 4), alignment: .leading, spacing: 12) {
                ForEach(themes) { t in
                    ThemeSwatch(theme: t, selected: t == theme) {
                        themeRaw = t.rawValue
                        AppearanceController.apply(theme: t)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var sample: some View {
        let p = theme.palette
        return VStack(alignment: .leading, spacing: 6) {
            Text("The quick brown fox jumps over the lazy dog.")
                .font(Font(fonts.font(mono: false, size: CGFloat(fontSize))))
            Text("let coffee = \"latte\" // code")
                .font(Font(fonts.font(mono: true, size: MarkdownStyler.size(fonts))))
                .foregroundStyle(Color(nsColor: NSColor(hex: p.muted)))
        }
        .foregroundStyle(Color(nsColor: NSColor(hex: p.fg)))
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: NSColor(hex: p.bg))))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.25)))
    }
}

private struct ThemeSwatch: View {
    let theme: AppTheme
    let selected: Bool
    let action: () -> Void

    var body: some View {
        let p = theme.palette
        Button(action: action) {
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: NSColor(hex: p.bg)))
                    .frame(width: 96, height: 44)
                    .overlay(
                        HStack(spacing: 5) {
                            ForEach([p.fg, p.accent, p.codeFg, p.muted], id: \.self) { c in
                                Circle().fill(Color(nsColor: NSColor(hex: c))).frame(width: 9, height: 9)
                            }
                        }
                    )
                    .overlay(RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(selected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: selected ? 2 : 1))
                Text(theme.title).font(.caption).fontWeight(selected ? .semibold : .regular)
            }
        }
        .buttonStyle(.plain)
        .help(theme.title)
    }
}
