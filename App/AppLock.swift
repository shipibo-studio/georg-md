import AppKit
import LocalAuthentication
import SwiftUI

/// Lock after inactivity (or manually) with Touch ID / the Mac's password.
///
/// It is a privacy screen: it hides open documents and blocks the keyboard, copy and export while
/// it is active. It encrypts nothing: files on disk remain ordinary Markdown files.
@MainActor
final class AppLock: ObservableObject {
    static let shared = AppLock()
    static let minutesKey = "lockMinutes"
    static let choices = [0, 1, 5, 15, 30, 60]

    @Published private(set) var isLocked = false
    @Published private(set) var isAuthenticating = false
    @Published var lastError: String?

    private var lastActivity = Date()
    private var monitor: Any?
    private var timer: Timer?
    private var sleepObservers: [NSObjectProtocol] = []

    /// Minutes of inactivity before locking (0 = never).
    var minutes: Int { UserDefaults.standard.integer(forKey: Self.minutesKey) }

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]) { [weak self] event in
            guard let self else { return event }
            // Sendable values are extracted; the local monitor runs on the main thread.
            let isKey = event.type == .keyDown
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue
            let key = isKey ? (event.charactersIgnoringModifiers?.lowercased() ?? "") : ""
            let code = isKey ? event.keyCode : 0
            let drop = MainActor.assumeIsolated { self.shouldDrop(isKey: isKey, flags: flags, key: key, keyCode: code) }
            return drop ? nil : event
        }
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        // When the computer or the display goes to sleep, lock immediately (if locking is enabled).
        let nc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            sleepObservers.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { if let self, self.minutes > 0 { self.lock() } }
            })
        }
    }

    /// true = discard the event (app locked). While unlocked it only records activity.
    private func shouldDrop(isKey: Bool, flags: UInt, key: String, keyCode: UInt16) -> Bool {
        guard isLocked else {
            lastActivity = Date()
            return false
        }
        guard isKey else { return false } // clicks are absorbed by the lock overlay
        if flags == NSEvent.ModifierFlags.command.rawValue, ["q", "h", "m"].contains(key) { return false }
        if keyCode == 36 || keyCode == 76 { Task { await unlock() } } // Return / Enter
        return true
    }

    private func tick() {
        guard minutes > 0, !isLocked, Date().timeIntervalSince(lastActivity) >= Double(minutes) * 60 else { return }
        lock()
    }

    func lock() {
        guard !isLocked else { return }
        isLocked = true
        lastError = nil
        for window in NSApp.windows {
            // Without a first responder, the menu's Copy/Cut have nothing to act on.
            window.makeFirstResponder(nil)
            for sheet in window.sheets { window.endSheet(sheet) }
        }
    }

    func unlock() async {
        guard isLocked, !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }
        let ctx = LAContext()
        var err: NSError?
        // deviceOwnerAuthentication: Touch ID and, if unavailable or it fails, the Mac's password.
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else {
            lastError = err?.localizedDescription ?? "Authentication is not available."
            return
        }
        do {
            try await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "unlock your documents")
            isLocked = false
            lastError = nil
            lastActivity = Date()
        } catch let e as LAError where e.code == .userCancel || e.code == .appCancel || e.code == .systemCancel {
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }
}

/// Overlay that covers the document while the app is locked.
struct LockOverlay: View {
    @ObservedObject var lock: AppLock
    let palette: Palette

    var body: some View {
        ZStack {
            Color(nsColor: NSColor(hex: palette.bg))
            VStack(spacing: 14) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(Color(nsColor: NSColor(hex: palette.muted)))
                Text("Locked")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color(nsColor: NSColor(hex: palette.fg)))
                Button {
                    Task { await lock.unlock() }
                } label: {
                    Label("Unlock with Touch ID", systemImage: "touchid")
                        .padding(.horizontal, 6)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .tint(Color(nsColor: NSColor(hex: palette.accent)))
                .disabled(lock.isAuthenticating)
                if let e = lock.lastError {
                    Text(e).font(.callout).foregroundStyle(Color(nsColor: NSColor(hex: palette.muted)))
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {} // absorbs clicks so they do not reach the editor
    }
}
