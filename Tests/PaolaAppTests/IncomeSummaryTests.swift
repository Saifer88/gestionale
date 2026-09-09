import Foundation
import PaolaCore
@testable import PaolaApp
import XCTest

final class IncomeSummaryTests: XCTestCase {
    private var calendar: Calendar {
        var value = SchedulingSuggestions.calendar
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    private func date(_ year: Int = 2026, _ month: Int = 9, _ day: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    func testCardsSeparateCalendarPeriodsAndIgnoreChargesUsesAndRefunds() throws {
        let entries = [
            LedgerEntry(date: date(2025, 12, 31), kind: .payment, amountCents: 99900, sourceKey: "prior-year"),
            LedgerEntry(date: date(2026, 1, 1), kind: .payment, amountCents: 10000, sourceKey: "jan"),
            LedgerEntry(date: date(2026, 9, 1), kind: .payment, amountCents: 20000, sourceKey: "sep"),
            LedgerEntry(date: date(2026, 9, 6), kind: .payment, amountCents: 30000, sourceKey: "sunday"),
            LedgerEntry(date: date(2026, 9, 7), kind: .payment, amountCents: 40000, sourceKey: "monday"),
            LedgerEntry(date: date(), kind: .payment, amountCents: 5000, sourceKey: "today"),
            LedgerEntry(date: date(), kind: .charge, amountCents: 80000, sourceKey: "charge"),
            LedgerEntry(date: date(), kind: .refund, amountCents: 2000, sourceKey: "refund")
        ]
        let summary = try IncomeSummary(entries: entries, now: date(), calendar: calendar)
        XCTAssertEqual(summary.annualCents, 105000)
        XCTAssertEqual(summary.monthlyCents, 95000)
        XCTAssertEqual(summary.weeklyCents, 45000)
    }

    func testWeekCanCrossYearBoundaryAndDuplicateSourcesCountOnce() throws {
        let lastYear = LedgerEntry(date: date(2025, 12, 31), kind: .payment, amountCents: 10000, sourceKey: "last")
        let current = LedgerEntry(date: date(2026, 1, 1), kind: .payment, amountCents: 5000, sourceKey: "current")
        let duplicate = LedgerEntry(date: current.date, kind: .payment, amountCents: 5000, sourceKey: "current")
        let summary = try IncomeSummary(entries: [lastYear, current, duplicate], now: date(2026, 1, 1), calendar: calendar)
        XCTAssertEqual(summary.annualCents, 5000)
        XCTAssertEqual(summary.monthlyCents, 5000)
        XCTAssertEqual(summary.weeklyCents, 15000)
    }
}
