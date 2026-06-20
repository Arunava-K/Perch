import Foundation
import Defaults

/// Toggles a macOS Focus by running user-provided Shortcuts. This is the only
/// Apple-supported way to control Focus / Do Not Disturb programmatically on
/// macOS 15 — there is no public framework API. The user creates a "Focus On"
/// and "Focus Off" shortcut (each a "Set Focus" action) and picks them in
/// Settings; we shell out to `/usr/bin/shortcuts run <name>`.
enum FocusController {
    /// Names of every shortcut in the user's library, for the Settings pickers.
    /// Runs synchronously — fast, and only called on demand from Settings.
    static func availableShortcuts() -> [String] {
        run(["list"], waitForOutput: true)
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Run a named shortcut. No-op if the name is empty. Fire-and-forget unless
    /// `waitForExit` is set (used on app quit so the Focus actually turns off
    /// before we exit).
    static func runShortcut(named name: String, waitForExit: Bool = false) {
        guard !name.isEmpty else { return }
        _ = run(["run", name], waitForOutput: waitForExit)
    }

    @discardableResult
    private static func run(_ args: [String], waitForOutput: Bool) -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        proc.arguments = args
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do {
            try proc.run()
        } catch {
            return ""
        }
        guard waitForOutput else { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }
}

/// Coordinates the notch ↔ Focus pairing: turns the Focus on whenever
/// notification mirroring *and* DND pairing are both enabled, and off otherwise.
@MainActor
final class FocusPairingController {
    private var observations: [Defaults.Observation] = []
    private var active = false

    /// Observe the two prefs and keep the Focus in sync. Fires immediately, so
    /// it also re-asserts the correct state at launch.
    func activate() {
        observations = [
            Defaults.observe(.notificationMirroringEnabled) { [weak self] _ in self?.apply() },
            Defaults.observe(.dndPairingEnabled) { [weak self] _ in self?.apply() },
        ]
    }

    private func apply() {
        let shouldBeOn = Defaults[.notificationMirroringEnabled] && Defaults[.dndPairingEnabled]
        guard shouldBeOn != active else { return }
        active = shouldBeOn
        if shouldBeOn {
            FocusController.runShortcut(named: Defaults[.focusOnShortcutName])
        } else {
            FocusController.runShortcut(named: Defaults[.focusOffShortcutName])
        }
    }

    /// Turn the paired Focus off on quit so we never leave the user stuck in it.
    func deactivateForQuit() {
        guard active else { return }
        active = false
        FocusController.runShortcut(named: Defaults[.focusOffShortcutName], waitForExit: true)
    }
}
