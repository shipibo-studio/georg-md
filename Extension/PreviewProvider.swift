import Foundation
import QuickLookUI
import UniformTypeIdentifiers

final class PreviewProvider: QLPreviewProvider, QLPreviewingController {
    /// Límite de lectura para que un archivo enorme no agote la memoria de la extensión.
    private static let maxBytes = 2_000_000

    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let handle = try FileHandle(forReadingFrom: request.fileURL)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: Self.maxBytes) ?? Data()
        let source = String(decoding: data, as: UTF8.self)
        let html = await HTMLPage.render(markdown: source, baseDir: request.fileURL.deletingLastPathComponent())

        let reply = QLPreviewReply(
            dataOfContentType: .html,
            contentSize: CGSize(width: 820, height: 900)
        ) { _ in Data(html.utf8) }
        reply.stringEncoding = .utf8
        return reply
    }
}
