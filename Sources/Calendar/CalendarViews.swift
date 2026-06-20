import SwiftUI
import Defaults

/// A colored dot on the left, countdown to the next event on the right —
/// flanking the camera while the notch is collapsed (the "Up Next" activity).
struct CollapsedCalendarView: View {
    @ObservedObject var calendar: CalendarManager
    @State private var now = Date()
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 0) {
            Circle()
                .fill(calendar.nextEvent?.calendarColor ?? .accentColor)
                .frame(width: 8, height: 8)
                .padding(.leading, 18)

            Spacer(minLength: 0)

            Text(calendar.nextEvent?.countdownString(from: now) ?? "")
                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .padding(.trailing, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onReceive(tick) { now = $0 }
    }
}

/// The Calendar tab: a month grid on the left (~70%) and the selected day's
/// agenda on the right (~30%).
struct CalendarTab: View {
    @ObservedObject var calendar: CalendarManager
    let dismiss: () -> Void

    @State private var selectedDate = Date()
    @State private var now = Date()
    private let tick = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if calendar.access != .granted {
                permissionView
            } else {
                splitView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onReceive(tick) { now = $0 }
        .onAppear {
            selectedDate = Date()
            calendar.selectDate(selectedDate)
        }
        .onChange(of: selectedDate) { _, date in
            calendar.selectDate(date)
        }
        .transition(.blurFade)
    }

    private var splitView: some View {
        GeometryReader { geo in
            HStack(spacing: 16) {
                MonthGrid(selectedDate: $selectedDate, hasEvents: calendar.hasEvents)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Rectangle()
                    .fill(.white.opacity(0.08))
                    .frame(width: 1)
                    .padding(.vertical, 2)

                agendaColumn
                    .frame(width: max(180, geo.size.width * 0.3), alignment: .leading)
            }
        }
        .padding(.horizontal, 26)
        .padding(.top, 2)
        .padding(.bottom, 8)
    }

    // MARK: Agenda (right column)

    private var agendaColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(selectedDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                .font(.system(size: 10.5, weight: .bold))
                .tracking(0.5)
                .textCase(.uppercase)
                .foregroundStyle(.white.opacity(0.4))

            if calendar.dayEvents.isEmpty {
                EmptyEventsView(selectedDate: selectedDate)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(calendar.dayEvents.enumerated()), id: \.element.id) { idx, event in
                            Button {
                                calendar.openInCalendar(event)
                                dismiss()
                            } label: {
                                agendaRow(event)
                            }
                            .buttonStyle(PressableStyle())
                            .staggeredAppear(idx)
                        }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func agendaRow(_ e: CalendarEvent) -> some View {
        let isPast = e.end < now && Calendar.current.isDateInToday(e.start)
        return HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(e.calendarColor)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 2) {
                Text(e.title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Text(e.isAllDay ? "All-day" : shortTime(e.start))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                    if e.videoURL != nil {
                        Image(systemName: "video.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .opacity(isPast ? 0.5 : 1)
    }

    // MARK: Permission

    private var permissionView: some View {
        VStack(spacing: 10) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 26))
                .foregroundStyle(.white.opacity(0.5))
            Text("Show your day in the notch")
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(.white)
            Button(calendar.access == .denied ? "Open System Settings" : "Enable Calendar") {
                if calendar.access == .denied {
                    calendar.openSystemSettings()
                } else {
                    calendar.setEnabled(true)
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

    private func shortTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f.string(from: date)
    }
}

// MARK: - Empty state

private struct EmptyEventsView: View {
    let selectedDate: Date

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: "calendar.badge.checkmark")
                .font(.system(size: 20))
                .foregroundStyle(.white.opacity(0.4))
            Text(Calendar.current.isDateInToday(selectedDate) ? "Nothing today" : "No events")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

// MARK: - Month grid (left column)

private struct MonthGrid: View {
    @Binding var selectedDate: Date
    let hasEvents: (Date) -> Bool

    private var cal: Calendar { Calendar.current }

    var body: some View {
        VStack(spacing: 4) {
            monthHeader
            weekdayHeader
            ForEach(0..<6, id: \.self) { week in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { day in
                        dayCell(date(week: week, day: day))
                    }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var monthHeader: some View {
        HStack(spacing: 8) {
            Text(selectedDate.formatted(.dateTime.month(.wide).year()))
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(.white)
            Spacer(minLength: 0)
            navButton("chevron.left") { shiftMonth(-1) }
            navButton("chevron.right") { shiftMonth(1) }
        }
        .padding(.bottom, 1)
    }

    private func navButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 22, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.35))
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let inMonth = cal.isDate(day, equalTo: selectedDate, toGranularity: .month)
        let isToday = cal.isDateInToday(day)
        let isSelected = cal.isDate(day, inSameDayAs: selectedDate)
        let marked = inMonth && hasEvents(day)
        return Button {
            selectedDate = day
            if Defaults[.hapticFeedback] { Haptics.tap() }
        } label: {
            VStack(spacing: 2) {
                Text("\(cal.component(.day, from: day))")
                    .font(.system(size: 12, weight: isToday ? .bold : .medium))
                    .foregroundStyle(dayColor(inMonth: inMonth, isToday: isToday, isSelected: isSelected))
                    .frame(width: 23, height: 23)
                    .background(
                        Circle().fill(isToday ? Color.accentColor
                                      : (isSelected ? Color.white.opacity(0.15) : .clear))
                    )
                Circle()
                    .fill(marked ? Color.white.opacity(0.55) : .clear)
                    .frame(width: 3, height: 3)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func dayColor(inMonth: Bool, isToday: Bool, isSelected: Bool) -> Color {
        if isToday || isSelected { return .white }
        return inMonth ? .white.opacity(0.85) : .white.opacity(0.25)
    }

    // MARK: Date math

    private var weekdaySymbols: [String] {
        let symbols = cal.veryShortStandaloneWeekdaySymbols
        let first = cal.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    /// Start of the grid: the first weekday cell on/before the 1st of the month.
    private var gridStart: Date {
        guard let firstOfMonth = cal.dateInterval(of: .month, for: selectedDate)?.start else {
            return cal.startOfDay(for: selectedDate)
        }
        let weekdayOfFirst = cal.component(.weekday, from: firstOfMonth)
        let leading = (weekdayOfFirst - cal.firstWeekday + 7) % 7
        return cal.date(byAdding: .day, value: -leading, to: firstOfMonth) ?? firstOfMonth
    }

    private func date(week: Int, day: Int) -> Date {
        cal.date(byAdding: .day, value: week * 7 + day, to: gridStart) ?? gridStart
    }

    private func shiftMonth(_ delta: Int) {
        if let d = cal.date(byAdding: .month, value: delta, to: selectedDate) {
            withAnimation(.easeOut(duration: 0.18)) { selectedDate = d }
        }
    }
}
