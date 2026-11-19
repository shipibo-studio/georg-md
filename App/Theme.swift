import AppKit
import SwiftUI

/// Paleta única: alimenta el CSS del preview y los colores de los editores.
struct Palette: Equatable {
    var dark: Bool
    var bg, fg, muted, rule, codeBg, codeFg, accent, bar, box, boxFg: String

    // Colores de sintaxis según claro/oscuro.
    var k: String { dark ? "#e0905f" : "#a2432b" }
    var s: String { dark ? "#a9c27c" : "#3f7a3a" }
    var c: String { dark ? "#7f786d" : "#8b867c" }
    var n: String { dark ? "#dbaa6a" : "#9a5b00" }
    var f: String { dark ? "#7fb7cd" : "#1f6c8a" }
    var t: String { dark ? "#c9a6d8" : "#7a4a96" }

    func css() -> String {
        ":root{--bg:\(bg);--fg:\(fg);--muted:\(muted);--rule:\(rule);--code-bg:\(codeBg);--code-fg:\(codeFg);"
        + "--accent:\(accent);--bar:\(bar);--box:\(box);--box-fg:\(boxFg);"
        + "--k:\(k);--s:\(s);--c:\(c);--n:\(n);--f:\(f);--t:\(t)}"
        + "html{color-scheme:\(dark ? "dark" : "light")}"
    }
}

/// Temas fijos (cada uno es claro u oscuro; la apariencia del sistema no interviene).
enum AppTheme: String, CaseIterable, Identifiable {
    case latte, paper, matcha, snow, rose, sky
    case roast, espresso, midnight, graphite, forest, plum, ink

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    static let light: [AppTheme] = allCases.filter { !$0.isDark }
    static let dark: [AppTheme] = allCases.filter(\.isDark)
    static let `default` = AppTheme.latte

    var isDark: Bool {
        switch self {
        case .latte, .paper, .matcha, .snow, .rose, .sky: false
        default: true
        }
    }

    /// Valor guardado → tema. Migra el antiguo "coffee" (que seguía al sistema) según la apariencia que tenía elegida.
    static func resolve(_ raw: String) -> AppTheme {
        if let t = AppTheme(rawValue: raw) { return t }
        if raw == "coffee" { return UserDefaults.standard.string(forKey: "appearance") == "dark" ? .roast : .latte }
        return .default
    }

    var palette: Palette {
        func p(_ bg: String, _ fg: String, _ muted: String, _ rule: String, _ codeBg: String, _ codeFg: String,
               _ accent: String, _ bar: String) -> Palette {
            Palette(dark: isDark, bg: bg, fg: fg, muted: muted, rule: rule, codeBg: codeBg, codeFg: codeFg,
                    accent: accent, bar: bar, box: fg, boxFg: bg)
        }
        switch self {
        case .latte:    return p("#ffffff", "#141414", "#6f6e6b", "#e6e5e2", "#f4f4f1", "#141414", "#8a5a2b", "#d6d5d1")
        case .paper:    return p("#f8f4ea", "#26221b", "#7d7566", "#e6dfcf", "#efe8d8", "#8a4a24", "#b0522d", "#d6cdb8")
        case .matcha:   return p("#f5f8ec", "#1f2a18", "#6b7a5c", "#dfe6cf", "#eaf0da", "#2f4a1f", "#4a7a2a", "#c5d2ad")
        case .snow:     return p("#fbfbfd", "#1d1d1f", "#6e6e73", "#e5e5ea", "#f1f1f4", "#1d1d1f", "#2f6fdb", "#d2d2d7")
        case .rose:     return p("#fdf7f6", "#2b1d1f", "#8a6f73", "#f0e1df", "#f8ecea", "#7a2e3a", "#b4475a", "#e6cfcc")
        case .sky:      return p("#f5f9fc", "#13263a", "#5f7387", "#dfe8f0", "#e9f1f7", "#1c4f7a", "#1f6fb2", "#c8d6e3")
        case .roast:    return p("#1b1a18", "#ece6dc", "#8f887d", "#34312c", "#252421", "#d9a869", "#d9a869", "#4a463f")
        case .espresso: return p("#1d1510", "#efe3d3", "#a08f7b", "#3a2c20", "#281d15", "#e0a868", "#e0a060", "#5a4533")
        case .midnight: return p("#161b26", "#e6eaf2", "#8a93a6", "#272f40", "#1e2433", "#8fa8f5", "#7b9cf5", "#3a4560")
        case .graphite: return p("#1e1e20", "#e8e8ea", "#8e8e93", "#333336", "#28282b", "#ffb27a", "#ff9f5a", "#48484c")
        case .forest:   return p("#141c17", "#e2ece4", "#86998b", "#26332b", "#1b261f", "#9fd3a6", "#7cc48a", "#33473a")
        case .plum:     return p("#1c1520", "#ece2f0", "#9a8aa3", "#2f2436", "#251c2b", "#d7a7f0", "#c792ea", "#46374f")
        case .ink:      return p("#000000", "#e6e6e6", "#7a7a7a", "#222222", "#111111", "#e6c07b", "#e6c07b", "#333333")
        }
    }
}

// MARK: - Fuentes

enum TextFont: String, CaseIterable, Identifiable {
    case geist, system, newYork, charter, avenir
    var id: String { rawValue }
    var title: String {
        switch self { case .geist: "Geist"; case .system: "SF Pro"; case .newYork: "New York"; case .charter: "Charter"; case .avenir: "Avenir Next" }
    }
    /// Pila CSS (valores fijos, nunca datos del usuario).
    var css: String {
        switch self {
        case .geist: "'Geist',-apple-system,system-ui,sans-serif"
        case .system: "-apple-system,system-ui,sans-serif"
        case .newYork: "ui-serif,'New York',Georgia,serif"
        case .charter: "Charter,'Iowan Old Style',Georgia,serif"
        case .avenir: "'Avenir Next',-apple-system,sans-serif"
        }
    }
}

enum CodeFont: String, CaseIterable, Identifiable {
    case geistMono, sfMono, menlo
    var id: String { rawValue }
    var title: String {
        switch self { case .geistMono: "Geist Mono"; case .sfMono: "SF Mono"; case .menlo: "Menlo" }
    }
    var css: String {
        switch self {
        case .geistMono: "'Geist Mono',ui-monospace,Menlo,monospace"
        case .sfMono: "ui-monospace,'SF Mono',Menlo,monospace"
        case .menlo: "Menlo,ui-monospace,monospace"
        }
    }
}

/// Fuentes elegidas en Ajustes (independientes del tema de color).
struct FontSettings: Equatable {
    var text: TextFont = .geist
    var code: CodeFont = .geistMono
    /// Tamaño del texto del modo Write (el preview usa +1 px y el modo Markdown −2 pt).
    var size: CGFloat = 16

    static let sizes: ClosedRange<Double> = 13...22

    init(text: TextFont = .geist, code: CodeFont = .geistMono, size: CGFloat = 16) {
        self.text = text; self.code = code; self.size = size
    }

    init(textRaw: String, codeRaw: String, size: Double) {
        text = TextFont(rawValue: textRaw) ?? .geist
        code = CodeFont(rawValue: codeRaw) ?? .geistMono
        self.size = CGFloat(min(max(size, Self.sizes.lowerBound), Self.sizes.upperBound))
    }

    /// CSS para el preview y el HTML exportado.
    func css(includeSize: Bool = true) -> String {
        "body{font-family:\(text.css)\(includeSize ? ";font-size:\(Int(size) + 1)px" : "")}"
        + "code,kbd,pre code,pre .lang{font-family:\(code.css)}"
    }

    private static var cache: [String: NSFont] = [:]

    func font(mono: Bool, size: CGFloat, weight: CGFloat = 400) -> NSFont {
        let key = "\(mono ? code.rawValue : text.rawValue)|\(size)|\(weight)"
        if let f = Self.cache[key] { return f }
        let w: NSFont.Weight = weight >= 690 ? .bold : weight >= 590 ? .semibold : weight >= 490 ? .medium : .regular
        let style = weight >= 690 ? "Bold" : weight >= 590 ? "SemiBold" : weight >= 490 ? "Medium" : "Regular"
        var f: NSFont?
        if mono {
            switch code {
            case .geistMono: f = NSFont(name: "GeistMono-" + style, size: size)
            case .sfMono: f = .monospacedSystemFont(ofSize: size, weight: w)
            case .menlo: f = NSFont(name: weight >= 590 ? "Menlo-Bold" : "Menlo-Regular", size: size)
            }
            f = f ?? .monospacedSystemFont(ofSize: size, weight: w)
        } else {
            switch text {
            case .geist: f = NSFont(name: "Geist-" + style, size: size)
            case .system: f = .systemFont(ofSize: size, weight: w)
            case .newYork:
                let sys = NSFont.systemFont(ofSize: size, weight: w)
                f = sys.fontDescriptor.withDesign(.serif).flatMap { NSFont(descriptor: $0, size: size) }
            case .charter: f = NSFont(name: weight >= 590 ? "Charter-Bold" : "Charter-Roman", size: size)
            case .avenir:
                let n = weight >= 690 ? "AvenirNext-Bold" : weight >= 590 ? "AvenirNext-DemiBold" : weight >= 490 ? "AvenirNext-Medium" : "AvenirNext-Regular"
                f = NSFont(name: n, size: size)
            }
            f = f ?? .systemFont(ofSize: size, weight: w)
        }
        Self.cache[key] = f!
        return f!
    }
}

enum PaperSize: String, CaseIterable, Identifiable {
    case a4, letter
    var id: String { rawValue }
    var title: String { self == .a4 ? "A4" : "Letter" }
    var size: NSSize { self == .a4 ? NSSize(width: 595, height: 842) : NSSize(width: 612, height: 792) }
}

extension NSColor {
    convenience init(hex: String) {
        var h = hex
        if h.hasPrefix("#") { h.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: h).scanHexInt64(&v)
        self.init(srgbRed: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255,
                  blue: CGFloat(v & 0xff) / 255, alpha: 1)
    }
}

enum AppearanceController {
    /// La apariencia de la app la decide el tema (claro u oscuro), no el sistema.
    @MainActor static func apply(theme: AppTheme) {
        NSApp.appearance = NSAppearance(named: theme.isDark ? .darkAqua : .aqua)
    }
}
