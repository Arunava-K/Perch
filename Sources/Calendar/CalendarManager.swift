import SwiftUI
import AppKit
import Defaults

/// One calendar event, flattened from EventKit into a value type the UI owns.
struct CalendarEvent: Identifiable, Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let calendarColor: Color
    let location: String?
    /// A detected video-call link (Zoom / Meet / Teams / Webex), if any.
    let videoURL: URL?
    /// Deep link that opens the event in Calendar.app.
    let appURL: URL?

    func isInProgress(at now: Date = Date()) -> Bool {
        !isAllDay && start <= now && end > now
    }

    /// Compact countdown for the collapsed flank: "12m", "1h 5m", "Now".
    func countdownString(from now: Date = Date()) -> String {
        let secs = start.timeIntervalSince(now)
        if secs <= 0 { return "Now" }
        let mins = Int(secs / 60)
        if mins < 60 { return "\(max(1, mins))m" }
        let h = mins / 60, m = mins % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    /// Human phrasing for the tab: "in 12m", "In progress".
    func relativeString(from now: Date = Date()) -> String {
        start.timeIntervalSince(now) <= 0 ? "In progress" : "in \(countdownString(from: now))"
    }

    var timeRange: String {
        if isAllDay { return "All day" }
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return "\(f.string(from: start)) – \(f.string(from: end))"
    }
}

/// Holds today's events and drives the Calendar tab plus the collapsed "Up
/// Next" flank. All EventKit access goes through `CalendarServiceProviding`.
/// Opt-in: nothing runs until the user enables it (`Defaults[.calendarEnabled]`)
/// and grants Calendar access.
@MainActor
final class CalendarManager: ObservableObject {
    /// Today's events from now onward (in-progress + upcoming), soonest first.
    @Published private(set) var events: [CalendarEvent] = []
    /// The soonest timed event still to come (or in progress) — drives the flank.
    @Published private(set) var nextEvent: CalendarEvent?
    /// True while `nextEvent` is within the imminent window — shows the flank.
    @Published private(set) var isImminent = false
    /// Available event calendars, for the Settings show/hide list.
    @Published private(set) var calendars: [CalendarInfo] = []
    /// The day currently shown in the tab's date strip.
    @Published private(set) var selectedDate: Date
    /// All events on `selectedDate` (including earlier ones), for the agenda list.
    @Published private(set) var dayEvents: [CalendarEvent] = []
    /// Start-of-day dates in the selected month that have ≥1 event (grid dots).
    @Published private(set) var datesWithEvents: Set<Date> = []
    @Published private(set) var access: CalendarAccess
    @Published private(set) var isActive = false

    /// Fired once when an event crosses the reminder lead time — wired to a peek.
    var onReminder: ((CalendarEvent) -> Void)?

    /// Show the collapsed flank when the next event starts within this window.
    static let imminentWindow: TimeInterval = 30 * 60
    /// Fire a one-time peek when an event is this close.
    private static let reminderLeadTime: TimeInterval = 5 * 60

    private let service: CalendarServiceProviding
    private var refreshTimer: Timer?
    private var storeObserver: NSObjectProtocol?
    private var applicationObserver: NSObjectProtocol?
    private var remindedEventIDs: Set<String> = []
    private var accessRequestGeneration = 0

    init(service: CalendarServiceProviding = CalendarService()) {
        self.service = service
        self.access = service.access
        self.selectedDate = Calendar.current.startOfDay(for: Date())
        applicationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshAccessAfterSettings() }
        }
    }

    /// Switch the day shown in the agenda list (driven by the date strip).
    func selectDate(_ date: Date) {
        selectedDate = Calendar.current.startOfDay(for: date)
        refreshDayEvents()
        refreshMonthMarks()
    }

    func hasEvents(on date: Date) -> Bool {
        datesWithEvents.contains(Calendar.current.startOfDay(for: date))
    }

    // MARK: Enable / permission

    /// Called at launch — only starts if the user previously opted in.
    func startIfEnabled() {
        guard Defaults[.calendarEnabled] else { return }
        requestAccessAndStart()
    }

    /// Flip the opt-in (from Settings or the in-notch enable button).
    func setEnabled(_ enabled: Bool) {
        Defaults[.calendarEnabled] = enabled
        if enabled { requestAccessAndStart() } else { stop() }
    }

    /// Open System Settings to the Calendar privacy pane (for a denied grant).
    func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    func join(_ event: CalendarEvent) {
        if let url = event.videoURL { NSWorkspace.shared.open(url) }
    }

    /// Open the event in Calendar.app (fallback action when there's no video link).
    func openInCalendar(_ event: CalendarEvent) {
        if let url = event.appURL { NSWorkspace.shared.open(url) }
    }

    // MARK: Calendar selection

    func isCalendarHidden(_ id: String) -> Bool {
        Defaults[.hiddenCalendarIDs].contains(id)
    }

    func setCalendar(_ id: String, hidden: Bool) {
        var set = Set(Defaults[.hiddenCalendarIDs])
        if hidden { set.insert(id) } else { set.remove(id) }
        Defaults[.hiddenCalendarIDs] = Array(set)
        refresh()
    }

    private func requestAccessAndStart() {
        access = service.access
        switch access {
        case .granted:
            if isActive { refresh() } else { start() }
        case .notDetermined:
            accessRequestGeneration += 1
            let generation = accessRequestGeneration
            Task { [weak self] in
                guard let self else { return }
                let granted = await self.service.requestAccess()
                guard generation == self.accessRequestGeneration, Defaults[.calendarEnabled] else { return }
                self.access = self.service.access
                if granted { self.start() }
            }
        case .denied:
            break  // surfaced in the UI with an "Open Settings" action.
        }
    }

    // MARK: Lifecycle

    private func start() {
        guard !isActive else { return }  // idempotent — never stack timers/observers.
        isActive = true
        storeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        let timer = Timer(timeInterval: 20, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
        refresh()
    }

    private func stop() {
        accessRequestGeneration += 1
        isActive = false
        refreshTimer?.invalidate()
        refreshTimer = nil
        if let storeObserver {
            NotificationCenter.default.removeObserver(storeObserver)
            self.storeObserver = nil
        }
        events = []
        nextEvent = nil
        dayEvents = []
        datesWithEvents = []
        isImminent = false
        remindedEventIDs.removeAll()
    }

    deinit {
        refreshTimer?.invalidate()
        if let storeObserver { NotificationCenter.default.removeObserver(storeObserver) }
        if let applicationObserver { NotificationCenter.default.removeObserver(applicationObserver) }
    }

    // MARK: Refresh

    private func refresh() {
        guard isActive else { return }
        access = service.access
        let now = Date()
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: now)
        let endOfDay = cal.date(bySettingHour: 23, minute: 59, second: 59, of: now) ?? now.addingTimeInterval(86400)

        calendars = service.calendars()
        let visible = Set(calendars.map(\.id)).subtracting(Defaults[.hiddenCalendarIDs])
        let mapped = service.events(from: startOfDay, to: endOfDay, calendarIDs: visible)
            .filter { $0.end > now }

        events = mapped
        // "Up next" = the soonest event that hasn't started yet, so the flank
        // counts down and never gets stuck at "Now" during an in-progress event.
        nextEvent = mapped.first { !$0.isAllDay && $0.start > now }

        if let next = nextEvent {
            let lead = next.start.timeIntervalSince(now)  // always > 0
            // Persistent countdown flank is opt-in; the one-time peek always fires.
            isImminent = Defaults[.calendarShowCountdown] && lead <= Self.imminentWindow
            if lead <= Self.reminderLeadTime, !remindedEventIDs.contains(next.id) {
                remindedEventIDs.insert(next.id)
                onReminder?(next)
            }
        } else {
            isImminent = false
        }

        refreshDayEvents()
        refreshMonthMarks()
    }

    /// Re-run live-activity evaluation immediately (e.g. after a settings change).
    func reevaluate() { refresh() }

    /// The user may grant access in System Settings while the app is inactive.
    private func refreshAccessAfterSettings() {
        guard Defaults[.calendarEnabled] else { return }
        requestAccessAndStart()
    }

    private var visibleCalendarIDs: Set<String> {
        Set(calendars.map(\.id)).subtracting(Defaults[.hiddenCalendarIDs])
    }

    /// All events on the selected day (past + future), for the agenda list.
    private func refreshDayEvents() {
        guard isActive else { dayEvents = []; return }
        let cal = Calendar.current
        let end = cal.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate.addingTimeInterval(86400)
        dayEvents = service.events(from: selectedDate, to: end, calendarIDs: visibleCalendarIDs)
    }

    /// Which days in the selected month have events (for the grid's dots).
    private func refreshMonthMarks() {
        guard isActive, let month = Calendar.current.dateInterval(of: .month, for: selectedDate) else {
            datesWithEvents = []
            return
        }
        let evs = service.events(from: month.start, to: month.end, calendarIDs: visibleCalendarIDs)
        datesWithEvents = Set(evs.map { Calendar.current.startOfDay(for: $0.start) })
    }
}
