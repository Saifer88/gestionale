import Foundation
@testable import PaolaCore
import XCTest

final class BusinessIntegrityTests: XCTestCase {
    private let clientID = UUID()
    private let date = Date(timeIntervalSince1970: 1_735_689_600)

    private func payment() -> LedgerEntry {
        LedgerEntry(clientID: clientID, date: date, kind: .payment, amountCents: 10000, sourceKey: "payment:test")
    }

    private func package() -> (LessonPackage, LedgerEntry) {
        let package = LessonPackage(clientID: clientID, purchasedOn: date, priceCents: 40000)
        let charge = LedgerEntry(clientID: clientID, date: date, kind: .charge, amountCents: 40000,
                                 sourceKey: BusinessRules.packageSource(package.id))
        return (package, charge)
    }

    func testHealthyDataAndIdenticalSourceReplayHaveNoWarnings() {
        let (package, charge) = package()
        let paid = payment()
        let duplicate = LedgerEntry(clientID: clientID, date: date, kind: .payment,
                                    amountCents: paid.amountCents, sourceKey: paid.sourceKey.uppercased())
        let sessionID = UUID()
        let key = BusinessRules.sessionSource(sessionID: sessionID, clientID: clientID)
        let firstUse = PackageUse(packageID: package.id, sessionID: sessionID, clientID: clientID, sourceKey: key)
        let duplicateUse = PackageUse(packageID: package.id, sessionID: sessionID, clientID: clientID, sourceKey: key)
        let entries = [charge, paid, duplicate, paid]
        XCTAssertTrue(BusinessReports.integrityWarnings(entries: entries, packages: [package], uses: [firstUse, duplicateUse]).isEmpty)
        XCTAssertEqual(BusinessReports.balance(clientID: clientID, entries: entries), 30000)
        XCTAssertEqual(BusinessReports.remaining(package: package, uses: [firstUse, duplicateUse]), 9)
    }

    func testConflictingSourceValuesAreFlaggedDeterministically() {
        let mutations: [(LedgerEntry) -> Void] = [
            { $0.amountCents += 1 }, { $0.kind = .charge }, { $0.clientID = UUID() },
            { $0.originalEntryID = UUID() }, { $0.date = $0.date.addingTimeInterval(1) },
            { $0.method = .bankTransfer }
        ]
        for mutate in mutations {
            let first = payment()
            let second = payment()
            mutate(second)
            let forward = BusinessReports.integrityWarnings(entries: [first, second], packages: [], uses: [])
            let reverse = BusinessReports.integrityWarnings(entries: [second, first], packages: [], uses: [])
            XCTAssertTrue(forward.contains { $0.contains("stessa origine") })
            XCTAssertEqual(forward, reverse)
        }
    }

    func testDuplicateIDsAcrossDifferentRowsAreFlaggedWithoutCrashing() {
        let first = payment()
        let second = payment()
        second.id = first.id
        XCTAssertTrue(BusinessReports.integrityWarnings(entries: [first, second], packages: [], uses: [])
            .contains { $0.contains("stesso identificativo") })
        XCTAssertTrue(BusinessReports.integrityWarnings(entries: [first, first], packages: [], uses: []).isEmpty)
        let (package, charge) = package()
        let duplicate = LessonPackage(id: package.id, clientID: clientID, purchasedOn: date, priceCents: 40000)
        XCTAssertTrue(BusinessReports.integrityWarnings(entries: [charge], packages: [package, duplicate], uses: [])
            .contains { $0.contains("pacchetti distinti") })
        let sessionID = UUID()
        let key = BusinessRules.sessionSource(sessionID: sessionID, clientID: clientID)
        let use = PackageUse(packageID: package.id, sessionID: sessionID, clientID: clientID, sourceKey: key)
        let duplicateUse = PackageUse(id: use.id, packageID: package.id, sessionID: sessionID, clientID: clientID, sourceKey: key)
        XCTAssertTrue(BusinessReports.integrityWarnings(entries: [charge], packages: [package], uses: [use, duplicateUse])
            .contains { $0.contains("utilizzi distinti") })
    }

    func testOverCapacityAndOrphanOrForeignPackageReferences() {
        let (package, charge) = package()
        var uses: [PackageUse] = []
        for _ in 0..<11 {
            let sessionID = UUID()
            uses.append(PackageUse(packageID: package.id, sessionID: sessionID, clientID: clientID,
                sourceKey: BusinessRules.sessionSource(sessionID: sessionID, clientID: clientID)))
        }
        XCTAssertTrue(BusinessReports.integrityWarnings(entries: [charge], packages: [package], uses: uses)
            .contains { $0.contains("supera il numero") })
        XCTAssertTrue(BusinessReports.integrityWarnings(entries: [], packages: [], uses: [uses[0]])
            .contains { $0.contains("pacchetto mancante") })
        uses[0].clientID = UUID()
        XCTAssertTrue(BusinessReports.integrityWarnings(entries: [charge], packages: [package], uses: [uses[0]])
            .contains { $0.contains("cliente diverso") })
        XCTAssertTrue(BusinessReports.integrityWarnings(entries: [], packages: [package], uses: [])
            .contains { $0.contains("addebito di acquisto") })
    }

    func testSameLessonCannotConsumeDifferentPackagesWithoutWarning() {
        let (first, firstCharge) = package()
        let (second, secondCharge) = package()
        let sessionID = UUID()
        let key = BusinessRules.sessionSource(sessionID: sessionID, clientID: clientID)
        let firstUse = PackageUse(packageID: first.id, sessionID: sessionID, clientID: clientID, sourceKey: key)
        let secondUse = PackageUse(packageID: second.id, sessionID: sessionID, clientID: clientID, sourceKey: key)
        let warnings = BusinessReports.integrityWarnings(entries: [firstCharge, secondCharge],
            packages: [first, second], uses: [firstUse, secondUse])
        XCTAssertTrue(warnings.contains { $0.contains("pacchetti differenti") })
    }

    func testOrphanAdjustmentWrongKindAndExcessRefundAreFlagged() {
        let paid = payment()
        let refund = LedgerEntry(clientID: clientID, date: date, kind: .refund, amountCents: 10001,
                                 sourceKey: "refund:test", originalEntryID: paid.id)
        XCTAssertTrue(BusinessReports.integrityWarnings(entries: [refund], packages: [], uses: [])
            .contains { $0.contains("originale mancante") })
        XCTAssertTrue(BusinessReports.integrityWarnings(entries: [paid, refund], packages: [], uses: [])
            .contains { $0.contains("superano") })
        refund.kind = .credit
        XCTAssertTrue(BusinessReports.integrityWarnings(entries: [paid, refund], packages: [], uses: [])
            .contains { $0.contains("tipo o al cliente") })
    }

    func testUnknownKindNeverBecomesChargeAndProducesVisibleWarning() {
        let unknown = payment()
        unknown.kindRaw = "future-unsupported-kind"
        XCTAssertEqual(unknown.kind, .unknown)
        XCTAssertEqual(unknown.kind.title, "Tipo sconosciuto")
        XCTAssertEqual(BusinessReports.balance(clientID: clientID, entries: [unknown]), 0)
        XCTAssertTrue(BusinessReports.allocations(clientID: clientID, entries: [unknown]).isEmpty)
        XCTAssertTrue(BusinessReports.integrityWarnings(entries: [unknown], packages: [], uses: [])
            .contains { $0.contains("tipo sconosciuto") })
        var archive = BusinessArchive()
        archive.ledgerEntries = [BusinessArchive.LedgerRecord(unknown)]
        XCTAssertThrowsError(try archive.validate(clientIDs: [clientID]))
        unknown.kind = .unknown
        archive.ledgerEntries = [BusinessArchive.LedgerRecord(unknown)]
        XCTAssertThrowsError(try archive.validate(clientIDs: [clientID]))
    }
}
