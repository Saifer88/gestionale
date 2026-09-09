import Foundation

public enum SchedulingSuggestions {
    public static let quickHours = [7, 8, 9, 10, 13, 14, 15, 16, 17, 18, 19, 20]

    public static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "it_IT")
        calendar.timeZone = .current
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    public static func weekDays(containing date: Date, calendar: Calendar = calendar) throws -> [Date] {
        guard date.timeIntervalSinceReferenceDate.isFinite,
              let week = calendar.dateInterval(of: .weekOfYear, for: date) else {
            throw SchedulingError.invalidDate
        }
        return try (0..<7).map { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: week.start) else {
                throw SchedulingError.invalidDate
            }
            return day
        }
    }

    public static func suggestedDays(from now: Date, calendar: Calendar = calendar) throws -> [Date] {
        let currentWeek = try weekDays(containing: now, calendar: calendar)
        guard let lastDay = currentWeek.last,
              let nextMonday = calendar.date(byAdding: .day, value: 1, to: lastDay) else {
            throw SchedulingError.invalidDate
        }
        let today = calendar.startOfDay(for: now)
        let days = currentWeek.filter { $0 >= today } + (try weekDays(containing: nextMonday, calendar: calendar))
        return days.filter { !calendar.isDateInWeekend($0) }
    }

    public static func availableHours(
        on day: Date,
        durationMinutes: Int,
        sessions: [TrainingSession],
        blocks: [Unavailability],
        excludingSessionID: UUID? = nil,
        now: Date = Date(),
        calendar: Calendar = calendar
    ) throws -> [Date] {
        guard (1...1440).contains(durationMinutes) else { throw SchedulingError.invalidDuration }
        guard day.timeIntervalSinceReferenceDate.isFinite, now.timeIntervalSinceReferenceDate.isFinite else {
            throw SchedulingError.invalidDate
        }
        let start = calendar.startOfDay(for: day)
        // Strict matching omits missing DST hours and proposes a repeated hour only once.
        return try quickHours.compactMap { hour in
            guard let candidate = calendar.date(
                bySettingHour: hour, minute: 0, second: 0, of: start,
                matchingPolicy: .strict, repeatedTimePolicy: .first
            ), calendar.isDate(candidate, inSameDayAs: day),
            calendar.component(.hour, from: candidate) == hour, candidate >= now else { return nil }
            guard try isAvailable(candidate, durationMinutes: durationMinutes, sessions: sessions,
                                  blocks: blocks, excludingSessionID: excludingSessionID) else { return nil }
            return candidate
        }
    }

    public static func isAvailable(
        _ start: Date, durationMinutes: Int, sessions: [TrainingSession], blocks: [Unavailability],
        excludingSessionID: UUID? = nil
    ) throws -> Bool {
        guard (1...1440).contains(durationMinutes) else { throw SchedulingError.invalidDuration }
        guard start.timeIntervalSinceReferenceDate.isFinite else { throw SchedulingError.invalidDate }
        let end = start.addingTimeInterval(Double(durationMinutes) * 60)
        return !sessions.contains {
            $0.id != excludingSessionID && $0.status != .cancelled && $0.status != .noShow
                && $0.startDate < end && $0.endDate > start
        } && !blocks.contains { $0.startDate < end && $0.endDate > start }
    }

    public static func dayLabel(_ date: Date, calendar: Calendar = calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "it_IT")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "EEEE d"
        let label = formatter.string(from: date)
        return label.prefix(1).uppercased() + label.dropFirst()
    }

    public static func hourLabel(_ date: Date, calendar: Calendar = calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "it_IT")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

public enum SchedulingError: LocalizedError {
    case invalidDate, invalidDuration

    public var errorDescription: String? {
        switch self {
        case .invalidDate: "Impossibile calcolare le date proposte. Controlla il giorno selezionato."
        case .invalidDuration: "La durata deve essere compresa tra 1 e 1440 minuti."
        }
    }
}
