import Foundation

/// Resolves images (local or web) to `data:` URIs to embed them in the HTML.
/// That way the preview's CSP stays `img-src data:` and the HTML never touches the network.
///
/// Safeguards:
/// - Only content whose *actual content* (magic bytes) is an image is returned.
/// - Local: image extension, regular file, maximum size; no other kind of file is ever read.
/// - Web: only http(s), no private/loopback hosts (also after redirects), no cookies or cache,
///   with maximum timeouts and sizes.
enum ImageLoader {
    static let maxImages = 24
    static let maxBytes = 8_000_000
    static let maxTotalChars = 32_000_000

    private static let localExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "svg", "bmp"]

    static func load(_ sources: [String], baseDir: URL) async -> [String: String] {
        let unique = Array(Set(sources)).sorted().prefix(maxImages)
        var result: [String: String] = [:]
        await withTaskGroup(of: (String, String?).self) { group in
            for s in unique {
                group.addTask { (s, await resolve(s, baseDir: baseDir)) }
            }
            for await (s, uri) in group {
                if let uri { result[s] = uri }
            }
        }
        var total = 0
        var capped: [String: String] = [:]
        for (k, v) in result.sorted(by: { $0.key < $1.key }) {
            total += v.utf8.count
            if total > maxTotalChars { break }
            capped[k] = v
        }
        return capped
    }

    private static func resolve(_ src: String, baseDir: URL) async -> String? {
        let s = src.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, s.count < 4096 else { return nil }
        if s.lowercased().hasPrefix("data:") { return fromDataURI(s) }
        if let u = URL(string: s), let scheme = u.scheme?.lowercased() {
            switch scheme {
            case "http", "https": return await fetchRemote(u)
            case "file": return loadLocal(u.path)
            default: return nil
            }
        }
        let decoded = s.removingPercentEncoding ?? s
        let url = decoded.hasPrefix("/")
            ? URL(fileURLWithPath: decoded)
            : URL(fileURLWithPath: decoded, relativeTo: baseDir)
        return loadLocal(url.path)
    }

    // MARK: Local

    private static func loadLocal(_ path: String) -> String? {
        let url = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
        guard localExtensions.contains(url.pathExtension.lowercased()) else { return nil }
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              (attrs[.type] as? FileAttributeType) == .typeRegular,
              let size = attrs[.size] as? Int, size > 0, size <= maxBytes,
              let data = try? Data(contentsOf: url) else { return nil }
        return dataURI(data)
    }

    // MARK: data:

    private static func fromDataURI(_ s: String) -> String? {
        guard let comma = s.firstIndex(of: ","), s[..<comma].lowercased().hasSuffix(";base64") else { return nil }
        let payload = s[s.index(after: comma)...]
        guard payload.utf8.count <= maxBytes * 4 / 3 + 8,
              let data = Data(base64Encoded: String(payload)) else { return nil }
        return dataURI(data)
    }

    // MARK: Web

    private static func fetchRemote(_ url: URL) async -> String? {
        guard isPublicHost(url.host) else { return nil }
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 6
        cfg.timeoutIntervalForResource = 10
        cfg.httpCookieAcceptPolicy = .never
        cfg.httpShouldSetCookies = false
        cfg.urlCache = nil
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: cfg, delegate: RedirectGuard(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        var req = URLRequest(url: url)
        req.setValue("image/*", forHTTPHeaderField: "Accept")
        req.setValue("Georg-md", forHTTPHeaderField: "User-Agent")
        guard let (bytes, resp) = try? await session.bytes(for: req),
              let http = resp as? HTTPURLResponse, http.statusCode == 200,
              http.expectedContentLength <= Int64(maxBytes) else { return nil }
        var data = Data()
        do {
            for try await b in bytes {
                data.append(b)
                if data.count > maxBytes { return nil }
            }
        } catch { return nil }
        return dataURI(data)
    }

    /// Rejects loopback, private networks, link-local and intranet names.
    /// Known limitation: it does not resolve DNS, so a public domain pointing to a private IP is not detected.
    static func isPublicHost(_ host: String?) -> Bool {
        guard var h = host?.lowercased(), !h.isEmpty else { return false }
        while h.hasSuffix(".") { h.removeLast() }
        if h == "localhost" || h.hasSuffix(".local") || h.hasSuffix(".localhost")
            || h.hasSuffix(".internal") || h.hasSuffix(".lan") || h.hasSuffix(".home.arpa") { return false }
        if h.contains(":") {
            return !(h == "::1" || h.hasPrefix("::") || h.hasPrefix("fc") || h.hasPrefix("fd") || h.hasPrefix("fe80"))
        }
        guard h.contains(".") else { return false }
        if h.allSatisfy({ $0.isNumber || $0 == "." }) {
            let p = h.split(separator: ".").compactMap { Int($0) }
            guard p.count == 4, p.allSatisfy({ (0...255).contains($0) }) else { return false }
            let a = p[0], b = p[1]
            if a == 0 || a == 10 || a == 127 || (a == 169 && b == 254) || (a == 172 && (16...31).contains(b))
                || (a == 192 && b == 168) || (a == 100 && (64...127).contains(b)) || a >= 224 { return false }
        }
        return true
    }

    // MARK: Content

    /// Only emits a URI if the first bytes match a known image format.
    private static func dataURI(_ data: Data) -> String? {
        guard let mime = sniff(data) else { return nil }
        return "data:\(mime);base64,\(data.base64EncodedString())"
    }

    private static func sniff(_ d: Data) -> String? {
        let b = [UInt8](d.prefix(16))
        if b.count >= 8, b[0] == 0x89, b[1] == 0x50, b[2] == 0x4E, b[3] == 0x47 { return "image/png" }
        if b.count >= 3, b[0] == 0xFF, b[1] == 0xD8, b[2] == 0xFF { return "image/jpeg" }
        if b.count >= 4, b[0] == 0x47, b[1] == 0x49, b[2] == 0x46, b[3] == 0x38 { return "image/gif" }
        if b.count >= 12, b[0] == 0x52, b[1] == 0x49, b[2] == 0x46, b[3] == 0x46,
           b[8] == 0x57, b[9] == 0x45, b[10] == 0x42, b[11] == 0x50 { return "image/webp" }
        if b.count >= 2, b[0] == 0x42, b[1] == 0x4D { return "image/bmp" }
        let head = String(decoding: d.prefix(1024), as: UTF8.self).lowercased()
        if head.contains("<svg") { return "image/svg+xml" }  // inside <img> it runs no scripts and loads no resources
        return nil
    }
}

/// Revalidates every redirect: same public-host rule and only http(s).
final class RedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        if let u = request.url, ["http", "https"].contains(u.scheme?.lowercased() ?? ""),
           ImageLoader.isPublicHost(u.host) {
            completionHandler(request)
        } else {
            completionHandler(nil)
        }
    }
}
