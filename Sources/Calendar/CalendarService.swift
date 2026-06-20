import SwiftUI
@preconcurrency import EventKit

/// Whether Mybar can read calendar events — our own enum so EventKit stays
/// confined to this file (the rest of the app never imports it).
enum CalendarAccess {
    case notDetermined, granted, denied
}

/// A selectable event calendar (for the Settings show/hide list).
struct CalendarInfo: Identifiable, Equatable {
    let id: String
    let title: String
    let color: Color
}

/// The EventKit boundary: everything that touches `EKEventStore` lives behind
/// this protocol, so `CalendarManager` holds only state and the app stays
/// testable with a fake service. (Pattern borrowed from boring.notch / Calendr.)
protocol CalendarServiceProviding {
    var access: CalendarAccess { get }
    func requestAccess() async -> Bool
    func calendars() -> [CalendarInfo]
    func events(from start: Date, to end: Date, calendarIDs: Set<String>) -> [CalendarEvent]
}

final class CalendarService: CalendarServiceProviding {
    private let store = EKEventStore()

    var access: CalendarAccess {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: return .granted
        case .notDetermined: return .notDetermined
        default: return .denied  // denied / restricted / write-only
        }
    }

    func requestAccess() async -> Bool {
        (try? await store.requestFullAccessToEvents()) ?? false
    }

    func calendars() -> [CalendarInfo] {
        guard access == .granted else { return [] }
        return store.calendars(for: .event).map {
            CalendarInfo(id: $0.calendarIdentifier, title: $0.title, color: CalendarEvent.color(for: $0))
        }
    }

    func events(from start: Date, to end: Date, calendarIDs: Set<String>) -> [CalendarEvent] {
        guard access == .granted else { return [] }
        // An empty visible set means the user hid every calendar — show nothing.
        let ekCalendars = store.calendars(for: .event).filter { calendarIDs.contains($0.calendarIdentifier) }
        guard !ekCalendars.isEmpty else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: ekCalendars)
        return store.events(matching: predicate)
            .map(CalendarEvent.init(ek:))
            .sorted { $0.start < $1.start }
    }
}

// MARK: - EventKit → CalendarEvent mapping (kept here so EventKit is confined)

extension CalendarEvent {
    init(ek: EKEvent) {
        // Recurring events share an identifier; disambiguate by occurrence start.
        let base = ek.eventIdentifier ?? UUID().uuidString
        self.id = "\(base)@\(ek.startDate.timeIntervalSince1970)"
        self.title = ek.title?.isEmpty == false ? ek.title : "Untitled Event"
        self.start = ek.startDate
        self.end = ek.endDate
        self.isAllDay = ek.isAllDay
        let loc = ek.location?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.location = (loc?.isEmpty == false) ? loc : nil
        self.videoURL = CalendarEvent.detectVideoURL(ek)
        self.appURL = CalendarEvent.appURL(for: ek)
        self.calendarColor = CalendarEvent.color(for: ek.calendar)
    }

    static func color(for calendar: EKCalendar?) -> Color {
        guard let cg = calendar?.cgColor, let ns = NSColor(cgColor: cg) else { return .accentColor }
        return Color(nsColor: ns)
    }

    /// Scan the URL, location, and notes for a known video-meeting link.
    static func detectVideoURL(_ ek: EKEvent) -> URL? {
        let patterns = [
            "https://[\\w.-]*zoom\\.us/[^\\s<>]+",
            "https://meet\\.google\\.com/[^\\s<>]+",
            "https://teams\\.microsoft\\.com/[^\\s<>]+",
            "https://[\\w.-]*webex\\.com/[^\\s<>]+",
        ]
        let haystacks = [ek.url?.absoluteString, ek.location, ek.notes].compactMap { $0 }
        for text in haystacks {
            for pattern in patterns {
                if let range = text.range(of: pattern, options: .regularExpression) {
                    return URL(string: String(text[range]))
                }
            }
        }
        if let url = ek.url, let host = url.host,
           ["zoom.us", "meet.google.com", "teams.microsoft.com", "webex.com"].contains(where: { host.contains($0) }) {
            return url
        }
        return nil
    }

    /// A deep link that opens this event in Calendar.app (handles recurrence).
    static func appURL(for ek: EKEvent) -> URL? {
        guard let id = ek.calendarItemIdentifier
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        var datePart = ""
        if ek.hasRecurrenceRules || ek.isDetached {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
            if !ek.isAllDay { f.timeZone = TimeZone(secondsFromGMT: 0) }
            datePart = "/\(f.string(from: ek.startDate))"
        }
        return URL(string: "ical://ekevent\(datePart)/\(id)?method=show&options=more")
    }
}
