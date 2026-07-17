import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Defaults
import KeyboardShortcuts

/// The Settings window: native System-Settings-style sidebar via
/// `TabView(.sidebarAdaptable)`, one tab per grouped pane.
struct SettingsView: View {
    @ObservedObject var registry: ModuleRegistry
    @ObservedObject var calendar: CalendarManager

    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                GeneralPane()
            }
            Tab("Clipboard", systemImage: "doc.on.clipboard") {
                ClipboardPane()
            }
            Tab("Notifications", systemImage: "bell.badge") {
                NotificationsPane()
            }
            Tab("Calendar", systemImage: "calendar") {
                CalendarPane(calendar: calendar)
            }
            Tab("Tabs", systemImage: "square.grid.2x2") {
                TabsPane(registry: registry)
            }
            Tab("Shortcuts", systemImage: "keyboard") {
                ShortcutsPane()
            }
            Tab("About", systemImage: "info.circle") {
                AboutPane()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .formStyle(.grouped)
        .frame(minWidth: 680, idealWidth: 720, minHeight: 460, idealHeight: 540)
    }
}

// MARK: - General

private struct GeneralPane: View {
    @Default(.openNotchOnHover) private var openNotchOnHover
    @Default(.hapticFeedback) private var hapticFeedback
    @Default(.hideMenuBarIcon) private var hideMenuBarIcon

    @State private var launchAtLogin = LoginItem.isEnabled

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        LoginItem.setEnabled(newValue)
                    }
                Toggle("Open notch on hover", isOn: $openNotchOnHover)
                Toggle("Haptic feedback", isOn: $hapticFeedback)
            }

            Section {
                Toggle("Hide menu bar icon", isOn: $hideMenuBarIcon)
            } footer: {
                if hideMenuBarIcon {
                    Text("Open Settings from the gear button in the notch, or reach the menu with the Toggle Notch shortcut.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onAppear { launchAtLogin = LoginItem.isEnabled }
    }
}

// MARK: - Clipboard

private struct ClipboardPane: View {
    @Default(.historyLimit) private var historyLimit
    @Default(.historyMaxAgeDays) private var historyMaxAgeDays
    @Default(.skipSensitiveContent) private var skipSensitiveContent
    @Default(.stripFormattingByDefault) private var stripFormattingByDefault
    @Default(.plainTextApps) private var plainTextApps

    @State private var accessibilityGranted = AccessibilityPermission.isTrusted

    var body: some View {
        Form {
            Section("History") {
                Stepper(value: $historyLimit, in: 10...1000, step: 10) {
                    LabeledContent("Keep up to", value: "\(historyLimit) clips")
                }
                Stepper(value: $historyMaxAgeDays, in: 1...365, step: 1) {
                    LabeledContent("Discard after", value: "\(historyMaxAgeDays) days")
                }
                Toggle("Skip passwords & sensitive content", isOn: $skipSensitiveContent)
            }

            Section {
                Toggle("Paste without formatting by default", isOn: $stripFormattingByDefault)
                ForEach(plainTextApps, id: \.self) { bundleID in
                    HStack {
                        Image(systemName: "app.dashed").foregroundStyle(.secondary)
                        Text(SettingsFormatHelpers.appName(for: bundleID))
                        Spacer()
                        Button {
                            plainTextApps.removeAll { $0 == bundleID }
                        } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Button("Add App…", action: addPlainTextApp)
            } header: {
                Text("Formatting")
            } footer: {
                Text("Clips paste with their original formatting. Apps listed here always receive plain text.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Label {
                        Text("Accessibility")
                    } icon: {
                        Image(systemName: accessibilityGranted
                              ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(accessibilityGranted ? .green : .orange)
                    }
                    Spacer()
                    if accessibilityGranted {
                        Text("Granted").foregroundStyle(.secondary)
                    } else {
                        Button("Grant…") {
                            AccessibilityPermission.prompt()
                            AccessibilityPermission.openSettings()
                        }
                    }
                }
            } header: {
                Text("Permissions")
            } footer: {
                Text("Required to paste a clip into the active app (simulates ⌘V).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { accessibilityGranted = AccessibilityPermission.isTrusted }
    }

    private func addPlainTextApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url,
              let id = Bundle(url: url)?.bundleIdentifier else { return }
        if !plainTextApps.contains(id) { plainTextApps.append(id) }
    }
}

// MARK: - Notifications

private struct NotificationsPane: View {
    @Default(.notificationMirroringEnabled) private var notificationMirroringEnabled
    @Default(.mutedNotificationApps) private var mutedNotificationApps
    @Default(.dndPairingEnabled) private var dndPairingEnabled
    @Default(.focusOnShortcutName) private var focusOnShortcutName
    @Default(.focusOffShortcutName) private var focusOffShortcutName

    @State private var shortcuts: [String] = []

    var body: some View {
        Form {
            Section {
                Toggle("Mirror notifications in the notch", isOn: $notificationMirroringEnabled)
            } footer: {
                Text("Shows delivered macOS notifications in the collapsed notch. Requires Full Disk Access — you'll be prompted to grant it when first enabled.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if notificationMirroringEnabled {
                Section {
                    Toggle("Replace system banners with a Focus", isOn: $dndPairingEnabled)
                    if dndPairingEnabled {
                        shortcutPicker("Turn Focus on", selection: $focusOnShortcutName)
                        shortcutPicker("Turn Focus off", selection: $focusOffShortcutName)
                        HStack {
                            Button("New Focus Shortcut…", action: openShortcuts)
                            Spacer()
                            Button("Refresh", action: loadShortcuts)
                                .buttonStyle(.borderless)
                        }
                    }
                } header: {
                    Text("Do Not Disturb Pairing")
                } footer: {
                    Text("macOS has no public way to toggle Focus, so Perch runs Shortcuts you provide. Create two shortcuts — each a “Set Focus” action, one turning a Focus On and one Off — then pick them above. While mirroring is on, the Focus hides native banners; the notch still shows them.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if notificationMirroringEnabled {
                Section {
                    if mutedNotificationApps.isEmpty {
                        Text("No muted apps")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(mutedNotificationApps, id: \.self) { bundleID in
                        HStack {
                            Image(systemName: "bell.slash").foregroundStyle(.secondary)
                            Text(SettingsFormatHelpers.appName(for: bundleID))
                            Spacer()
                            Button {
                                mutedNotificationApps.removeAll { $0 == bundleID }
                            } label: {
                                Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Button("Mute App…", action: muteApp)
                } header: {
                    Text("Muted Apps")
                } footer: {
                    Text("Notifications from these apps are never mirrored into the notch.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onAppear(perform: loadShortcuts)
    }

    private func muteApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url,
              let id = Bundle(url: url)?.bundleIdentifier else { return }
        if !mutedNotificationApps.contains(id) { mutedNotificationApps.append(id) }
    }

    /// A picker over the user's shortcut library, plus a "None" option. Keeps a
    /// previously-saved name selectable even if the library hasn't loaded yet.
    private func shortcutPicker(_ label: String, selection: Binding<String>) -> some View {
        let options = (["", selection.wrappedValue] + shortcuts)
            .filter { $0 == "" || shortcuts.contains($0) || $0 == selection.wrappedValue }
        var seen = Set<String>()
        let unique = options.filter { seen.insert($0).inserted }
        return Picker(label, selection: selection) {
            ForEach(unique, id: \.self) { name in
                Text(name.isEmpty ? "None" : name).tag(name)
            }
        }
    }

    private func loadShortcuts() {
        shortcuts = FocusController.availableShortcuts()
    }

    private func openShortcuts() {
        if let url = URL(string: "shortcuts://create-shortcut") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Calendar

private struct CalendarPane: View {
    @ObservedObject var calendar: CalendarManager

    @Default(.calendarEnabled) private var calendarEnabled
    @Default(.calendarShowCountdown) private var calendarShowCountdown

    var body: some View {
        Form {
            Section {
                Toggle("Show calendar & meetings in the notch", isOn: $calendarEnabled)
                    .onChange(of: calendarEnabled) { _, on in
                        calendar.setEnabled(on)
                    }
                if calendarEnabled {
                    Toggle("Show next-meeting countdown in notch", isOn: $calendarShowCountdown)
                        .onChange(of: calendarShowCountdown) { _, _ in calendar.reevaluate() }
                }
                if calendarEnabled, calendar.access == .denied {
                    HStack {
                        Label("Calendar access denied", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("Open Settings…") { calendar.openSystemSettings() }
                    }
                }
                if calendarEnabled, calendar.access == .granted, !calendar.calendars.isEmpty {
                    ForEach(calendar.calendars) { cal in
                        HStack(spacing: 10) {
                            Circle().fill(cal.color).frame(width: 9, height: 9)
                            Text(cal.title)
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { !calendar.isCalendarHidden(cal.id) },
                                set: { calendar.setCalendar(cal.id, hidden: !$0) }
                            ))
                            .labelsHidden()
                        }
                    }
                }
            } footer: {
                Text("Shows today's agenda in a tab and counts down to your next meeting in the collapsed notch, with one-click Join for video calls. Requires Calendar access.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Tabs

private struct TabsPane: View {
    @ObservedObject var registry: ModuleRegistry

    var body: some View {
        Form {
            Section {
                ForEach(registry.order, id: \.self) { id in
                    if let module = registry.module(id) {
                        HStack(spacing: 10) {
                            Image(systemName: module.icon)
                                .frame(width: 18)
                                .foregroundStyle(.secondary)
                            Text(module.title)
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { registry.isEnabled(id) },
                                set: { registry.setEnabled($0, id) }
                            ))
                            .labelsHidden()
                        }
                    }
                }
                .onMove { from, to in registry.move(from: from, to: to) }
            } footer: {
                Text("Drag to reorder; toggle to show or hide a tab in the notch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Shortcuts

private struct ShortcutsPane: View {
    var body: some View {
        Form {
            Section {
                KeyboardShortcuts.Recorder("Toggle notch", name: .toggleNotch)
                KeyboardShortcuts.Recorder("Quick search", name: .quickSearch)
                LabeledContent("Paste recent") {
                    Text("⌃⌘1 … ⌃⌘0").foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - About

private struct AboutPane: View {
    var body: some View {
        Form {
            Section {
                LabeledContent("Version", value: SettingsFormatHelpers.versionString)
                Button("Check for Updates…") {
                    UpdaterController.shared.checkForUpdates()
                }
                Link("github.com/Arunava-K/Perch",
                     destination: URL(string: "https://github.com")!)
            }
        }
    }
}

// MARK: - Helpers

enum SettingsFormatHelpers {
    /// Resolve a bundle ID to a display name, falling back to the ID itself.
    static func appName(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return bundleID
        }
        return FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
    }

    static var versionString: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(v) (\(b))"
    }
}
