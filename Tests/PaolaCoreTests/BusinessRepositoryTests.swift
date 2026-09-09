import Foundation
@testable import PaolaCore
import SwiftData
import XCTest

@MainActor
final class BusinessRepositoryTests: XCTestCase {
    func testSingleSessionChargeIsIdempotentAndCompletedSessionFrozen() async throws {
        let store = try BusinessTestStore.make()
        let context = store.mainContext
        let client = try BusinessTestStore.addClient(context)
        let repo = BusinessRepository(context: context)
        let draft = BusinessTestStore.session(client)
        let id = try repo.saveSession(draft)
        let observed = try XCTUnwrap(context.fetch(FetchDescriptor<TrainingSession>()).first)
        XCTAssertEqual(observed.status, .planned)
        XCTAssertTrue(try context.fetch(FetchDescriptor<LedgerEntry>()).isEmpty)
        try repo.setSessionStatus(id, to: .completed)
        try repo.setSessionStatus(id, to: .completed)
        XCTAssertEqual(observed.status, .completed)
        let entries = try context.fetch(FetchDescriptor<LedgerEntry>())
        XCTAssertEqual(entries.count, 2)
        let charge = try XCTUnwrap(entries.first { $0.kind == .charge })
        XCTAssertEqual(charge.amountCents, 5000)
        XCTAssertEqual(charge.date, draft.startDate)
        XCTAssertEqual(charge.sourceKey, "\(id.uuidString.lowercased()):\(client.id.uuidString.lowercased())")
        for status in [SessionStatus.cancelled, .planned, .noShow] {
            XCTAssertThrowsError(try repo.setSessionStatus(id, to: status)) {
                guard case BusinessError.completedSessionLocked = $0 else { return XCTFail("\($0)") }
            }
        }
        var edit = SessionDraft(observed, participants: try context.fetch(FetchDescriptor<SessionParticipant>()))
        edit.startDate = edit.startDate.addingTimeInterval(3600)
        XCTAssertThrowsError(try repo.saveSession(edit))
        XCTAssertEqual(observed.startDate, draft.startDate)
        XCTAssertFalse(context.hasChanges)
    }

    func testPairMixedPackageAndCashCreatesOnlyCorrectCharge() async throws {
        let store = try BusinessTestStore.make()
        let context = store.mainContext
        let first = try BusinessTestStore.addClient(context)
        let second = try BusinessTestStore.addClient(context, name: "Elena")
        let repo = BusinessRepository(context: context)
        let packageID = try repo.savePackage(BusinessTestStore.package(first))
        var session = BusinessTestStore.session(first, packageID: packageID)
        session.participants.append(ParticipantDraft(clientID: second.id, priceCents: 3000))
        let id = try BusinessTestStore.seedLegacySession(session, in: context)
        try repo.setSessionStatus(id, to: .completed)
        try repo.setSessionStatus(id, to: .completed)
        let entries = try context.fetch(FetchDescriptor<LedgerEntry>())
        XCTAssertEqual(entries.count, 4)
        XCTAssertEqual(BusinessReports.balance(clientID: first.id, entries: entries), 0)
        XCTAssertEqual(BusinessReports.balance(clientID: second.id, entries: entries), 0)
        let uses = try context.fetch(FetchDescriptor<PackageUse>())
        XCTAssertEqual(uses.count, 1)
        let package = try XCTUnwrap(context.fetch(FetchDescriptor<LessonPackage>()).first)
        XCTAssertEqual(BusinessReports.remaining(package: package, uses: uses), 9)
    }

    func testPairWithTwoPackagesConsumesEachOnceAndWorksOneHour() async throws {
        let store = try BusinessTestStore.make()
        let context = store.mainContext
        let first = try BusinessTestStore.addClient(context)
        let second = try BusinessTestStore.addClient(context, name: "Elena")
        let repo = BusinessRepository(context: context)
        let firstPackageID = try repo.savePackage(BusinessTestStore.package(first))
        let secondPackageID = try repo.savePackage(BusinessTestStore.package(second))
        var draft = BusinessTestStore.session(first, packageID: firstPackageID)
        draft.participants.append(ParticipantDraft(clientID: second.id, priceCents: 5000, packageID: secondPackageID))
        let id = try BusinessTestStore.seedLegacySession(draft, in: context)
        try repo.setSessionStatus(id, to: .completed)
        try repo.setSessionStatus(id, to: .completed)
        let uses = try context.fetch(FetchDescriptor<PackageUse>())
        XCTAssertEqual(uses.count, 2)
        for package in try context.fetch(FetchDescriptor<LessonPackage>()) {
            XCTAssertEqual(BusinessReports.remaining(package: package, uses: uses), 9)
        }
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<LedgerEntry>()), 4)
        let stats = BusinessReports.statistics(from: draft.startDate,
            to: draft.startDate.addingTimeInterval(3600),
            sessions: try context.fetch(FetchDescriptor<TrainingSession>()),
            entries: try context.fetch(FetchDescriptor<LedgerEntry>()))
        XCTAssertEqual(stats.completedSessions, 1)
        XCTAssertEqual(stats.workedMinutes, 60)
        XCTAssertEqual(stats.receivedCents, 0)
    }

    func testCustomCapacityExhaustionRejectsNextCompletionAtomicallyForWholeGroup() async throws {
        let store = try BusinessTestStore.make()
        let context = store.mainContext
        let first = try BusinessTestStore.addClient(context)
        let second = try BusinessTestStore.addClient(context, name: "Elena")
        let repo = BusinessRepository(context: context)
        var packageDraft = BusinessTestStore.package(first)
        packageDraft.capacity = 5
        let packageID = try repo.savePackage(packageDraft)
        var excess = BusinessTestStore.session(second, day: 6, price: 7000)
        excess.participants.append(ParticipantDraft(clientID: first.id, priceCents: 5000, packageID: packageID))
        let excessID = try BusinessTestStore.seedLegacySession(excess, in: context)
        for day in 1...5 {
            let id = try repo.saveSession(BusinessTestStore.session(first, day: day, packageID: packageID))
            try repo.setSessionStatus(id, to: .completed)
            try repo.setSessionStatus(id, to: .completed)
        }
        XCTAssertThrowsError(try repo.setSessionStatus(excessID, to: .completed)) {
            guard case BusinessError.packageExhausted = $0 else { return XCTFail("\($0)") }
        }
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PackageUse>()), 5)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<LedgerEntry>()), 2)
        let excessStored = try XCTUnwrap(context.fetch(FetchDescriptor<TrainingSession>()).first { $0.id == excessID })
        XCTAssertEqual(excessStored.status, .planned)
        XCTAssertFalse(context.hasChanges)
        let package = try XCTUnwrap(context.fetch(FetchDescriptor<LessonPackage>()).first)
        XCTAssertEqual(BusinessReports.remaining(package: package, uses: try context.fetch(FetchDescriptor<PackageUse>())), 0)
    }

    func testCancelledAndNoShowHaveNoFinancialEffectAndCanBeReplanned() async throws {
        let store = try BusinessTestStore.make()
        let context = store.mainContext
        let client = try BusinessTestStore.addClient(context)
        let repo = BusinessRepository(context: context)
        let draft = BusinessTestStore.session(client)
        let cancelled = try repo.saveSession(draft)
        try repo.setSessionStatus(cancelled, to: .cancelled)
        let other = try repo.saveSession(draft)
        try repo.setSessionStatus(other, to: .noShow)
        XCTAssertTrue(try context.fetch(FetchDescriptor<LedgerEntry>()).isEmpty)
        try repo.setSessionStatus(cancelled, to: .planned)
        XCTAssertThrowsError(try repo.setSessionStatus(other, to: .planned))
        XCTAssertThrowsError(try repo.setSessionStatus(other, to: .completed))
        XCTAssertFalse(context.hasChanges)
    }

    func testOverlapAdjacentAndExplicitOverrideIncludingBlocks() async throws {
        let store = try BusinessTestStore.make()
        let context = store.mainContext
        let client = try BusinessTestStore.addClient(context)
        let repo = BusinessRepository(context: context)
        var first = BusinessTestStore.session(client)
        _ = try repo.saveSession(first)
        XCTAssertThrowsError(try repo.saveSession(first)) {
            guard case BusinessError.overlap = $0 else { return XCTFail("\($0)") }
        }
        _ = try repo.saveSession(first, allowOverlap: true)
        first.startDate = first.startDate.addingTimeInterval(3600)
        let adjacentID = try repo.saveSession(first)
        let adjacent = try XCTUnwrap(context.fetch(FetchDescriptor<TrainingSession>()).first { $0.id == adjacentID })
        _ = try repo.saveSession(SessionDraft(adjacent, participants: try context.fetch(FetchDescriptor<SessionParticipant>())))
        var block = BlockDraft()
        block.title = "Pausa"; block.startDate = first.startDate
        block.endDate = first.startDate.addingTimeInterval(3600)
        XCTAssertThrowsError(try repo.saveBlock(block))
        let blockID = try repo.saveBlock(block, allowOverlap: true)
        try repo.setSessionStatus(adjacentID, to: .cancelled)
        XCTAssertThrowsError(try repo.saveSession(first))
        try repo.deleteBlock(blockID)
        XCTAssertTrue(try context.fetch(FetchDescriptor<Unavailability>()).isEmpty)
        _ = try repo.saveSession(first)
    }

    func testParticipantValidationOwnershipExpiryAndArchivedClients() async throws {
        let store = try BusinessTestStore.make()
        let context = store.mainContext
        let first = try BusinessTestStore.addClient(context)
        let second = try BusinessTestStore.addClient(context, name: "Elena")
        let archived = try BusinessTestStore.addClient(context, name: "Maria", archived: true)
        let repo = BusinessRepository(context: context)
        var draft = BusinessTestStore.session(first)
        let valid = draft.participants
        for participants in [
            [], valid + valid,
            valid + [ParticipantDraft(clientID: second.id, priceCents: 1), ParticipantDraft(clientID: archived.id, priceCents: 1)],
            [ParticipantDraft(clientID: UUID(), priceCents: 1)],
            [ParticipantDraft(clientID: archived.id, priceCents: 1)],
            [ParticipantDraft(clientID: first.id, priceCents: -1)]
        ] {
            draft.participants = participants
            XCTAssertThrowsError(try repo.saveSession(draft))
        }
        var package = BusinessTestStore.package(first)
        package.expiresOn = BusinessTestStore.date
        let packageID = try repo.savePackage(package)
        draft.participants = [ParticipantDraft(clientID: second.id, priceCents: 1, packageID: packageID)]
        XCTAssertThrowsError(try repo.saveSession(draft))
        draft.participants = [ParticipantDraft(clientID: first.id, priceCents: 1, packageID: packageID)]
        XCTAssertThrowsError(try repo.saveSession(draft))
        draft.startDate = BusinessTestStore.date.addingTimeInterval(3600)
        _ = try repo.saveSession(draft)
        XCTAssertFalse(context.hasChanges)
    }

    func testHistoricalPriceAndServiceNameSurviveCatalogEdit() async throws {
        let store = try BusinessTestStore.make()
        let context = store.mainContext
        let client = try BusinessTestStore.addClient(context)
        let repo = BusinessRepository(context: context)
        var service = ServiceDraft()
        service.name = "Individuale"; service.priceCents = 5000
        let serviceID = try repo.saveService(service)
        var draft = BusinessTestStore.session(client)
        draft.serviceID = serviceID; draft.serviceName = ""
        let sessionID = try repo.saveSession(draft)
        service.id = serviceID; service.priceCents = 9000; service.name = "Nuovo nome"; service.isActive = false
        try repo.saveService(service)
        try repo.setSessionStatus(sessionID, to: .completed)
        let session = try XCTUnwrap(context.fetch(FetchDescriptor<TrainingSession>()).first)
        XCTAssertEqual(session.serviceName, "Individuale")
        XCTAssertEqual(try context.fetch(FetchDescriptor<LedgerEntry>()).first?.amountCents, 5000)
        draft.startDate = draft.startDate.addingTimeInterval(86400)
        XCTAssertThrowsError(try repo.saveSession(draft))
    }

    func testInvalidDatesDurationsServicesAndMonetaryOverflowLeaveStoreClean() async throws {
        let store = try BusinessTestStore.make()
        let context = store.mainContext
        let client = try BusinessTestStore.addClient(context)
        let repo = BusinessRepository(context: context)
        for duration in [0, -1, Int.max] {
            var draft = BusinessTestStore.session(client); draft.durationMinutes = duration
            XCTAssertThrowsError(try repo.saveSession(draft))
        }
        var invalidDate = BusinessTestStore.session(client)
        invalidDate.startDate = Date(timeIntervalSinceReferenceDate: .infinity)
        XCTAssertThrowsError(try repo.saveSession(invalidDate))
        var invalidService = BusinessTestStore.session(client)
        invalidService.serviceID = UUID()
        XCTAssertThrowsError(try repo.saveSession(invalidService))
        XCTAssertThrowsError(try repo.saveService(ServiceDraft()))
        try BusinessTestStore.seedLegacyPayment(BusinessTestStore.payment(client, amount: .max), in: context)
        XCTAssertThrowsError(try repo.savePackage(BusinessTestStore.package(client, price: 1))) {
            guard case BusinessError.arithmeticOverflow = $0 else { return XCTFail("\($0)") }
        }
        XCTAssertThrowsError(try repo.recordPayment(BusinessTestStore.payment(client, amount: 0)))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<LedgerEntry>()), 1)
        XCTAssertFalse(context.hasChanges)
    }

    func testRefundAndCreditLimitsPreserveImmutableOriginals() async throws {
        let store = try BusinessTestStore.make()
        let context = store.mainContext
        let client = try BusinessTestStore.addClient(context)
        let repo = BusinessRepository(context: context)
        let paymentID = try BusinessTestStore.seedLegacyPayment(BusinessTestStore.payment(client, amount: 10000), in: context)
        try repo.recordRefund(paymentID: paymentID, amountCents: 3000, date: BusinessTestStore.date, notes: "Parziale")
        try repo.recordRefund(paymentID: paymentID, amountCents: 7000, date: BusinessTestStore.date, notes: "Saldo")
        XCTAssertThrowsError(try repo.recordRefund(paymentID: paymentID, amountCents: 1, date: BusinessTestStore.date, notes: ""))
        let packageID = try repo.savePackage(BusinessTestStore.package(client, price: 10000))
        let charge = try XCTUnwrap(context.fetch(FetchDescriptor<LedgerEntry>()).first { $0.sourceKey == packageID.uuidString.lowercased() })
        try repo.recordCredit(chargeID: charge.id, amountCents: 2500, date: BusinessTestStore.date, notes: "Sconto")
        XCTAssertThrowsError(try repo.recordCredit(chargeID: charge.id, amountCents: 7501, date: BusinessTestStore.date, notes: ""))
        XCTAssertThrowsError(try repo.recordCredit(chargeID: paymentID, amountCents: 1, date: BusinessTestStore.date, notes: ""))
        XCTAssertThrowsError(try repo.recordRefund(paymentID: paymentID, amountCents: 1,
            date: BusinessTestStore.date.addingTimeInterval(-1), notes: ""))
        XCTAssertEqual(charge.amountCents, 10000)
        let entries = try context.fetch(FetchDescriptor<LedgerEntry>())
        XCTAssertEqual(BusinessReports.balance(clientID: client.id, entries: entries), -2500)
        XCTAssertEqual(entries.first { $0.id == paymentID }?.amountCents, 10000)
        XCTAssertFalse(context.hasChanges)
    }

    func testFailedSaveDoesNotMutateObservedObjectsAndRetryIsSafe() async throws {
        let store = try BusinessTestStore.make()
        let context = store.mainContext
        let client = try BusinessTestStore.addClient(context)
        let normal = BusinessRepository(context: context)
        let id = try normal.saveSession(BusinessTestStore.session(client))
        let observed = try XCTUnwrap(context.fetch(FetchDescriptor<TrainingSession>()).first)
        let originalUpdatedAt = observed.updatedAt
        let failure = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)
        var fail = true
        let repo = BusinessRepository(context: context) { writer in
            XCTAssertFalse(writer === context)
            XCTAssertFalse(writer.autosaveEnabled)
            writer.processPendingChanges()
            if fail { throw failure }
            try writer.save()
        }
        for _ in 0..<2 {
            XCTAssertThrowsError(try repo.setSessionStatus(id, to: .completed)) { XCTAssertEqual($0 as NSError, failure) }
            XCTAssertThrowsError(try repo.savePackage(BusinessTestStore.package(client))) { XCTAssertEqual($0 as NSError, failure) }
            XCTAssertEqual(observed.status, .planned)
            XCTAssertEqual(observed.updatedAt, originalUpdatedAt)
            XCTAssertTrue(try context.fetch(FetchDescriptor<LedgerEntry>()).isEmpty)
            XCTAssertTrue(try context.fetch(FetchDescriptor<LessonPackage>()).isEmpty)
            XCTAssertFalse(context.hasChanges)
        }
        fail = false
        try repo.setSessionStatus(id, to: .completed)
        XCTAssertEqual(observed.status, .completed)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<LedgerEntry>()), 2)
        XCTAssertFalse(context.hasChanges)
    }

    func testFailedServiceEditAndBlockDeletePreserveObservedValues() async throws {
        let store = try BusinessTestStore.make()
        let context = store.mainContext
        let normal = BusinessRepository(context: context)
        var serviceDraft = ServiceDraft()
        serviceDraft.name = "Originale"; serviceDraft.priceCents = 1000
        serviceDraft.id = try normal.saveService(serviceDraft)
        let service = try XCTUnwrap(context.fetch(FetchDescriptor<TrainingService>()).first)
        var blockDraft = BlockDraft()
        blockDraft.title = "Ferie"
        let blockID = try normal.saveBlock(blockDraft)
        let block = try XCTUnwrap(context.fetch(FetchDescriptor<Unavailability>()).first)
        let failure = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError)
        let failing = BusinessRepository(context: context) { writer in
            writer.processPendingChanges()
            throw failure
        }
        serviceDraft.name = "Modifica"; serviceDraft.priceCents = 9000
        XCTAssertThrowsError(try failing.saveService(serviceDraft)) { XCTAssertEqual($0 as NSError, failure) }
        XCTAssertThrowsError(try failing.deleteBlock(blockID)) { XCTAssertEqual($0 as NSError, failure) }
        XCTAssertEqual(service.name, "Originale")
        XCTAssertEqual(service.priceCents, 1000)
        XCTAssertEqual(block.title, "Ferie")
        XCTAssertFalse(block.isDeleted)
        XCTAssertFalse(context.hasChanges)
    }
}
