import SwiftUI
import Defaults
import KeyboardShortcuts

/// Settings: general behavior, history limits, shortcuts, permissions, about.
struct SettingsView: View {
    @Default(.openNotchOnHover) private var openNotchOnHover
    @Default(.historyLimit) private var historyLimit
    @Default(.historyMaxAgeDays) private var historyMaxAgeDays
    @Default(.skipSensitiveContent) private var skipSensitiveContent

    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var accessibilityGranted = AccessibilityPermission.isTrusted

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        LoginItem.setEnabled(newValue)
                    }
                Toggle("Open notch on hover", isOn: $openNotchOnHover)
            }

            Section("History") {
                Stepper(value: $historyLimit, in: 10...1000, step: 10) {
                    LabeledContent("Keep up to", value: "\(historyLimit) clips")
                }
                Stepper(value: $historyMaxAgeDays, in: 1...365, step: 1) {
                    LabeledContent("Discard after", value: "\(historyMaxAgeDays) days")
                }
                Toggle("Skip passwords & sensitive content", isOn: $skipSensitiveContent)
            }

            Section("Shortcuts") {
                KeyboardShortcuts.Recorder("Toggle notch", name: .toggleNotch)
                KeyboardShortcuts.Recorder("Quick search", name: .quickSearch)
                LabeledContent("Paste recent") {
                    Text("⌃⌘1 … ⌃⌘0").foregroundStyle(.secondary)
                }
            }

            Section("Permissions") {
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
                Text("Required to paste a clip into the active app (simulates ⌘V).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("About") {
                LabeledContent("Version", value: Self.versionString)
                Button("Check for Updates…") {
                    UpdaterController.shared.checkForUpdates()
                }
                Link("github.com/Steiner&Co/Mybar",
                     destination: URL(string: "https://github.com")!)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 540)
        .onAppear {
            launchAtLogin = LoginItem.isEnabled
            accessibilityGranted = AccessibilityPermission.isTrusted
        }
    }

    static var versionString: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(v) (\(b))"
    }
}
