import Foundation
import PaolaCore

struct IncomeSummary {
    let annualCents: Int64
    let monthlyCents: Int64
    let weeklyCents: Int64

    init(entries: [LedgerEntry], now: Date = Date(), calendar: Calendar = SchedulingSuggestions.calendar) throws {
        guard now.timeIntervalSinceReferenceDate.isFinite,
              let year = calendar.dateInterval(of: .year, for: now),
              let month = calendar.dateInterval(of: .month, for: now),
              let week = calendar.dateInterval(of: .weekOfYear, for: now) else {
            throw SchedulingError.invalidDate
        }
        func received(_ period: DateInterval) -> Int64 {
            BusinessReports.statement(clientID: nil, from: period.start, to: period.end, entries: entries).paidCents
        }
        annualCents = received(year)
        monthlyCents = received(month)
        weeklyCents = received(week)
    }
}
