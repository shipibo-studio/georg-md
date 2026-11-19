# AGENTS.md

Instructions for AI coding agents working in this repository.

## Project

**Georg md** is a native macOS Markdown editor (SwiftUI + AppKit, macOS 15+) with a Quick Look extension. It has three modes: **Write** (formatted live editing on TextKit 1, styled from the swift-markdown AST), **Markdown** (raw text) and **Split** (Markdown plus a rendered preview that scroll together). It exports PDF and HTML, locks after inactivity with Touch ID, and ships a `georg` command-line helper. `README.md` covers what it does and how to build and release it.

- **Name:** always "Georg md", lowercase descriptor, as the georg-ds brand guide asks for every family product (`../georg-ds/docs/brand-manual.md`). Formerly "MD Editor" / `MDQuickLook` during development.
- **Bundle id:** `cc.dasgeorg.md` (extension `.preview`, CLI `.cli`, dev tool `.devtool`). Moved from `cl.jorgeepunan.georgmd` after 1.0.0; never change it again: macOS treats a new bundle id as a different app (settings, default-app choice and Quick Look registration start over).
- **Product, target and scheme:** `GeorgMD`; the app bundle is `Georg md.app`, the extension `Georg md Preview.appex`.
- **Status:** released (1.0.0) and in personal use on two Macs. Distributed as a disk image signed with the Developer ID of team `34BRMF8X9A`, notarized and stapled, published on GitHub Releases. Everyday builds are ad-hoc.
- **Origin:** a free reimplementation inspired by the writing experience of Coffee.app. Coffee is design reference only: no code or assets are copied, and its bundle and screenshots stay out of the repository (`rscs/` is git-ignored).

## Related repositories

Expected local layout: sibling directories under the same parent folder.

| Repository | Local path | Relationship |
| --- | --- | --- |
| [georg-ds](https://github.com/shipibo-studio/georg-ds) | `../georg-ds` | Design system and brand. Source of the app icon (`src/brand/md-icon-macos-1024.png`, release 0.13.0) and of the brand rules for Georg md (orange accent). Read `docs/brand-manual.md` and `docs/native.md` |
| [Georg port](https://github.com/shipibo-studio/georg-port) | `../georg-port` | Closest sibling: SwiftUI app with XcodeGen, a `Makefile`, Developer ID signing and notarization |
| [Georg use](https://github.com/shipibo-studio/georg-use) | `../georg-use` | Menu bar app of the family; same repository standard (`CONTRIBUTING.md`, `SECURITY.md`, CI) |
| georg-mail | `../georg-mail` | Owns email on `dasgeorg.cc` (`security@dasgeorg.cc`). No shared contract |

Family identifiers follow one scheme: bundle ids under `cc.dasgeorg.*`, repository names `georg-*`, the domain `dasgeorg.cc`.

## Commands

```bash
make build     # xcodegen + ad-hoc signed Release build → build/DerivedData/…/Georg md.app
make test      # builds GeorgDevTool and runs the test suite (must report 0 failures)
make run       # build and open
make install   # copy into /Applications
make icon      # regenerate the app icon from ../georg-ds (checks the source's SHA-256)
make release   # Developer ID + notarization + stapled .dmg in dist/ (scripts/release.sh)
make clean
```

- Run `xcodegen generate` (or any `make` target) after adding or renaming source files; the `.xcodeproj` is generated and git-ignored.
- `scripts/release.sh <version> [--skip-notarize] [--publish]`. Needs the keychain profile `georg-md` (`xcrun notarytool store-credentials`). `--publish` creates the GitHub release; never publish unless the user asks.
- `GeorgDevTool` (development only, not sandboxed, never shipped) renders and exports without touching the app's sandbox container, which avoids TCC prompts. It is driven by environment variables (`MDQ_IN`, `MDQ_OUT`, `MDQ_TASK=pdf|html|ast|live|perf|deco|depth|settings|code|test`, `MDQ_THEME`, `MDQ_FONT`, `MDQ_CARET`) because AppKit treats path arguments as documents to open.

## Layout

```
App/             app target: entry point, editors, preview, export, settings, lock, updates
  Assets.xcassets   app icon (from georg-ds; regenerate with `make icon`, never edit by hand)
Extension/       Quick Look preview extension (uses the app's icon)
Shared/          renderer shared by app and extension: HTMLPage, HTMLRenderer, RawHTML
                 (sanitizer), Highlighter, LaTeX → MathML, ImageLoader, MarkdownLimits
CLI/             `georg` helper, embedded in Contents/Helpers
Tools/DevTool/   GeorgDevTool and the test suite (LiveChecks.swift)
Fonts/           Geist and Geist Mono (OFL)
samples/         test documents, including hostile ones
scripts/         release.sh
```

## Security invariants (check them in every change)

- Preview and Quick Look HTML: CSP `default-src 'none'; style-src 'unsafe-inline'; font-src data:; img-src data:`. `WKWebView` with `allowsContentJavaScript = false`, non-persistent data store, navigation cancelled; links open in the browser only for `http`, `https`, `mailto`.
- App-injected JavaScript (scroll sync) runs in the `.defaultClient` world and only carries numbers formatted by the app, never document content.
- `RawHTML.sanitize` is an allow-list; `HTMLRenderer.safeURL` blocks every scheme but http(s)/mailto. Never emit raw document HTML.
- `ImageLoader`: extension allow-list, regular files, per-image and total size caps, ephemeral session, redirect guard, private hosts blocked, magic-byte check.
- `MarkdownLimits` caps block nesting at 32 before parsing (the extension runs on 512 KB stacks; deep nesting used to crash it). The Write mode falls back to plain text instead.
- Files are UTF-8 only; non-UTF-8 files are rejected rather than corrupted.
- The lock (`AppLock`) is a privacy screen, not encryption: it drops key events, clears first responders and disables export while locked.
- `UpdateChecker`: ephemeral session, 1 MB cap, only `https://github.com/…` links, opens the browser and never downloads or runs an installer.
- `georg` creates only Markdown/text files in existing folders, never folders.
- Release builds must not carry `get-task-allow` (`CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO`); `scripts/release.sh` checks it.

## Things that bite

- swift-markdown: `children` is a `Sequence`, so `children.first` resolves to `first(where:)` and a cast on it always fails. Use `child(at: 0)`.
- cmark can leave a child's range outside its parent's (an unclosed fence inside a quote). `LiveStyler` uses each top-level block's full extent.
- Source locations are line plus UTF-8 byte column; `SourceMap` converts them to UTF-16 offsets.
- TextKit 1 puts the null glyphs that start a line (hidden markers) in the previous line fragment; decoration geometry starts from the first visible glyph of each line.
- XcodeGen ignores a target-level `resources:` key; resources go in `sources` with `buildPhase: resources`.
- `NSFont(name:)` needs PostScript names (`Geist-Regular`, `GeistMono-Bold`), not family names.
- The incremental restyle is verified by the test suite against a full restyle with random edits; keep that test green when touching `LiveStyler`.

## Brand

- Write "Georg md" everywhere.
- The g's square is always the fixed Georg md orange (`#b04000` light, `#ff6a00` dark), even though the app lets users pick other theme accents.
- Never use the markdown mark alone or with a square of our own. The icon comes from georg-ds unchanged (`make icon`).

## Conventions

Everything in the repository is in English: code, comments, identifiers, commit messages and documentation (see `CONTRIBUTING.md`). Conventional Commits, branches `feat/*`, `fix/*`, `chore/*` from `main`, and a `CHANGELOG.md` entry for every user-visible change. Never commit, push or publish a release unless the user asks.
