import Foundation
import PaolaCore

struct IncomeSummary {
    let annualCents: Int64
    let monthlyCents: Int64
    let weeklyCents: Int64
    // Spese del periodo (una tantum + ricorrenti mensili).
    let annualExpensesCents: Int64
    let monthlyExpensesCents: Int64
    let weeklyExpensesCents: Int64

    // EBIT = incassi − spese del periodo.
    var annualEbitCents: Int64 { annualCents - annualExpensesCents }
    var monthlyEbitCents: Int64 { monthlyCents - monthlyExpensesCents }
    var weeklyEbitCents: Int64 { weeklyCents - weeklyExpensesCents }

    init(entries: [LedgerEntry], expenses: [Expense] = [],
         now: Date = Date(), calendar: Calendar = SchedulingSuggestions.calendar) throws {
        guard now.timeIntervalSinceReferenceDate.isFinite,
              let year = calendar.dateInterval(of: .year, for: now),
              let month = calendar.dateInterval(of: .month, for: now),
              let week = calendar.dateInterval(of: .weekOfYear, for: now) else {
            throw SchedulingError.invalidDate
        }
        func received(_ period: DateInterval) -> Int64 {
            BusinessReports.statement(clientID: nil, from: period.start, to: period.end, entries: entries).paidCents
        }
        func spent(_ period: DateInterval) -> Int64 {
            ExpenseReports.total(expenses, from: period.start, to: period.end, calendar: calendar)
        }
        annualCents = received(year)
        monthlyCents = received(month)
        weeklyCents = received(week)
        // Le spese annuali si fermano al mese corrente: le ricorrenti dei mesi futuri
        // non concorrono al totale né all'EBIT annuale.
        annualExpensesCents = ExpenseReports.total(expenses, from: year.start,
                                                   to: min(year.end, month.end), calendar: calendar)
        monthlyExpensesCents = spent(month)
        weeklyExpensesCents = spent(week)
    }
}
