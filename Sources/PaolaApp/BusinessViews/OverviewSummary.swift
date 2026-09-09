import Foundation
import PaolaCore

enum CalendarAppointments {
    static func visible(_ sessions: [TrainingSession], in interval: DateInterval) -> [TrainingSession] {
        var seen = Set<UUID>()
        return sessions.filter {
            $0.statusRaw != SessionStatus.cancelled.rawValue
                && $0.startDate < interval.end && $0.endDate > interval.start
        }.sorted {
            $0.startDate == $1.startDate ? $0.id.uuidString < $1.id.uuidString : $0.startDate < $1.startDate
        }.filter { seen.insert($0.id).inserted }
    }
}

struct OverviewSummary {
    let income: IncomeSummary
    let forecastCents: Int64
    let bookedClientsThisWeek: Int
    let plannedSessionsThisWeek: Int
    let today: [TrainingSession]

    init(
        entries: [LedgerEntry], sessions: [TrainingSession], participants: [SessionParticipant],
        now: Date = Date(), calendar: Calendar = SchedulingSuggestions.calendar
    ) throws {
        income = try IncomeSummary(entries: entries, now: now, calendar: calendar)
        guard let week = calendar.dateInterval(of: .weekOfYear, for: now),
              let day = calendar.dateInterval(of: .day, for: now) else {
            throw SchedulingError.invalidDate
        }
        let planned = sessions.filter { $0.statusRaw == SessionStatus.planned.rawValue }
        let weeklyIDs = Set(planned.filter { $0.startDate >= week.start && $0.startDate < week.end }.map(\.id))
        plannedSessionsThisWeek = weeklyIDs.count
        bookedClientsThisWeek = Set(participants.filter { weeklyIDs.contains($0.sessionID) }.map(\.clientID)).count
        today = CalendarAppointments.visible(sessions, in: day)

        let futureIDs = Set(planned.filter { $0.startDate > now }.map(\.id))
        var forecast: Int64 = 0
        // The same booking may arrive more than once during synchronization; never count it twice.
        var bookings: [String: SessionParticipant] = [:]
        for person in participants where futureIDs.contains(person.sessionID) {
            let key = "\(person.sessionID):\(person.clientID)"
            if let previous = bookings[key] {
                guard previous.priceCents == person.priceCents, previous.packageID == person.packageID else {
                    throw BusinessInputError(message: "La previsione contiene prezzi o pacchetti discordanti per lo stesso appuntamento.")
                }
                continue
            }
            bookings[key] = person
            guard person.priceCents >= 0 else {
                throw BusinessInputError(message: "La previsione contiene un prezzo non valido.")
            }
            if person.packageID == nil {
                let sum = forecast.addingReportingOverflow(person.priceCents)
                guard !sum.overflow else {
                    throw BusinessInputError(message: "Il totale degli incassi previsti supera il limite supportato.")
                }
                forecast = sum.partialValue
            }
        }
        forecastCents = forecast
    }
}
