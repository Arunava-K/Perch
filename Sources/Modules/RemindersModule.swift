import SwiftUI

@MainActor
final class RemindersModule: NotchModule {
    let id = "reminders"
    let title = "Reminders"
    let icon = "checklist"

    let reminders: ReminderManager

    init(reminders: ReminderManager) { self.reminders = reminders }

    var indicator: Bool { reminders.hasActiveItems }

    func makeContent(_ context: ModuleContext) -> AnyView {
        AnyView(RemindersTab(reminders: reminders, dismiss: context.dismiss))
    }
}
