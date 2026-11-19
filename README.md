# Georg md

A small, native macOS Markdown editor with a Quick Look extension. Write in a formatted live view, switch to raw Markdown with ⌘/, or work side by side. Files stay plain `.md` on disk.

Requires **macOS 15** or later. Signed with Developer ID and notarized by Apple.

## Install

1. Download the latest `Georg-md-x.y.z.dmg` from [Releases](https://github.com/shipibo-studio/georg-md/releases).
2. Open it and drag **Georg md** to Applications. Open it once.
3. On first launch Georg md becomes the default app for Markdown files (only once; change it any time in Finder → Get Info → Open with, or back in Settings → Default App → Make Default).
4. Quick Look: press Space on any `.md` file in Finder. If another app's preview shows up, enable **Georg md Preview** in System Settings → General → Login Items & Extensions → Quick Look.
5. Command line (optional): Settings → Command Line shows the one-time command to link `georg` into `/usr/local/bin`. Then `georg notes.md` opens a file (and creates it if it doesn't exist).

Settings → About shows the installed version and checks this repository for new releases.

## Features

- **Write**: one editable text where Markdown is formatted as you type. Headings, emphasis, inline code, links, bullets, clickable task boxes, quotes, GitHub alerts, horizontal rules, highlighted code blocks, tables and math are styled; markers (`#`, `**`, `` ` ``, `[]()`) hide outside the line you're on.
  - Return continues lists and quotes (twice ends them), Tab / Shift-Tab indent list items, ⌘B / ⌘I wrap the selection, ⌘-click opens links.
- **Markdown**: the raw text in a monospaced font with dimmed markers.
- **Split**: Markdown and rendered preview side by side, scrolling together.
- **Themes**: 6 light (Latte, Paper, Matcha, Snow, Rose, Sky) and 7 dark (Roast, Espresso, Midnight, Graphite, Forest, Plum, Ink). The whole window follows the theme.
- **Fonts**: text in Geist, SF Pro, New York, Charter or Avenir Next; code in Geist Mono, SF Mono or Menlo; 13–22 pt.
- **Export**: paginated PDF (A4 or Letter) and self-contained HTML.
- **Lock**: after 1–60 minutes of inactivity, when the Mac sleeps, or with ⌃⌘L. Unlock with Touch ID or your Mac password.
- **Quick Look**: tables, task lists, alerts, highlighted code, LaTeX math rendered to MathML, local and web images, and a safe subset of inline HTML.

## Security

- Rendered previews run with JavaScript disabled, a strict Content-Security-Policy (`default-src 'none'`), no navigation and non-persistent storage. Links open in your browser only for `http`, `https` and `mailto`.
- Inline HTML goes through an allow-list sanitizer; scripts, styles, event handlers, iframes and forms are shown as text.
- Images are embedded as `data:` URIs after checking extension, size limits and magic bytes. Remote images use an ephemeral session and private/local hosts are blocked. Note that loading a remote image reveals your IP address to its server.
- Pathological nesting (thousands of `>` or nested lists) is capped before parsing, so a hostile file can't crash the app or the Quick Look extension.
- Files are read and written as UTF-8 only; non-UTF-8 files are rejected instead of being corrupted.
- The lock is a privacy screen: it hides open documents and blocks typing, copying and exporting. It does not encrypt files on disk.
- Update checks call the public GitHub API with an ephemeral session and only accept `https://github.com/…` links. The app never downloads or runs an installer itself.

## Build from source

Requires Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
make build   # ad-hoc signed Release build in build/DerivedData
make test    # test suite (must report 0 failures)
make run     # build and open
```

The `.xcodeproj` is generated from `project.yml` and not committed; every `make` target regenerates it. Everyday builds are ad-hoc signed, so no certificate is needed.

### Release

```sh
xcrun notarytool store-credentials georg-md --apple-id <apple-id> --team-id <team-id>   # once
make release                          # signed + notarized .dmg in dist/ for MARKETING_VERSION
scripts/release.sh 1.1.0 --publish    # also creates the GitHub release
```

The script builds Release with the Developer ID certificate (hardened runtime, secure timestamp, no debug entitlements), notarizes and staples both the app and the `.dmg`, checks Gatekeeper, and writes a SHA-256 file. `--skip-notarize` makes a local, unnotarized build for testing.

### Tests and dev tool

`GeorgDevTool` is a development-only helper (not sandboxed, never shipped). It renders and exports without touching the app's sandbox container. It's driven by environment variables because AppKit treats path arguments as documents to open:

```sh
make test   # builds GeorgDevTool and runs the suite
T=build/DerivedData/Build/Products/Debug/GeorgDevTool.app/Contents/MacOS/GeorgDevTool
MDQ_IN=samples/math-code.md MDQ_OUT=/tmp/mc $T                           # PDF + one PNG per page
MDQ_IN=samples/live.md MDQ_OUT=/tmp/live MDQ_TASK=live MDQ_THEME=midnight $T   # screenshot of Write mode
```

Other tasks: `html`, `ast` (swift-markdown tree with source ranges), `perf`, `deco`, `depth` (render on a 512 KB stack), `settings`, `code`.

## Project layout

```
App/              macOS app (SwiftUI + AppKit)
  GeorgMDApp.swift     entry point, menus, shortcuts
  EditorView.swift     modes, toolbar, export
  LiveTextView.swift   Write mode: TextKit 1 view, hidden markers, decorations, keyboard
  LiveStyler.swift     swift-markdown AST → text attributes; restyles only the edited block
  EditAssist.swift     list/quote continuation, indent, ⌘B/⌘I
  CodeEditor.swift     Markdown mode
  PreviewWebView.swift WKWebView preview (JS off, navigation blocked)
  ScrollSync.swift     proportional scroll between editor and preview
  Exporter.swift       PDF and HTML export
  AppLock.swift        inactivity lock (LocalAuthentication)
  UpdateChecker.swift  GitHub Releases check
  DefaultApp.swift     default app for Markdown (first launch + Settings button)
  Theme.swift          palettes, themes, fonts
  SettingsView.swift
Extension/        Quick Look preview extension
Shared/           renderer shared by app and extension: HTML, sanitizer, highlighter, LaTeX → MathML, images, limits
CLI/              `georg` command-line helper (embedded in Contents/Helpers)
Tools/DevTool/    development tool and tests
Fonts/            Geist and Geist Mono (SIL Open Font License, see Fonts/LICENSE-Geist.txt)
samples/          test documents, including hostile cases
scripts/          release script
```

## Known limitations

- Write mode shows images and tables as styled text, not rendered.
- Split view scroll is proportional (not aligned by heading); scrolling the preview with the keyboard doesn't move the editor.
- Quick Look follows the system appearance, not the app theme.
- No footnotes yet.
- WebKit ignores `break-after: avoid` when printing, so a heading can end up alone at the bottom of a PDF page.

## Contributing and security

See [CONTRIBUTING.md](CONTRIBUTING.md) (the georg family conventions), [AGENTS.md](AGENTS.md) for architecture notes, and [SECURITY.md](SECURITY.md) to report a vulnerability privately. Third-party components are listed in [CREDITS.md](CREDITS.md) and changes in [CHANGELOG.md](CHANGELOG.md).
