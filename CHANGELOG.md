# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Georg md offers to be the default Markdown app.** On the first launch from an Applications folder it becomes the app that opens `.md` files, once; if you later pick another app it does not insist. *Settings → Default App* shows which app opens Markdown today and has a *Make Default* button.

### Changed

- **New bundle id: `cc.dasgeorg.md`**, the georg family's scheme (it was `cl.jorgeepunan.georgmd`). macOS treats it as a new app: settings, the default-app choice and the Quick Look registration start over, and Georg md 1.0.0 should be deleted after installing this version.

## [1.0.0] - 2026-11-18

First release: signed with Developer ID and notarized by Apple.

### Added

- **Three modes.** *Write* formats Markdown as you type (headings, emphasis, inline code, links, bullets, clickable task boxes, quotes, GitHub alerts, rules, highlighted code blocks, tables, math) and hides the markers outside the current line. *Markdown* shows the raw text with dimmed markers. *Split* shows Markdown and the rendered preview side by side, scrolling together. ⌘/ toggles Write and Markdown, ⌥⌘/ toggles Split.
- **Editing helpers.** Return continues lists and quotes (twice ends them), Tab and Shift-Tab indent list items, ⌘B and ⌘I wrap the selection, ⌘-click opens links.
- **Quick Look extension** with the same renderer: tables, task lists, alerts, highlighted code, LaTeX math as MathML, local and web images, and a safe subset of inline HTML.
- **Themes and fonts.** Six light and seven dark themes that colour the whole window, and separate text and code fonts with a size setting.
- **Export** to paginated PDF (A4 or Letter) and self-contained HTML.
- **Inactivity lock** with Touch ID or the Mac password, also when the Mac sleeps or with ⌃⌘L.
- **`georg` command-line helper** to open (and create) Markdown files from Terminal.
- **Update check** in *Settings → About* against this repository's GitHub releases.

### Security

- Previews run without JavaScript, under a strict Content-Security-Policy, with navigation blocked; inline HTML goes through an allow-list sanitizer; images are size-capped, type-checked and never fetched from private hosts.
- Pathologically nested documents are capped before parsing, so a crafted file cannot crash the app or the Quick Look extension.

[Unreleased]: https://github.com/shipibo-studio/georg-md/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/shipibo-studio/georg-md/releases/tag/v1.0.0
