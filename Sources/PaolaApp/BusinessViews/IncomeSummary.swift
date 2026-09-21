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
    // Spese future previste dell'anno in corso: dai mesi successivi a quello corrente
    // fino a fine anno (ricorrenti mensili e una tantum già datate nel futuro).
    let futureExpensesCents: Int64

    // EBIT = incassi − spese del periodo.
    var annualEbitCents: Int64 { annualCents - annualExpensesCents }
    var monthlyEbitCents: Int64 { monthlyCents - monthlyExpensesCents }
    var weeklyEbitCents: Int64 { weeklyCents - weeklyExpensesCents }

    // Ripartizione fiscale (bianchi/neri/inps/imposte/netto) mensile e annuale.
    let monthlyTax: TaxBreakdown
    let annualTax: TaxBreakdown

    // Spese personali del periodo (escluse dal riepilogo economico). Le annuali sono
    // cappate al mese corrente, come le spese attività e il netto annuale.
    let monthlyPersonalExpensesCents: Int64
    let annualPersonalExpensesCents: Int64

    // Bilancio personale = Netto − spese personali del periodo.
    var monthlyPersonalBalanceCents: Int64 { monthlyTax.netCents - monthlyPersonalExpensesCents }
    var annualPersonalBalanceCents: Int64 { annualTax.netCents - annualPersonalExpensesCents }

    init(entries: [LedgerEntry], expenses: [Expense] = [],
         sessions: [TrainingSession] = [], packages: [LessonPackage] = [],
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
        // Spese future previste dell'anno: dal mese prossimo a fine anno.
        futureExpensesCents = ExpenseReports.total(expenses, from: min(month.end, year.end),
                                                   to: year.end, calendar: calendar)
        // Ripartizione fiscale degli incassi del mese e dell'anno; il netto sottrae
        // anche le spese del periodo (annuali cappate al mese corrente, come sopra).
        monthlyTax = BusinessReports.taxSummary(from: month.start, to: month.end,
                                                entries: entries, sessions: sessions, packages: packages,
                                                expensesCents: monthlyExpensesCents)
        annualTax = BusinessReports.taxSummary(from: year.start, to: year.end,
                                               entries: entries, sessions: sessions, packages: packages,
                                               expensesCents: annualExpensesCents)
        // Spese personali del periodo (annuali cappate al mese corrente, come sopra).
        monthlyPersonalExpensesCents = ExpenseReports.totalPersonal(expenses, from: month.start,
                                                                    to: month.end, calendar: calendar)
        annualPersonalExpensesCents = ExpenseReports.totalPersonal(expenses, from: year.start,
                                                                   to: min(year.end, month.end), calendar: calendar)
    }
}
