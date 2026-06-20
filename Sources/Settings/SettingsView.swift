import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Defaults
import KeyboardShortcuts

/// The Settings window: a sidebar of grouped panes (General, Clipboard,
/// Notifications, Calendar, Tabs, Shortcuts, About) with a detail form on the
/// right, matching the modern macOS System Settings shape.
struct SettingsView: View {
    @ObservedObject var registry: ModuleRegistry
    @ObservedObject var calendar: CalendarManager

    @State private var selection: SettingsPane? = .general

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: $selection) { pane in
                Label(pane.title, systemImage: pane.icon)
                    .tag(pane)
            }
            .navigationSplitViewColumnWidth(min: 178, ideal: 196, max: 230)
        } detail: {
            detail(for: selection ?? .general)
                .formStyle(.grouped)
                .navigationTitle((selection ?? .general).title)
        }
        .frame(minWidth: 680, idealWidth: 720, minHeight: 460, idealHeight: 540)
    }

    @ViewBuilder
    private func detail(for pane: SettingsPane) -> some View {
        switch pane {
        case .general: GeneralPane()
        case .clipboard: ClipboardPane()
        case .notifications: NotificationsPane()
        case .calendar: CalendarPane(calendar: calendar)
        case .tabs: TabsPane(registry: registry)
        case .shortcuts: ShortcutsPane()
        case .about: AboutPane()
        }
    }
}

/// The sidebar categories.
enum SettingsPane: String, CaseIterable, Identifiable {
    case general, clipboard, notifications, calendar, tabs, shortcuts, about

    var id: Self { self }

    var title: String {
        switch self {
        case .general: return "General"
        case .clipboard: return "Clipboard"
        case .notifications: return "Notifications"
        case .calendar: return "Calendar"
        case .tabs: return "Tabs"
        case .shortcuts: return "Shortcuts"
        case .about: return "About"
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .clipboard: return "doc.on.clipboard"
        case .notifications: return "bell.badge"
        case .calendar: return "calendar"
        case .tabs: return "square.grid.2x2"
        case .shortcuts: return "keyboard"
        case .about: return "info.circle"
        }
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

    var body: some View {
        Form {
            Section {
                Toggle("Mirror notifications in the notch", isOn: $notificationMirroringEnabled)
            } footer: {
                Text("Shows delivered macOS notifications in the collapsed notch. Requires Full Disk Access — you'll be prompted to grant it when first enabled.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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
                Link("github.com/Steiner&Co/Mybar",
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
