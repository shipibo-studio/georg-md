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

## Georg logo (app icon)

The app icon (`App/Assets.xcassets/AppIcon.appiconset`) is the Georg md logo of the georg family, from [georg-ds](https://github.com/shipibo-studio/georg-ds) release **0.13.0**, `src/brand/md-icon-macos-1024.png` (sha256 `2b5c43fdea0f60a0946e90fad87c6ff850c600a726000f433d8f4d717bb02c09`): the lowercase g with its square in Georg md's orange (`--accent-orange`, `#b04000` light / `#ff6a00` dark), on the macOS icon grid. It is internal, same owner. The sizes are scaled from that file with `sips` by `make icon`, never redrawn or recoloured; the 512 pt @2x image is the original. The Quick Look extension and `georg` use the app's icon. Brand rules: `../georg-ds/docs/brand-manual.md`.

The Georg md symbol shown in *Settings → About* (`App/Assets.xcassets/BrandSymbol.imageset`) is `src/brand/md-symbol-light.svg` (sha256 `b717d7f5f0404ee3883aeb9e5c66502ca00b5e52328c138448aa323e322ee9dd`) and `md-symbol-dark.svg` (sha256 `682c3b8949819fad6f1486c777d158ca96680aaaf069ae4bfead5f21eec04cf7`) from the same georg-ds 0.13.0 release, copied unmodified as one image with Any and Dark appearances and Preserve Vector Data.

## SF Symbols and system fonts

Toolbar and settings icons are SF Symbols, through SwiftUI's `Image(systemName:)`, under Apple's terms for use in apps on Apple platforms. The SF Pro, New York, SF Mono, Charter, Avenir Next and Menlo font choices are system fonts; they are referenced, not bundled.

## Design reference only (no code or assets copied)

- **Coffee** (Coffee.app): the writing experience, the three view modes and the look of the window inspired Georg md. It is a closed-source app; nothing from it is copied or redistributed, and the local reference copy and screenshots (`rscs/`) are git-ignored.
