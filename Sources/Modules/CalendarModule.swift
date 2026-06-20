import SwiftUI

/// Calendar / Up Next tab. The next meeting also surfaces as a live activity in
/// the collapsed notch (wired in the window controller, like the timer).
@MainActor
final class CalendarModule: NotchModule {
    let id = "calendar"
    let title = "Calendar"
    let icon = "calendar"

    let calendar: CalendarManager

    init(calendar: CalendarManager) { self.calendar = calendar }

    /// A live dot on the tab while the next event is imminent.
    var indicator: Bool { calendar.isImminent }

    /// Taller than other tabs so the month grid + agenda fit comfortably.
    var preferredExpandedHeight: CGFloat { 260 }

    func makeContent(_ context: ModuleContext) -> AnyView {
        AnyView(CalendarTab(calendar: calendar, dismiss: context.dismiss))
    }
}
