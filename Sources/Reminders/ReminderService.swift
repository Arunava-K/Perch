import SwiftUI
@preconcurrency import EventKit

struct ReminderItem: Identifiable, Equatable {
    let id: String
    let title: String
    let dueDate: Date?
    let isCompleted: Bool
    let priority: Int
    let listName: String
    let listColor: Color
    let notes: String?

    var isOverdue: Bool {
        guard let dueDate, !isCompleted else { return false }
        return dueDate < Calendar.current.startOfDay(for: Date())
    }

    var isDueToday: Bool {
        guard let dueDate, !isCompleted else { return false }
        return Calendar.current.isDateInToday(dueDate)
    }
}

protocol ReminderServiceProviding {
    var access: CalendarAccess { get }
    func requestAccess() async -> Bool
    func calendars() -> [CalendarInfo]
    func reminders(in lists: Set<String>) async -> [ReminderItem]
}

final class ReminderService: ReminderServiceProviding {
    private let store = EKEventStore()

    var access: CalendarAccess {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess: return .granted
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }

    func requestAccess() async -> Bool {
        (try? await store.requestFullAccessToReminders()) ?? false
    }

    func calendars() -> [CalendarInfo] {
        guard access == .granted else { return [] }
        return store.calendars(for: .reminder).map {
            CalendarInfo(id: $0.calendarIdentifier, title: $0.title,
                         color: color(for: $0))
        }
    }

    func reminders(in lists: Set<String>) async -> [ReminderItem] {
        guard access == .granted else { return [] }
        let ekCalendars = store.calendars(for: .reminder).filter { lists.contains($0.calendarIdentifier) }
        guard !ekCalendars.isEmpty else { return [] }
        let predicate = store.predicateForReminders(in: ekCalendars)
        return await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { ekReminders in
                let items = (ekReminders ?? [])
                    .filter { !$0.isCompleted }
                    .map(ReminderItem.init(ek:))
                    .sorted { a, b in
                        switch (a.dueDate, b.dueDate) {
                        case (.none, .none): return a.title < b.title
                        case (.none, .some): return false
                        case (.some, .none): return true
                        case let (.some(l), .some(r)): return l < r
                        }
                    }
                continuation.resume(returning: items)
            }
        }
    }

    private func color(for calendar: EKCalendar?) -> Color {
        guard let cg = calendar?.cgColor, let ns = NSColor(cgColor: cg) else { return .accentColor }
        return Color(nsColor: ns)
    }
}

extension ReminderItem {
    init(ek: EKReminder) {
        let base = ek.calendarItemIdentifier
        self.id = base
        self.title = ek.title?.isEmpty == false ? ek.title : "Untitled"
        self.dueDate = ek.dueDateComponents?.date
        self.isCompleted = ek.isCompleted
        self.priority = ek.priority
        self.listName = ek.calendar?.title ?? "Reminders"
        self.notes = ek.notes?.isEmpty == false ? ek.notes : nil
        self.listColor = {
            guard let cg = ek.calendar?.cgColor, let ns = NSColor(cgColor: cg) else { return .accentColor }
            return Color(nsColor: ns)
        }()
    }
}
