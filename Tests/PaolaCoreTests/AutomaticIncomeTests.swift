import Foundation
@testable import PaolaCore
import SwiftData
import XCTest

@MainActor
final class AutomaticIncomeTests: XCTestCase {
    func testPackageRegistersExactChargeAndReceiptOnPurchaseWithUnspecifiedMethod() async throws {
        let store = try BusinessTestStore.make()
        let context = store.mainContext
        let client = try BusinessTestStore.addClient(context)
        let legacyID = try BusinessTestStore.seedLegacyPayment(
            BusinessTestStore.payment(client, amount: 12345), in: context)
        let legacy = try XCTUnwrap(context.fetch(FetchDescriptor<LedgerEntry>()).first { $0.id == legacyID })
        let original = BusinessArchive.LedgerRecord(legacy)
        let repository = BusinessRepository(context: context)
        let draft = BusinessTestStore.package(client, price: 12345)
        let id = try repository.savePackage(draft)
        let entries = try context.fetch(FetchDescriptor<LedgerEntry>())
        XCTAssertEqual(entries.count, 3)
        let charge = try XCTUnwrap(entries.first { $0.sourceKey == BusinessRules.packageSource(id) })
        let income = try XCTUnwrap(entries.first { $0.sourceKey == BusinessRules.packageIncomeSource(id) })
        XCTAssertEqual(charge.kind, .charge)
        XCTAssertEqual(income.kind, .payment)
        XCTAssertEqual(income.method, .cash) // metodo predefinito ora selezionabile (contanti)
        XCTAssertEqual(income.date, draft.purchasedOn)
        XCTAssertEqual(charge.date, draft.purchasedOn)
        XCTAssertEqual(income.amountCents, draft.priceCents)
        XCTAssertEqual(income.amountCents, charge.amountCents)
        XCTAssertEqual(income.clientID, client.id)
        XCTAssertEqual(BusinessArchive.LedgerRecord(legacy), original)
        XCTAssertEqual(BusinessReports.balance(clientID: client.id, entries: entries), -12345)
        XCTAssertFalse(context.hasChanges)
    }

    func testPackagePersistsCustomCapacityAndUsesItInAccountingDescription() async throws {
        let store = try BusinessTestStore.make()
        let context = store.mainContext
        let client = try BusinessTestStore.addClient(context)
        var draft = BusinessTestStore.package(client)
        draft.capacity = 5

        let id = try BusinessRepository(context: context).savePackage(draft)

        let package = try XCTUnwrap(context.fetch(FetchDescriptor<LessonPackage>()).first { $0.id == id })
        XCTAssertEqual(package.capacity, 5)
        let entries = try context.fetch(FetchDescriptor<LedgerEntry>())
        XCTAssertEqual(entries.filter { $0.sourceKey.contains(id.uuidString.lowercased()) }.map(\.notes),
                       ["Pacchetto 5 lezioni", "Pacchetto 5 lezioni"])
    }

    func testPackageRejectsCapacityOutsideSupportedRangeWithoutWriting() async throws {
        let store = try BusinessTestStore.make()
        let context = store.mainContext
        let client = try BusinessTestStore.addClient(context)
        let repository = BusinessRepository(context: context)

        for capacity in [0, 1001] {
            var draft = BusinessTestStore.package(client)
            draft.capacity = capacity
            XCTAssertThrowsError(try repository.savePackage(draft))
        }

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<LessonPackage>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<LedgerEntry>()), 0)
    }

    func testReceiptUsesCompletionEventDateRatherThanScheduledYearAndIsIdempotent() async throws {
        let store = try BusinessTestStore.make()
        let context = store.mainContext
        let client = try BusinessTestStore.addClient(context)
        let repository = BusinessRepository(context: context)
        var draft = BusinessTestStore.session(client, price: 5678)
        draft.startDate = Date(timeIntervalSince1970: 1_735_646_400) // 31 December 2024 at noon UTC.
        let completedOn = BusinessTestStore.date.addingTimeInterval(2 * 86400)
        let id = try repository.saveSession(draft)
        for status in [SessionStatus.cancelled, .noShow, .planned] {
            try repository.setSessionStatus(id, to: status)
            XCTAssertTrue(try context.fetch(FetchDescriptor<LedgerEntry>()).isEmpty)
        }
        try repository.setSessionStatus(id, to: .completed, completionDate: completedOn)
        let snapshot = try BusinessArchive.capture(context: context)
        try repository.setSessionStatus(id, to: .completed, completionDate: completedOn.addingTimeInterval(86400))
        XCTAssertEqual(try BusinessArchive.capture(context: context), snapshot)
        let entries = try context.fetch(FetchDescriptor<LedgerEntry>())
        let income = try XCTUnwrap(entries.first { $0.kind == .payment })
        let charge = try XCTUnwrap(entries.first { $0.kind == .charge })
        XCTAssertEqual(income.date, completedOn)
        XCTAssertEqual(charge.date, draft.startDate)
        XCTAssertEqual(income.sourceKey, BusinessRules.sessionIncomeSource(sessionID: id, clientID: client.id))
        let sessions = try context.fetch(FetchDescriptor<TrainingSession>())
        let previous = BusinessReports.statistics(from: draft.startDate, to: BusinessTestStore.date,
            sessions: sessions, entries: entries)
        let current = BusinessReports.statistics(from: BusinessTestStore.date, to: completedOn.addingTimeInterval(1),
            sessions: sessions, entries: entries)
        XCTAssertEqual(previous.receivedCents, 0)
        XCTAssertEqual(previous.completedSessions, 1)
        XCTAssertEqual(previous.workedMinutes, 60)
        XCTAssertEqual(current.receivedCents, 5678)
        XCTAssertEqual(current.completedSessions, 0)
        let statement = BusinessReports.statement(clientID: client.id, from: BusinessTestStore.date,
            to: completedOn.addingTimeInterval(1), entries: entries)
        XCTAssertEqual(statement.openingBalance, 5678)
        XCTAssertEqual(statement.chargedCents, 0)
        XCTAssertEqual(statement.paidCents, 5678)
        XCTAssertEqual(statement.closingBalance, 0)
    }

    func testCompletionDateCanPrecedeChargeButInvalidDateIsAtomic() async throws {
        let store = try BusinessTestStore.make()
        let context = store.mainContext
        let client = try BusinessTestStore.addClient(context)
        let repository = BusinessRepository(context: context)
        let draft = BusinessTestStore.session(client)
        let id = try repository.saveSession(draft)
        let original = try BusinessArchive.capture(context: context)
        for invalid in [Double.infinity, -Double.infinity, Double.nan] {
            XCTAssertThrowsError(try repository.setSessionStatus(id, to: .completed,
                completionDate: Date(timeIntervalSinceReferenceDate: invalid)))
            XCTAssertEqual(try BusinessArchive.capture(context: context), original)
            XCTAssertFalse(context.hasChanges)
        }
        try repository.setSessionStatus(id, to: .completed, completionDate: BusinessTestStore.date)
        let archive = try BusinessArchive.capture(context: context)
        try archive.validate(clientIDs: [client.id])
        XCTAssertEqual(archive.ledgerEntries.first { $0.kindRaw == "payment" }?.date, BusinessTestStore.date)
    }

    func testZeroPricedPackageAndCompletedSessionHaveChargesWithoutZeroPayments() async throws {
        let store = try BusinessTestStore.make()
        let context = store.mainContext
        let client = try BusinessTestStore.addClient(context)
        let repository = BusinessRepository(context: context)
        try repository.savePackage(BusinessTestStore.package(client, price: 0))
        let id = try repository.saveSession(BusinessTestStore.session(client, price: 0))
        try repository.setSessionStatus(id, to: .completed)
        let entries = try context.fetch(FetchDescriptor<LedgerEntry>())
        XCTAssertEqual(entries.count, 2)
        XCTAssertTrue(entries.allSatisfy { $0.kind == .charge && $0.amountCents == 0 })
        try BusinessArchive.capture(context: context).validate(clientIDs: [client.id])
    }

    func testPackageLessonConsumesOnceAndNeverRegistersAnotherReceipt() async throws {
        let store = try BusinessTestStore.make()
        let context = store.mainContext
        let client = try BusinessTestStore.addClient(context)
        let repository = BusinessRepository(context: context)
        let packageID = try repository.savePackage(BusinessTestStore.package(client))
        let before = try BusinessArchive.capture(context: context).ledgerEntries
        let id = try repository.saveSession(BusinessTestStore.session(client, packageID: packageID))
        try repository.setSessionStatus(id, to: .completed)
        try repository.setSessionStatus(id, to: .completed)
        XCTAssertEqual(try BusinessArchive.capture(context: context).ledgerEntries, before)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PackageUse>()), 1)
    }

    func testManualPaymentsDisabledWithoutCallingWriterOrChangingLegacyRows() async throws {
        let store = try BusinessTestStore.make()
        let context = store.mainContext
        let client = try BusinessTestStore.addClient(context)
        try BusinessTestStore.seedLegacyPayment(BusinessTestStore.payment(client, amount: 4321), in: context)
        let before = try BusinessArchive.capture(context: context)
        let repository = BusinessRepository(context: context) { _ in XCTFail("Must not attempt a save") }
        for amount: Int64 in [0, 1, -1, .max] {
            XCTAssertThrowsError(try repository.recordPayment(BusinessTestStore.payment(client, amount: amount))) {
                guard case BusinessError.manualPaymentsDisabled = $0 else { return XCTFail("\($0)") }
                XCTAssertTrue($0.localizedDescription.contains("automaticamente"))
            }
        }
        XCTAssertEqual(try BusinessArchive.capture(context: context), before)
        XCTAssertFalse(context.hasChanges)
    }

    func testGroupCanBeEditedBeforeCompletionAndPreservesIndividualIncome() async throws {
        let store = try BusinessTestStore.make()
        let context = store.mainContext
        let first = try BusinessTestStore.addClient(context)
        let second = try BusinessTestStore.addClient(context, name: "Elena")
        var draft = BusinessTestStore.session(first)
        draft.participants.append(ParticipantDraft(clientID: second.id, priceCents: 3000))
        let repository = BusinessRepository(context: context)
        draft.id = try repository.saveSession(draft)
        let before = try BusinessArchive.capture(context: context)
        for edited in [draft, {
            var edit = draft
            edit.participants.removeLast()
            edit.startDate = edit.startDate.addingTimeInterval(7200)
            return edit
        }()] {
            XCTAssertNoThrow(try repository.saveSession(edited, allowOverlap: true))
        }
        try repository.saveSession(draft, allowOverlap: true)
        let id = try XCTUnwrap(draft.id)
        for status in [SessionStatus.cancelled, .noShow, .planned, .completed] {
            try repository.setSessionStatus(id, to: status, completionDate: BusinessTestStore.date)
        }
        let after = try BusinessArchive.capture(context: context)
        XCTAssertEqual(after.participants.map(\.clientID).sorted { $0.uuidString < $1.uuidString },
                       before.participants.map(\.clientID).sorted { $0.uuidString < $1.uuidString })
        XCTAssertEqual(after.sessions.first?.startDate, before.sessions.first?.startDate)
        XCTAssertEqual(after.preferences.count, 2)
        XCTAssertEqual(after.ledgerEntries.filter { $0.kindRaw == "payment" }.map(\.amountCents).sorted(), [3000, 5000])
        try after.validate(clientIDs: [first.id, second.id])
    }

    func testAutomaticReceiptSourceValidationAllowsLegacyMissingReceiptAndRejectsConflicts() async throws {
        let store = try BusinessTestStore.make()
        let context = store.mainContext
        let client = try BusinessTestStore.addClient(context)
        let repository = BusinessRepository(context: context)
        try repository.savePackage(BusinessTestStore.package(client))
        let id = try repository.saveSession(BusinessTestStore.session(client))
        try repository.setSessionStatus(id, to: .completed)
        let original = try BusinessArchive.capture(context: context)
        let incomeIndex = try XCTUnwrap(original.ledgerEntries.firstIndex { $0.sourceKey.hasPrefix("income:package:") })
        let mutations: [(inout BusinessArchive) -> Void] = [
            { $0.ledgerEntries[incomeIndex].amountCents += 1 },
            { $0.ledgerEntries[incomeIndex].date = $0.ledgerEntries[incomeIndex].date.addingTimeInterval(1) },
            { $0.ledgerEntries[incomeIndex].methodRaw = "metodo-inesistente" },
            { $0.ledgerEntries[incomeIndex].sourceKey = "income:invalid" },
            { $0.ledgerEntries[incomeIndex].sourceKey = "income:package:\(UUID().uuidString)" },
            { $0.sessions[0].statusRaw = SessionStatus.planned.rawValue }
        ]
        for mutate in mutations {
            var invalid = original
            mutate(&invalid)
            XCTAssertThrowsError(try invalid.validate(clientIDs: [client.id]))
        }
        var old = original
        old.ledgerEntries.removeAll { $0.kindRaw == "payment" }
        try old.validate(clientIDs: [client.id])
        var duplicate = original
        var copy = duplicate.ledgerEntries[incomeIndex]
        copy.id = UUID()
        duplicate.ledgerEntries.append(copy)
        try duplicate.validate(clientIDs: [client.id])
        let entries = duplicate.ledgerEntries.map { $0.model() }
        XCTAssertTrue(BusinessReports.integrityWarnings(entries: entries,
            packages: try context.fetch(FetchDescriptor<LessonPackage>()), uses: []).isEmpty)
        XCTAssertEqual(BusinessReports.statistics(from: .distantPast, to: .distantFuture,
            sessions: [], entries: entries).receivedCents, 45000)
        duplicate.ledgerEntries[duplicate.ledgerEntries.count - 1].amountCents += 1
        XCTAssertThrowsError(try duplicate.validate(clientIDs: [client.id]))
        XCTAssertFalse(BusinessReports.integrityWarnings(entries: duplicate.ledgerEntries.map { $0.model() },
            packages: try context.fetch(FetchDescriptor<LessonPackage>()), uses: []).isEmpty)
    }
}
