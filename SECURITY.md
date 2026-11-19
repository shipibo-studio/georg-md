# Security policy

## Reporting a vulnerability

If you find a security vulnerability, **do not open a public issue** and do not describe it in a pull request.

Report it privately through GitHub: **[Report a vulnerability](https://github.com/shipibo-studio/georg-md/security/advisories/new)**, or email **security@dasgeorg.cc**.

Please include:

- A description of the vulnerability
- Steps to reproduce it (a sample `.md` file helps)
- Its potential impact
- Suggested mitigations, if any

We acknowledge reports within **48 business hours** and reply with a remediation timeline.

We appreciate good-faith reports. Please do not access, modify or extract third-party data during your research, and do not disclose the finding publicly until a fix is available.

## Scope

Georg md opens untrusted Markdown in the editor, the preview and the Quick Look extension. Of special interest:

- Script execution, network requests or navigation from a rendered document (CSP, sanitizer, link and image handling).
- Reading files other than images next to a document, or reaching private network hosts through images.
- Crashes or hangs caused by a crafted file, especially in the Quick Look extension.
- Bypassing the inactivity lock, or the update check accepting a link outside `github.com`.

## Supported versions

| Version | Supported |
| --- | --- |
| Latest | Yes |
| Older | No |

## Automated scanning

- **gitleaks** (secrets) and **semgrep** (static analysis) run on every pull request, on every push to `main`, and weekly.
- **GitGuardian** monitors the repository for leaked secrets.
- **Dependabot** keeps the SHA-pinned GitHub Actions up to date.
