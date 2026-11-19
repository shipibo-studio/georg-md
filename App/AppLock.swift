import AppKit
import LocalAuthentication
import SwiftUI

/// Bloqueo por inactividad (o manual) con Touch ID / contraseña del Mac.
///
/// Es una pantalla de privacidad: oculta los documentos abiertos y bloquea teclado, copiar y exportar mientras
/// está activo. No cifra nada: los archivos en disco siguen siendo archivos Markdown normales.
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

    /// Minutos de inactividad antes de bloquear (0 = nunca).
    var minutes: Int { UserDefaults.standard.integer(forKey: Self.minutesKey) }

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]) { [weak self] event in
            guard let self else { return event }
            // Se extraen valores Sendable; el monitor local corre en el hilo principal.
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
        // Al dormir el equipo o la pantalla se bloquea de inmediato (si el bloqueo está activado).
        let nc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            sleepObservers.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { if let self, self.minutes > 0 { self.lock() } }
            })
        }
    }

    /// true = descartar el evento (app bloqueada). Mientras está desbloqueada solo registra actividad.
    private func shouldDrop(isKey: Bool, flags: UInt, key: String, keyCode: UInt16) -> Bool {
        guard isLocked else {
            lastActivity = Date()
            return false
        }
        guard isKey else { return false } // los clics los absorbe la capa de bloqueo
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
            // Sin primer respondedor, Copiar/Cortar del menú no tienen sobre qué actuar.
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
        // deviceOwnerAuthentication: Touch ID y, si no hay o falla, la contraseña del Mac.
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

/// Capa que cubre el documento mientras la app está bloqueada.
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
        .onTapGesture {} // absorbe los clics para que no lleguen al editor
    }
}
