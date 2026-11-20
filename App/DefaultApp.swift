import AppKit
import UniformTypeIdentifiers

/// Default app for opening Markdown (double-click in Finder, `open`, the Quick Look button).
@MainActor
enum DefaultApp {
    static let offeredKey = "didClaimDefaultApp"

    /// Types that are claimed. `public.markdown` only exists on some macOS versions.
    static var types: [UTType] {
        ["net.daringfireball.markdown", "public.markdown"].compactMap { UTType($0) }
    }

    /// App that currently opens `.md` files.
    static var current: URL? {
        types.first.flatMap { NSWorkspace.shared.urlForApplication(toOpen: $0) }
    }

    static var isDefault: Bool {
        guard let url = current, let id = Bundle(url: url)?.bundleIdentifier else { return false }
        return id == Bundle.main.bundleIdentifier
    }

    /// Only an installed copy should claim the files (never a development build in another folder).
    static var isInstalledCopy: Bool {
        let parent = Bundle.main.bundleURL.deletingLastPathComponent().standardizedFileURL.path
        let home = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path
        return parent == "/Applications" || parent == home
    }

    /// Sets Georg md as the default app for Markdown.
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

    /// First launch of an installed copy: the claim is made only once. If the user later picks another app,
    /// it does not insist again (that is what the button in Settings is for).
    static func claimOnFirstLaunch() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: offeredKey), isInstalledCopy else { return }
        defaults.set(true, forKey: offeredKey)
        guard !isDefault else { return }
        Task { try? await makeDefault() }
    }
}
