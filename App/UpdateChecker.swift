import AppKit
import Foundation

/// Consulta la última versión publicada en GitHub Releases.
///
/// Seguridad: sesión efímera sin cookies ni caché, tope de tamaño de respuesta, solo HTTPS, y los enlaces que
/// se ofrecen deben apuntar a github.com. La app nunca descarga ni ejecuta el instalador: abre la página en el
/// navegador y Gatekeeper verifica el .dmg firmado y notarizado.
@MainActor
final class UpdateChecker: ObservableObject {
    enum State: Equatable {
        case idle
        case checking
        case upToDate(String)
        case available(version: String, page: URL, download: URL?)
        case failed(String)
    }

    @Published private(set) var state: State = .idle

    static let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    static let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    /// "propietario/repo", definido en Info.plist (GeorgReleasesRepo).
    static let repo = Bundle.main.object(forInfoDictionaryKey: "GeorgReleasesRepo") as? String ?? ""

    private static let maxBytes = 1_000_000

    func check() async {
        guard state != .checking else { return }
        guard Self.isValidRepo(Self.repo),
              let url = URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest") else {
            state = .failed("Update source is not configured."); return
        }
        state = .checking
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Georg-md-UpdateCheck", forHTTPHeaderField: "User-Agent") // GitHub exige User-Agent; genérico
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 404 { state = .failed("No releases published yet."); return }
            guard status == 200 else { state = .failed("GitHub answered \(status). Try again later."); return }
            guard data.count <= Self.maxBytes else { state = .failed("Unexpected response."); return }
            state = Self.evaluate(data, current: Self.current)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Interpreta la respuesta de la API (separado para poder probarlo sin red).
    nonisolated static func evaluate(_ data: Data, current: String) -> State {
        struct Asset: Decodable { let name: String; let browser_download_url: String }
        struct Release: Decodable { let tag_name: String; let html_url: String; let draft: Bool?; let prerelease: Bool?; let assets: [Asset]? }
        guard let r = try? JSONDecoder().decode(Release.self, from: data) else { return .failed("Unexpected response.") }
        let version = r.tag_name.hasPrefix("v") ? String(r.tag_name.dropFirst()) : r.tag_name
        guard isVersion(version), let page = safeGitHubURL(r.html_url) else { return .failed("Unexpected response.") }
        guard r.draft != true, r.prerelease != true, compare(version, current) == .orderedDescending else {
            return .upToDate(current)
        }
        let dmg = r.assets?.first { $0.name.lowercased().hasSuffix(".dmg") }.flatMap { safeGitHubURL($0.browser_download_url) }
        return .available(version: version, page: page, download: dmg)
    }

    nonisolated static func isValidRepo(_ s: String) -> Bool {
        s.range(of: #"^[A-Za-z0-9-]{1,39}/[A-Za-z0-9._-]{1,100}$"#, options: .regularExpression) != nil
    }

    nonisolated static func isVersion(_ s: String) -> Bool {
        s.range(of: #"^\d{1,6}(\.\d{1,6}){0,3}$"#, options: .regularExpression) != nil
    }

    /// Solo https://github.com/… (páginas de release y descargas de assets, que redirigen al CDN de GitHub).
    nonisolated static func safeGitHubURL(_ s: String) -> URL? {
        guard let u = URL(string: s), u.scheme == "https", u.host?.lowercased() == "github.com", u.user == nil else { return nil }
        return u
    }

    /// Compara versiones numéricas ("1.10" > "1.9"; "1.0" == "1.0.0").
    nonisolated static func compare(_ a: String, _ b: String) -> ComparisonResult {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l < r ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }
}
