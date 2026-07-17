import SwiftUI
import Defaults

struct CollapsedRemindersView: View {
    @ObservedObject var reminders: ReminderManager

    var body: some View {
        HStack(spacing: 0) {
            Circle()
                .fill(reminders.overdueCount > 0 ? .red : .accentColor)
                .frame(width: 8, height: 8)
                .padding(.leading, 18)

            Spacer(minLength: 0)

            Text(label)
                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .padding(.trailing, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var label: String {
        if reminders.overdueCount > 0 {
            return "\(reminders.overdueCount) overdue"
        }
        return "\(reminders.todayCount) today"
    }
}

// MARK: - Expanded tab

struct RemindersTab: View {
    @ObservedObject var reminders: ReminderManager
    let dismiss: () -> Void

    var body: some View {
        Group {
            if reminders.access != .granted {
                permissionView
            } else {
                contentView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.blurFade)
    }

    // MARK: Permission

    private var permissionView: some View {
        VStack(spacing: 10) {
            Image(systemName: "checklist")
                .font(.system(size: 26))
                .foregroundStyle(.white.opacity(0.5))
            Text("See your reminders in the notch")
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(.white)
            Button(reminders.access == .denied ? "Open System Settings" : "Enable Reminders") {
                if reminders.access == .denied {
                    reminders.openSystemSettings()
                } else {
                    reminders.setEnabled(true)
                }
            }
            .buttonStyle(PressableStyle())
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Capsule().fill(.white.opacity(0.16)))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Content

    private var contentView: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Reminders")
                    .font(.system(size: 10.5, weight: .bold))
                    .tracking(0.5)
                    .textCase(.uppercase)
                    .foregroundStyle(.white.opacity(0.4))
                Spacer()
                Button {
                    reminders.openRemindersApp()
                } label: {
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.35))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 6)

            if reminders.reminders.isEmpty {
                emptyState
            } else {
                listContent
            }
        }
        .padding(.horizontal, 26)
        .padding(.top, 2)
        .padding(.bottom, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 5) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 20))
                .foregroundStyle(.white.opacity(0.4))
            Text("All caught up")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var listContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(reminders.reminders.enumerated()), id: \.element.id) { idx, item in
                    Button {
                        reminders.openRemindersApp()
                        dismiss()
                    } label: {
                        reminderRow(item)
                    }
                    .buttonStyle(PressableStyle())
                    .staggeredAppear(idx)
                }
            }
        }
    }

    private func reminderRow(_ item: ReminderItem) -> some View {
        HStack(spacing: 8) {
            Circle()
                .stroke(item.isOverdue ? Color.red : item.listColor, lineWidth: 2)
                .frame(width: 10, height: 10)
                .overlay(
                    Circle()
                        .fill(item.isOverdue ? Color.red : item.listColor)
                        .frame(width: 5, height: 5)
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if let date = item.dueDate {
                        Text(dueDateLabel(date, overdue: item.isOverdue))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(item.isOverdue ? .red : .white.opacity(0.5))
                    }
                    Text("· \(item.listName)")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.35))
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
    }

    private func dueDateLabel(_ date: Date, overdue: Bool) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInTomorrow(date) { return "Tomorrow" }
        if overdue { return "Overdue" }
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: date)
    }
}


