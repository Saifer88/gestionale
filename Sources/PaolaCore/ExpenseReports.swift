import Foundation

/// Calcolo dei totali delle spese in un periodo, tenendo conto delle ricorrenti mensili.
///
/// Regole:
/// - Le spese una tantum contano nel periodo in cui cade la loro `date`.
/// - Le ricorrenti mensili valgono ogni mese a partire dal mese della loro `date`
///   (considerate il primo giorno del mese). In un intervallo contano una volta per
///   ogni "primo del mese" incluso nell'intervallo, dal loro inizio in poi.
public enum ExpenseReports {

    /// Totale spese (centesimi) che ricadono nell'intervallo `[from, to)`.
    public static func total(_ expenses: [Expense], from: Date, to: Date,
                             calendar: Calendar = SchedulingSuggestions.calendar) -> Int64 {
        var sum: Int64 = 0
        for expense in expenses {
            switch expense.kind {
            case .oneTime:
                if expense.date >= from && expense.date < to {
                    sum &+= expense.amountCents
                }
            case .monthlyRecurring:
                sum &+= expense.amountCents &* Int64(recurringOccurrences(expense, from: from, to: to, calendar: calendar))
            }
        }
        return sum
    }

    /// Numero di occorrenze (primi del mese) di una spesa ricorrente nell'intervallo
    /// `[from, to)`, non prima del mese di inizio della spesa.
    static func recurringOccurrences(_ expense: Expense, from: Date, to: Date,
                                     calendar: Calendar) -> Int {
        guard to > from else { return 0 }
        // Inizio effettivo: il primo del mese della data della spesa.
        guard let expenseMonthStart = calendar.dateInterval(of: .month, for: expense.date)?.start,
              let fromMonthStart = calendar.dateInterval(of: .month, for: from)?.start else { return 0 }
        // Primo "primo del mese" candidato = max(inizio spesa, inizio mese di `from`).
        var cursor = max(expenseMonthStart, fromMonthStart)
        var count = 0
        // Avanza di mese in mese finché il primo del mese resta dentro [from, to).
        while cursor < to {
            if cursor >= from { count += 1 }
            guard let next = calendar.date(byAdding: .month, value: 1, to: cursor) else { break }
            cursor = next
        }
        return count
    }
}
