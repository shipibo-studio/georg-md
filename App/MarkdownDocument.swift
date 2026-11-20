import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let markdownText = UTType("net.daringfireball.markdown") ?? .plainText
}

struct MarkdownDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.markdownText, .plainText] }
    static var writableContentTypes: [UTType] { [.markdownText] }

    var text: String

    init(text: String = "") { self.text = text }

    init(configuration: ReadConfiguration) throws {
        // Invalid UTF-8 is rejected: reading it with replacement characters would corrupt the file on save.
        guard let data = configuration.file.regularFileContents,
              let s = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        text = s
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
