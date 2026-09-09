import Foundation
@testable import PaolaCore
import SwiftData
import XCTest

@MainActor
final class ClientPreferredServiceTests: XCTestCase {
    private func service(in context: ModelContext, name: String = "Allenamento") throws -> (UUID, [ServiceRateDraft]) {
        var draft = ServiceDraft()
        draft.name = name
        draft.tariffs = [ServiceRateDraft(name: "Standard", priceCents: 5000), ServiceRateDraft(name: "Ridotta", priceCents: 3500)]
        return (try BusinessRepository(context: context).saveService(draft), draft.tariffs)
    }

    func testCreateReopenEditClearAndArchivePreferredServiceAndRate() async throws {
        try withStoreFixture { directory in
            let url = directory.appendingPathComponent("clients.store")
            let store = try StoreFactory.makeContainer(url: url)
            let (serviceID, rates) = try service(in: store.mainContext)
            var draft = makeDraft()
            draft.preferredServiceID = serviceID
            draft.preferredRateID = rates[1].id
            let client = try ClientRepository(context: store.mainContext).save(draft)
            let id = client.id
            let createdAt = client.createdAt
            let reopened = try StoreFactory.makeContainer(url: url)
            let stored = try XCTUnwrap(reopened.mainContext.fetch(FetchDescriptor<Client>()).first)
            XCTAssertEqual(stored.preferredServiceID, serviceID)
            XCTAssertEqual(stored.preferredRateID, rates[1].id)
            var edit = ClientDraft(client: stored)
            XCTAssertEqual(edit.preferredRateID, rates[1].id)
            edit.preferredRateID = rates[0].id
            let repository = ClientRepository(context: reopened.mainContext)
            try repository.save(edit, updating: stored)
            try repository.setArchived(true, for: stored)
            XCTAssertEqual(stored.preferredRateID, rates[0].id)
            edit = ClientDraft(client: stored)
            edit.preferredServiceID = nil
            edit.preferredRateID = nil
            try repository.save(edit, updating: stored)
            XCTAssertNil(stored.preferredServiceID)
            XCTAssertNil(stored.preferredRateID)
            XCTAssertTrue(stored.isArchived)
            XCTAssertEqual(stored.id, id)
            XCTAssertEqual(stored.createdAt, createdAt)
        }
    }

    func testInvalidReferencesAndForeignRatesDoNotInsertOrModifyClients() async throws {
        let store = try StoreFactory.makeContainer(inMemory: true)
        let context = store.mainContext
        let (serviceID, rates) = try service(in: context)
        let (otherID, _) = try service(in: context, name: "Altro")
        let repository = ClientRepository(context: context)
        for (serviceID, rateID): (UUID?, UUID?) in [
            (nil, rates[0].id), (UUID(), nil), (serviceID, UUID()), (otherID, rates[0].id)
        ] {
            var draft = makeDraft()
            draft.preferredServiceID = serviceID
            draft.preferredRateID = rateID
            XCTAssertThrowsError(try repository.save(draft)) {
                XCTAssertEqual($0 as? ClientValidationError, .invalidPreference)
            }
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<Client>()), 0)
            XCTAssertFalse(context.hasChanges)
        }
        let client = try repository.save(makeDraft())
        let original = ArchiveSnapshot.ClientRecord(client)
        var edit = ClientDraft(client: client)
        edit.firstName = "Da non salvare"
        edit.preferredServiceID = UUID()
        XCTAssertThrowsError(try repository.save(edit, updating: client))
        XCTAssertEqual(ArchiveSnapshot.ClientRecord(client), original)
    }

    func testDraftCancellationAndFailedSaveKeepPreferencesUnchanged() async throws {
        let store = try StoreFactory.makeContainer(inMemory: true)
        let context = store.mainContext
        let (serviceID, rates) = try service(in: context)
        let client = try ClientRepository(context: context).save(makeDraft())
        let original = ArchiveSnapshot.ClientRecord(client)
        var edit = ClientDraft(client: client)
        edit.preferredServiceID = serviceID
        edit.preferredRateID = rates[1].id
        XCTAssertEqual(ArchiveSnapshot.ClientRecord(client), original)
        let error = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError)
        let failing = ClientRepository(context: context) { _ in throw error }
        XCTAssertThrowsError(try failing.save(edit, updating: client))
        XCTAssertEqual(ArchiveSnapshot.ClientRecord(client), original)
        XCTAssertFalse(context.hasChanges)
    }

    func testObsoletePreferencesCanBeKeptOnUnrelatedEditButCannotBeNewlySelected() async throws {
        let store = try StoreFactory.makeContainer(inMemory: true)
        let context = store.mainContext
        let (serviceID, rates) = try service(in: context)
        var draft = makeDraft()
        draft.preferredServiceID = serviceID
        draft.preferredRateID = rates[1].id
        let repository = ClientRepository(context: context)
        let client = try repository.save(draft)
        let model = try XCTUnwrap(context.fetch(FetchDescriptor<TrainingService>()).first)
        var serviceDraft = try ServiceDraft(model, rates: context.fetch(FetchDescriptor<ServiceRate>()))
        serviceDraft.isActive = false
        serviceDraft.tariffs = [rates[0]]
        try BusinessRepository(context: context).saveService(serviceDraft)
        var edit = ClientDraft(client: client)
        edit.phone = "3331234567"
        XCTAssertNoThrow(try repository.save(edit, updating: client))
        XCTAssertEqual(client.preferredRateID, rates[1].id)
        var newClient = makeDraft(firstName: "Altro")
        newClient.preferredServiceID = serviceID
        XCTAssertThrowsError(try repository.save(newClient))
        XCTAssertNoThrow(try ArchiveSnapshot.capture(context: context))
    }

    func testPreferenceDoesNotChangeWhenBookingWithAnotherService() async throws {
        let store = try StoreFactory.makeContainer(inMemory: true)
        let context = store.mainContext
        let (preferredID, rates) = try service(in: context)
        let (otherID, otherRates) = try service(in: context, name: "Occasionale")
        var draft = makeDraft()
        draft.preferredServiceID = preferredID
        draft.preferredRateID = rates[1].id
        let client = try ClientRepository(context: context).save(draft)
        var session = BusinessTestStore.session(client)
        session.serviceID = otherID
        session.participants[0].tariffID = otherRates[0].id
        try BusinessRepository(context: context).saveSession(session)
        XCTAssertEqual(client.preferredServiceID, preferredID)
        XCTAssertEqual(client.preferredRateID, rates[1].id)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ClientAppointmentPreference>()).first?.serviceID, otherID)
    }
}
