import AppKit

// georg: opens files in Georg md from Terminal.
// Lives in <App>.app/Contents/Helpers/georg; linked to /usr/local/bin/georg (see Settings → Command Line).
// Usage: georg [file ...]   (with no arguments opens the app; creates any missing .md files)

let bundleID = "cc.dasgeorg.md"
let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "mkd", "mkdn", "txt"]

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("georg: \(message)\n".utf8))
    exit(1)
}

let args = Array(CommandLine.arguments.dropFirst())
if args.contains("-h") || args.contains("--help") {
    print("""
    usage: georg [file ...]
      Opens Markdown files in Georg md. Missing .md files are created empty.
      With no arguments, opens the app.
    """)
    exit(0)
}

/// The app that contains this binary (resolving the /usr/local/bin link); otherwise, the one registered with the system.
func appURL() -> URL? {
    if let exe = Bundle.main.executableURL?.resolvingSymlinksInPath() {
        let app = exe.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        if app.pathExtension == "app", Bundle(url: app)?.bundleIdentifier == bundleID { return app }
    }
    return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
}

guard let app = appURL() else { fail("Georg md is not installed") }

let fm = FileManager.default
var urls: [URL] = []
for arg in args {
    let url = URL(fileURLWithPath: arg).standardizedFileURL
    var isDir: ObjCBool = false
    if fm.fileExists(atPath: url.path, isDirectory: &isDir) {
        if isDir.boolValue { fail("\(arg) is a directory") }
    } else {
        // Only Markdown/text files are created, never intermediate folders.
        guard markdownExtensions.contains(url.pathExtension.lowercased()) else { fail("\(arg): no such file") }
        guard fm.createFile(atPath: url.path, contents: Data(), attributes: nil) else { fail("could not create \(arg)") }
    }
    urls.append(url)
}

let config = NSWorkspace.OpenConfiguration()
config.activates = true
let done = DispatchSemaphore(value: 0)
var openError: Error?
if urls.isEmpty {
    NSWorkspace.shared.openApplication(at: app, configuration: config) { _, error in openError = error; done.signal() }
} else {
    NSWorkspace.shared.open(urls, withApplicationAt: app, configuration: config) { _, error in openError = error; done.signal() }
}
if done.wait(timeout: .now() + 20) == .timedOut { fail("timed out opening Georg md") }
if let openError { fail(openError.localizedDescription) }
