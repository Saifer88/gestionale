import Foundation
@testable import PaolaCore
import SwiftData
import XCTest

@MainActor
final class ClientSaveFailureTests: XCTestCase {
    func testFailedInsertCanBeRetriedWithoutGhostClientsOrDuplicates() async throws {
        let container = try StoreFactory.makeContainer(inMemory: true)
        let context = container.mainContext
        let failure = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError)
        var shouldFail = true
        let repository = ClientRepository(context: context) { writer in
            XCTAssertFalse(writer === context)
            XCTAssertFalse(writer.autosaveEnabled)
            writer.processPendingChanges()
            if shouldFail { throw failure }
            try writer.save()
        }
        let draft = makeDraft(email: "prova@example.it",
                              anamnesis: "Anamnesi nuova", physicalAnalysis: "Analisi nuova")

        for _ in 0..<2 {
            XCTAssertThrowsError(try repository.save(draft)) {
                XCTAssertEqual($0 as NSError, failure)
            }
            XCTAssertTrue(try context.fetch(FetchDescriptor<Client>()).isEmpty)
            XCTAssertFalse(context.hasChanges)
        }
        shouldFail = false
        let client = try repository.save(draft)
        XCTAssertTrue(client.modelContext === context)
        XCTAssertEqual(client.email, draft.email)
        XCTAssertEqual(client.anamnesis, draft.anamnesis)
        XCTAssertEqual(client.physicalAnalysis, draft.physicalAnalysis)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Client>()), 1)
        XCTAssertFalse(context.hasChanges)
        XCTAssertThrowsError(try repository.save(draft)) {
            XCTAssertEqual($0 as? ClientValidationError, .possibleDuplicate)
        }
    }

    func testFailedEditAndArchivePreserveAllValuesAndAllowRetry() async throws {
        try withStoreFixture { directory in
            let url = directory.appendingPathComponent("Clienti.store")
            let container = try StoreFactory.makeContainer(url: url)
            let context = container.mainContext
            let client = try ClientRepository(context: context).save(makeDraft(
                phone: "3331234567", email: "prima@example.it", notes: "Nota originale",
                anamnesis: "Anamnesi originale\nSeconda riga", physicalAnalysis: "Analisi originale"
            ))
            let original = ClientDraft(client: client)
            let id = client.id
            let createdAt = client.createdAt
            let updatedAt = client.updatedAt
            var draft = original
            draft.firstName = "Anna"
            draft.lastName = "Verdi"
            draft.phone = "3337654321"
            draft.email = "dopo@example.it"
            draft.notes = "Nota nuova"
            draft.anamnesis = "Anamnesi nuova"
            draft.physicalAnalysis = "Analisi nuova"
            draft.joinedOn = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
            let failure = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)
            var shouldFail = true
            let repository = ClientRepository(context: context) { writer in
                writer.processPendingChanges()
                if shouldFail { throw failure }
                try writer.save()
            }

            for _ in 0..<2 {
                XCTAssertThrowsError(try repository.save(draft, updating: client)) {
                    XCTAssertEqual($0 as NSError, failure)
                }
                XCTAssertThrowsError(try repository.setArchived(true, for: client)) {
                    XCTAssertEqual($0 as NSError, failure)
                }
                XCTAssertEqual(client.firstName, original.firstName)
                XCTAssertEqual(client.lastName, original.lastName)
                XCTAssertEqual(client.phone, original.phone)
                XCTAssertEqual(client.email, original.email)
                XCTAssertEqual(client.notes, original.notes)
                XCTAssertEqual(client.anamnesis, original.anamnesis)
                XCTAssertEqual(client.physicalAnalysis, original.physicalAnalysis)
                XCTAssertEqual(client.joinedOn, original.joinedOn)
                XCTAssertEqual(client.updatedAt, updatedAt)
                XCTAssertEqual(client.id, id)
                XCTAssertEqual(client.createdAt, createdAt)
                XCTAssertFalse(client.isArchived)
                XCTAssertFalse(context.hasChanges)
                let reader = ModelContext(container)
                let stored = try XCTUnwrap(reader.fetch(FetchDescriptor<Client>()).first)
                XCTAssertEqual(stored.email, original.email)
                XCTAssertEqual(stored.anamnesis, original.anamnesis)
                XCTAssertEqual(stored.physicalAnalysis, original.physicalAnalysis)
                XCTAssertFalse(stored.isArchived)
            }

            shouldFail = false
            XCTAssertTrue(try repository.save(draft, updating: client) === client)
            XCTAssertEqual(client.email, draft.email)
            XCTAssertEqual(client.anamnesis, draft.anamnesis)
            XCTAssertEqual(client.physicalAnalysis, draft.physicalAnalysis)
            try repository.setArchived(true, for: client)
            XCTAssertTrue(client.isArchived)
            XCTAssertEqual(client.id, id)
            XCTAssertEqual(client.createdAt, createdAt)
            XCTAssertFalse(context.hasChanges)

            let reopened = try StoreFactory.makeContainer(url: url)
            let records = try reopened.mainContext.fetch(FetchDescriptor<Client>())
            XCTAssertEqual(records.count, 1)
            let stored = try XCTUnwrap(records.first)
            XCTAssertEqual(stored.firstName, draft.firstName)
            XCTAssertEqual(stored.lastName, draft.lastName)
            XCTAssertEqual(stored.phone, draft.phone)
            XCTAssertEqual(stored.email, draft.email)
            XCTAssertEqual(stored.notes, draft.notes)
            XCTAssertEqual(stored.anamnesis, draft.anamnesis)
            XCTAssertEqual(stored.physicalAnalysis, draft.physicalAnalysis)
            XCTAssertEqual(stored.joinedOn, draft.joinedOn)
            XCTAssertEqual(stored.id, id)
            XCTAssertEqual(stored.createdAt, createdAt)
            XCTAssertTrue(stored.isArchived)
        }
    }
}
