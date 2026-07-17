import SwiftUI

/// Calendar / Up Next tab with Reminders merged in. The next meeting also
/// surfaces as a live activity in the collapsed notch.
@MainActor
final class CalendarModule: NotchModule {
    let id = "calendar"
    let title = "Calendar"
    let icon = "calendar"

    let calendar: CalendarManager
    let reminders: ReminderManager

    init(calendar: CalendarManager, reminders: ReminderManager) {
        self.calendar = calendar
        self.reminders = reminders
    }

    /// A live dot on the tab while the next event is imminent, or active reminders.
    var indicator: Bool { calendar.isImminent || reminders.hasActiveItems }

    /// Taller than other tabs so the month grid + agenda fit comfortably.
    var preferredExpandedHeight: CGFloat { 260 }

    func makeContent(_ context: ModuleContext) -> AnyView {
        AnyView(CalendarTab(calendar: calendar, reminders: reminders, dismiss: context.dismiss))
    }
}
