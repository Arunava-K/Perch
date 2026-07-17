import SwiftUI
import AppKit
import Defaults
import EventKit

@MainActor
final class ReminderManager: ObservableObject {
    @Published private(set) var reminders: [ReminderItem] = []
    @Published private(set) var overdueCount = 0
    @Published private(set) var todayCount = 0
    @Published private(set) var hasActiveItems = false
    @Published private(set) var calendars: [CalendarInfo] = []
    @Published private(set) var access: CalendarAccess = .notDetermined
    @Published private(set) var isActive = false

    private let service: ReminderServiceProviding
    private var refreshTimer: Timer?
    private var storeObserver: NSObjectProtocol?
    private var applicationObserver: NSObjectProtocol?
    private var accessRequestGeneration = 0

    init(service: ReminderServiceProviding = ReminderService()) {
        self.service = service
        self.access = service.access
        applicationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshAccessAfterSettings() }
        }
    }

    func startIfEnabled() {
        guard Defaults[.remindersEnabled] else { return }
        requestAccessAndStart()
    }

    func setEnabled(_ enabled: Bool) {
        Defaults[.remindersEnabled] = enabled
        if enabled { requestAccessAndStart() } else { stop() }
    }

    func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders") {
            NSWorkspace.shared.open(url)
        }
    }

    func openRemindersApp() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.reminders") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: List selection

    func isListHidden(_ id: String) -> Bool {
        Defaults[.hiddenReminderListIDs].contains(id)
    }

    func setList(_ id: String, hidden: Bool) {
        var set = Set(Defaults[.hiddenReminderListIDs])
        if hidden { set.insert(id) } else { set.remove(id) }
        Defaults[.hiddenReminderListIDs] = Array(set)
        refresh()
    }

    private var visibleListIDs: Set<String> {
        Set(calendars.map(\.id)).subtracting(Defaults[.hiddenReminderListIDs])
    }

    // MARK: Permission

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
                guard generation == self.accessRequestGeneration, Defaults[.remindersEnabled] else { return }
                self.access = self.service.access
                if granted { self.start() }
            }
        case .denied:
            break
        }
    }

    // MARK: Lifecycle

    private func start() {
        guard !isActive else { return }
        isActive = true
        storeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
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
        reminders = []
        overdueCount = 0
        todayCount = 0
        hasActiveItems = false
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
        calendars = service.calendars()
        let visible = visibleListIDs
        guard !visible.isEmpty else {
            reminders = []
            overdueCount = 0
            todayCount = 0
            hasActiveItems = false
            return
        }
        Task { [weak self] in
            guard let self else { return }
            let items = await self.service.reminders(in: visible)
            let overdue = items.filter { $0.isOverdue }.count
            let today = items.filter { $0.isDueToday }.count
            await MainActor.run {
                guard self.isActive else { return }
                self.reminders = items
                self.overdueCount = overdue
                self.todayCount = today
                self.hasActiveItems = overdue > 0 || today > 0
            }
        }
    }

    func reevaluate() { refresh() }

    private func refreshAccessAfterSettings() {
        guard Defaults[.remindersEnabled] else { return }
        requestAccessAndStart()
    }
}
