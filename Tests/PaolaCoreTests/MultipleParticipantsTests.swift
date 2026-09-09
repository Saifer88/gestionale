import Foundation
@testable import PaolaCore
import SwiftData
import XCTest

@MainActor
final class MultipleParticipantsTests: XCTestCase {
    func testThreeParticipantsCanBeEditedCompletedAndRestoredWithSeparatePricesAndPackage() async throws {
        let store = try StoreFactory.makeContainer(inMemory: true)
        let context = store.mainContext
        let clients = try ["Anna", "Bruno", "Carlo"].map { try BusinessTestStore.addClient(context, name: $0) }
        let repository = BusinessRepository(context: context)
        let packageID = try repository.savePackage(BusinessTestStore.package(clients[1]))
        var draft = BusinessTestStore.session(clients[0])
        draft.participants = [
            ParticipantDraft(clientID: clients[0].id, priceCents: 5000),
            ParticipantDraft(clientID: clients[1].id, priceCents: 4000, packageID: packageID),
            ParticipantDraft(clientID: clients[2].id, priceCents: 3500)
        ]
        draft.id = try repository.saveSession(draft)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SessionParticipant>()), 3)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ClientAppointmentPreference>()), 3)
        draft.participants[2].priceCents = 3000
        try repository.saveSession(draft)
        let sessionID = try XCTUnwrap(draft.id)
        try repository.setSessionStatus(sessionID, to: .completed)
        let completed = try BusinessArchive.capture(context: context)
        try repository.setSessionStatus(sessionID, to: .completed)
        XCTAssertEqual(completed, try BusinessArchive.capture(context: context))
        XCTAssertEqual(completed.packageUses.count, 1)
        XCTAssertEqual(completed.ledgerEntries.filter { $0.kindRaw == "payment" }.map(\.amountCents).sorted(),
                       [3000, 5000, 40000])
        try withStoreFixture { directory in
            let snapshot = try ArchiveSnapshot.capture(context: context)
            let url = directory.appendingPathComponent("restored.store")
            try snapshot.restore(toNewStoreAt: url)
            let restored = try StoreFactory.makeContainer(url: url)
            XCTAssertEqual(completed, try BusinessArchive.capture(context: restored.mainContext))
        }
    }

    func testDuplicateOrEmptyParticipantsAreRejectedWithoutChanges() async throws {
        let store = try StoreFactory.makeContainer(inMemory: true)
        let context = store.mainContext
        let client = try BusinessTestStore.addClient(context)
        let repository = BusinessRepository(context: context)
        var draft = BusinessTestStore.session(client)
        draft.participants = []
        XCTAssertThrowsError(try repository.saveSession(draft))
        draft.participants = [ParticipantDraft(clientID: client.id, priceCents: 5000),
                              ParticipantDraft(clientID: client.id, priceCents: 3500)]
        XCTAssertThrowsError(try repository.saveSession(draft))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TrainingSession>()), 0)
        XCTAssertFalse(context.hasChanges)
    }

    func testFailedGroupCompletionDoesNotLeavePartialIncomeOrStatusChanges() async throws {
        let store = try StoreFactory.makeContainer(inMemory: true)
        let context = store.mainContext
        let clients = try ["Uno", "Due", "Tre", "Quattro"].map {
            try BusinessTestStore.addClient(context, name: $0)
        }
        let repository = BusinessRepository(context: context)
        var draft = BusinessTestStore.session(clients[0])
        draft.participants = clients.map { ParticipantDraft(clientID: $0.id, priceCents: 5000) }
        let id = try repository.saveSession(draft)
        let snapshot = try BusinessArchive.capture(context: context)
        let error = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError)
        let failing = BusinessRepository(context: context) { _ in throw error }
        XCTAssertThrowsError(try failing.setSessionStatus(id, to: .completed))
        XCTAssertEqual(try BusinessArchive.capture(context: context), snapshot)
        XCTAssertFalse(context.hasChanges)
        try repository.setSessionStatus(id, to: .completed)
        let entries = try context.fetch(FetchDescriptor<LedgerEntry>())
        XCTAssertEqual(entries.filter { $0.kind == .payment }.count, 4)
        XCTAssertEqual(entries.filter { $0.kind == .payment }.reduce(0) { $0 + $1.amountCents }, 20000)
    }
}
