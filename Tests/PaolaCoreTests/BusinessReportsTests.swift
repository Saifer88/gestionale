import Foundation
@testable import PaolaCore
import XCTest

final class BusinessMoneyTests: XCTestCase {
    func testExactItalianAndDotParsingAndFormatting() throws {
        for (input, expected) in [("0", Int64(0)), ("12", 1200), ("12,3", 1230),
                                  ("12.34", 1234), ("  000,09\n", 9),
                                  ("92233720368547758,07", Int64.max)] {
            XCTAssertEqual(try Money.parse(input), expected, input)
        }
        XCTAssertEqual(Money.format(123456789), "1.234.567,89 €")
        XCTAssertEqual(Money.format(-1), "-0,01 €")
        XCTAssertEqual(Money.format(Int64.min), "-92.233.720.368.547.758,08 €")
        XCTAssertEqual(Money.format(0), "0,00 €")
    }

    func testRejectsAmbiguityFractionsAndOverflow() {
        for input in ["", " ", "-1", "+1", "1,234", "1.234,56", "1,23.45", ".5", "1.",
                      "1e3", "NaN", "€12", "1 000", "１２", "92233720368547758.08",
                      "999999999999999999999999999999999999999999"] {
            XCTAssertThrowsError(try Money.parse(input), input)
        }
    }
}

final class BusinessReportsTests: XCTestCase {
    private let clientID = UUID()
    private let date = Date(timeIntervalSince1970: 1_735_689_600)

    private func entry(_ kind: LedgerKind, _ amount: Int64, day: Int = 0,
                       originalID: UUID? = nil, source: String = "") -> LedgerEntry {
        LedgerEntry(clientID: clientID, date: date.addingTimeInterval(Double(day) * 86400),
                    kind: kind, amountCents: amount, sourceKey: source, originalEntryID: originalID)
    }

    func testStatementOpeningClosingAndExclusiveEndWithAllEntryTypes() {
        let beforeCharge = entry(.charge, 10000, day: -2)
        let beforePayment = entry(.payment, 3000, day: -1)
        let charge = entry(.charge, 5000)
        let payment = entry(.payment, 4000)
        let refund = entry(.refund, 1000, originalID: payment.id)
        let credit = entry(.credit, 500, originalID: charge.id)
        let after = entry(.payment, 50000, day: 1)
        let otherClient = LedgerEntry(clientID: UUID(), date: date, kind: .charge, amountCents: 1234)
        let entries = [beforeCharge, beforePayment, charge, payment, refund, credit, after, otherClient]
        let statement = BusinessReports.statement(clientID: clientID, from: date,
            to: date.addingTimeInterval(86400), entries: entries)
        XCTAssertEqual(statement.openingBalance, 7000)
        XCTAssertEqual(statement.closingBalance, 8500)
        XCTAssertEqual(statement.entries.count, 4)
        XCTAssertEqual(statement.chargedCents, 5000)
        XCTAssertEqual(statement.paidCents, 4000)
        XCTAssertEqual(statement.refundedCents, 1000)
        XCTAssertEqual(statement.creditedCents, 500)
        XCTAssertEqual(BusinessReports.balance(clientID: clientID, entries: entries), -41500)
        let global = BusinessReports.statement(clientID: nil, from: date, to: date.addingTimeInterval(86400), entries: entries)
        XCTAssertEqual(global.closingBalance, 9734)
    }

    func testFIFOAdvancesPartialPaymentsRefundsAndCredits() {
        let firstPayment = entry(.payment, 10000, day: -2)
        let firstCharge = entry(.charge, 8000)
        let secondCharge = entry(.charge, 7000, day: 1)
        let laterPayment = entry(.payment, 2000, day: 2)
        var entries = [laterPayment, secondCharge, firstCharge, firstPayment]
        XCTAssertEqual(BusinessReports.allocations(clientID: clientID, entries: entries), [
            PaymentAllocation(paymentID: firstPayment.id, chargeID: firstCharge.id, amountCents: 8000),
            PaymentAllocation(paymentID: firstPayment.id, chargeID: secondCharge.id, amountCents: 2000),
            PaymentAllocation(paymentID: laterPayment.id, chargeID: secondCharge.id, amountCents: 2000)
        ])
        entries.append(entry(.credit, 3000, day: 3, originalID: firstCharge.id))
        entries.append(entry(.refund, 4000, day: 3, originalID: firstPayment.id))
        XCTAssertEqual(BusinessReports.allocations(clientID: clientID, entries: entries), [
            PaymentAllocation(paymentID: firstPayment.id, chargeID: firstCharge.id, amountCents: 5000),
            PaymentAllocation(paymentID: firstPayment.id, chargeID: secondCharge.id, amountCents: 1000),
            PaymentAllocation(paymentID: laterPayment.id, chargeID: secondCharge.id, amountCents: 2000)
        ])
        XCTAssertEqual(BusinessReports.balance(clientID: clientID, entries: entries), 4000)
        XCTAssertEqual(firstPayment.amountCents, 10000)
        XCTAssertEqual(firstCharge.amountCents, 8000)
    }

    func testDuplicateSourcesAndAdjustmentAliasesAreCountedOnlyOnce() {
        let charge = entry(.charge, 6000, source: "charge-key")
        let duplicateCharge = entry(.charge, 6000, source: "CHARGE-KEY")
        let payment = entry(.payment, 10000, source: "payment-key")
        let duplicatePayment = entry(.payment, 10000, source: "PAYMENT-KEY")
        let refund = entry(.refund, 8000, originalID: duplicatePayment.id, source: "refund-key")
        let credit = entry(.credit, 1000, originalID: duplicateCharge.id, source: "credit-key")
        let duplicateCredit = entry(.credit, 1000, originalID: duplicateCharge.id, source: "credit-key")
        let entries = [charge, duplicateCharge, payment, duplicatePayment, refund, credit, duplicateCredit, charge]
        XCTAssertEqual(BusinessReports.balance(clientID: clientID, entries: entries), 3000)
        XCTAssertEqual(BusinessReports.allocations(clientID: clientID, entries: entries).map(\.amountCents), [2000])
        let statement = BusinessReports.statement(clientID: clientID, from: date,
            to: date.addingTimeInterval(1), entries: entries)
        XCTAssertEqual(statement.chargedCents, 6000)
        XCTAssertEqual(statement.paidCents, 10000)
        XCTAssertEqual(statement.refundedCents, 8000)
        XCTAssertEqual(statement.creditedCents, 1000)
    }

    func testRemainingCountsDistinctLogicalUsesAndNeverNegative() {
        let package = LessonPackage(clientID: clientID)
        let sessionID = UUID()
        let first = PackageUse(packageID: package.id, sessionID: sessionID, clientID: clientID, sourceKey: "one")
        let duplicate = PackageUse(packageID: package.id, sessionID: sessionID, clientID: clientID, sourceKey: "different")
        XCTAssertEqual(BusinessReports.remaining(package: package, uses: [first, duplicate]), 9)
        let uses = (0..<12).map { _ in PackageUse(packageID: package.id, sessionID: UUID(), clientID: clientID) }
        XCTAssertEqual(BusinessReports.remaining(package: package, uses: uses), 0)
        XCTAssertEqual(BusinessReports.remaining(package: package, uses: [PackageUse()]), 10)
    }

    func testStatisticsClipAndUnionWorkCountPairOnceAndUseCashDates() {
        let first = TrainingSession(startDate: date.addingTimeInterval(-1800), durationMinutes: 90, status: .completed)
        let overlapping = TrainingSession(startDate: date.addingTimeInterval(1800), durationMinutes: 120, status: .completed)
        let clipped = TrainingSession(startDate: date.addingTimeInterval(9000), durationMinutes: 60, status: .completed)
        let excluded = TrainingSession(startDate: date, durationMinutes: 60, status: .noShow)
        let cancelled = TrainingSession(startDate: date, durationMinutes: 60, status: .cancelled)
        let planned = TrainingSession(startDate: date, durationMinutes: 60, status: .planned)
        let outside = TrainingSession(startDate: date.addingTimeInterval(10800), durationMinutes: 60, status: .completed)
        let payment = entry(.payment, 12000)
        let refund = entry(.refund, 3000, originalID: payment.id)
        let oldPayment = entry(.payment, 20000, day: -1)
        let charge = entry(.charge, 50000)
        let stats = BusinessReports.statistics(from: date, to: date.addingTimeInterval(10800),
            sessions: [first, overlapping, clipped, excluded, cancelled, planned, outside, first],
            entries: [payment, refund, oldPayment, charge])
        XCTAssertEqual(stats.completedSessions, 3)
        XCTAssertEqual(stats.workedMinutes, 180)
        XCTAssertEqual(stats.receivedCents, 12000)
        XCTAssertEqual(stats.refundedCents, 3000)
        XCTAssertEqual(stats.hourlyIncomeCents, 3000)
        XCTAssertEqual(stats.popularHours.values.reduce(0, +), 3)
    }

    func testNoWorkedHoursHasNoHourlyRateAndDoesNotInventRevenue() {
        let payment = entry(.payment, 5000)
        let stats = BusinessReports.statistics(from: date, to: date.addingTimeInterval(86400), sessions: [], entries: [payment])
        XCTAssertEqual(stats.receivedCents, 5000)
        XCTAssertEqual(stats.workedMinutes, 0)
        XCTAssertNil(stats.hourlyIncomeCents)
        let backwards = BusinessReports.statistics(from: date.addingTimeInterval(86400), to: date,
            sessions: [TrainingSession(startDate: date, status: .completed)], entries: [payment])
        XCTAssertEqual(backwards.completedSessions, 0)
        XCTAssertNil(backwards.hourlyIncomeCents)
    }

    func testBalanceCancellationDoesNotOverflowIntermediateIntegerSum() {
        let entries = [entry(.charge, .max), entry(.refund, 1), entry(.payment, .max)]
        XCTAssertEqual(BusinessReports.balance(clientID: clientID, entries: entries), 1)
        XCTAssertEqual(BusinessReports.balance(clientID: clientID, entries: [entry(.charge, .max), entry(.charge, 1)]), .max)
    }
}
