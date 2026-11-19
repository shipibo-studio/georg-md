import AppKit
import UniformTypeIdentifiers

/// App predeterminada para abrir Markdown (doble clic en Finder, `open`, botón de Quick Look).
@MainActor
enum DefaultApp {
    static let offeredKey = "didClaimDefaultApp"

    /// Tipos que se reclaman. `public.markdown` solo existe en algunas versiones de macOS.
    static var types: [UTType] {
        ["net.daringfireball.markdown", "public.markdown"].compactMap { UTType($0) }
    }

    /// App que abre hoy los `.md`.
    static var current: URL? {
        types.first.flatMap { NSWorkspace.shared.urlForApplication(toOpen: $0) }
    }

    static var isDefault: Bool {
        guard let url = current, let id = Bundle(url: url)?.bundleIdentifier else { return false }
        return id == Bundle.main.bundleIdentifier
    }

    /// Solo una copia instalada debe reclamar los archivos (nunca un build de desarrollo en otra carpeta).
    static var isInstalledCopy: Bool {
        let parent = Bundle.main.bundleURL.deletingLastPathComponent().standardizedFileURL.path
        let home = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path
        return parent == "/Applications" || parent == home
    }

    /// Define Georg md como app predeterminada para Markdown.
    static func makeDefault() async throws {
        let app = Bundle.main.bundleURL
        for type in types {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                NSWorkspace.shared.setDefaultApplication(at: app, toOpen: type) { error in
                    if let error { c.resume(throwing: error) } else { c.resume() }
                }
            }
        }
    }

    /// Primera apertura de una copia instalada: se reclama una sola vez. Si luego el usuario elige otra app,
    /// no se vuelve a insistir (para eso está el botón en Settings).
    static func claimOnFirstLaunch() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: offeredKey), isInstalledCopy else { return }
        defaults.set(true, forKey: offeredKey)
        guard !isDefault else { return }
        Task { try? await makeDefault() }
    }
}
