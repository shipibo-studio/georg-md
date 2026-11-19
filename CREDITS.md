# Credits

## swift-markdown and swift-cmark

- Repositories: <https://github.com/swiftlang/swift-markdown>, <https://github.com/swiftlang/swift-cmark>
- License: Apache-2.0 (swift-markdown); BSD-2-Clause, with portions under the MIT License (swift-cmark, a fork of cmark-gfm)
- Resolved versions: swift-markdown 0.9.0 and swift-cmark 0.9.0, through Swift Package Manager (`project.yml` asks for swift-markdown `from: 0.5.0`).

Georg md parses Markdown with swift-markdown. The packages are fetched at build time and linked into the app and the Quick Look extension; no source is copied into this repository.

## Geist and Geist Mono

- Repository: <https://github.com/vercel/geist-font>
- License: SIL Open Font License 1.1, Copyright (c) 2023 Vercel, in collaboration with basement.studio. The full license ships next to the fonts in [`Fonts/LICENSE-Geist.txt`](Fonts/LICENSE-Geist.txt).

The variable TTFs in `Fonts/` are bundled unmodified in the app and the extension, and embedded as `data:` URIs in rendered HTML and PDF.

## SF Symbols and system fonts

Toolbar and settings icons are SF Symbols, through SwiftUI's `Image(systemName:)`, under Apple's terms for use in apps on Apple platforms. The SF Pro, New York, SF Mono, Charter, Avenir Next and Menlo font choices are system fonts; they are referenced, not bundled.

## Design reference only (no code or assets copied)

- **Coffee** (Coffee.app): the writing experience, the three view modes and the look of the window inspired Georg md. It is a closed-source app; nothing from it is copied or redistributed, and the local reference copy and screenshots (`rscs/`) are git-ignored.
