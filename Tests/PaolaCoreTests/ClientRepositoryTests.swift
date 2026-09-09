import Foundation
import PaolaCore
import SwiftData
import XCTest

@MainActor
final class ClientRepositoryTests: XCTestCase {
    func testCreateReadUpdateAndArchivePreserveIdentityAndCreationDate() async throws {
        let container = try StoreFactory.makeContainer(inMemory: true)
        let context = container.mainContext
        let repository = ClientRepository(context: context)
        var draft = makeDraft(firstName: "  Paola  ", phone: " +39 333 1234567 ")
        draft.joinedOn = Date(timeIntervalSince1970: 1_700_043_210)
        let client = try repository.save(draft)
        let id = client.id
        let createdAt = client.createdAt
        let firstUpdatedAt = client.updatedAt

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Client>()), 1)
        XCTAssertEqual(client.firstName, "Paola")
        XCTAssertEqual(client.joinedOn, Calendar.current.startOfDay(for: draft.joinedOn))
        XCTAssertEqual(firstUpdatedAt, createdAt)
        XCTAssertFalse(context.hasChanges)
        XCTAssertFalse(context.autosaveEnabled)

        var edit = ClientDraft(client: client)
        edit.firstName = "Maria"
        edit.email = " MARIA@EXAMPLE.IT "
        edit.notes = " Disponibile dopo le 17. "
        let updated = try repository.save(edit, updating: client)
        XCTAssertTrue(updated === client)
        XCTAssertEqual(client.id, id)
        XCTAssertEqual(client.createdAt, createdAt)
        XCTAssertGreaterThan(client.updatedAt, firstUpdatedAt)
        XCTAssertEqual(client.email, "maria@example.it")
        XCTAssertEqual(client.notes, "Disponibile dopo le 17.")
        XCTAssertFalse(context.hasChanges)

        let editUpdatedAt = client.updatedAt
        try repository.setArchived(true, for: client)
        XCTAssertTrue(client.isArchived)
        XCTAssertEqual(client.id, id)
        XCTAssertEqual(client.createdAt, createdAt)
        XCTAssertGreaterThan(client.updatedAt, editUpdatedAt)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Client>()), 1)
        let archivedAt = client.updatedAt
        try repository.setArchived(true, for: client)
        XCTAssertEqual(client.updatedAt, archivedAt)
        try repository.setArchived(false, for: client)
        XCTAssertFalse(client.isArchived)
        XCTAssertGreaterThan(client.updatedAt, archivedAt)
        XCTAssertFalse(context.hasChanges)
    }

    func testEditingArchivedClientKeepsArchiveState() async throws {
        let container = try StoreFactory.makeContainer(inMemory: true)
        let repository = ClientRepository(context: container.mainContext)
        let client = try repository.save(makeDraft())
        try repository.setArchived(true, for: client)
        var draft = ClientDraft(client: client)
        draft.phone = "3331234567"
        try repository.save(draft, updating: client)
        XCTAssertTrue(client.isArchived)
        XCTAssertEqual(client.phone, "3331234567")
    }

    func testDiscardingDraftDoesNotChangeClient() async throws {
        let container = try StoreFactory.makeContainer(inMemory: true)
        let context = container.mainContext
        let repository = ClientRepository(context: context)
        let client = try repository.save(makeDraft(email: "paola@example.it", notes: "Nota organizzativa",
            anamnesis: "Anamnesi originale", physicalAnalysis: "Analisi originale"))
        let timestamp = client.updatedAt

        var cancelled = ClientDraft(client: client)
        XCTAssertEqual(cancelled.anamnesis, "Anamnesi originale")
        XCTAssertEqual(cancelled.physicalAnalysis, "Analisi originale")
        cancelled.firstName = "Non salvato"
        cancelled.email = ""
        cancelled.notes = ""
        cancelled.anamnesis = "Modifica annullata"
        cancelled.physicalAnalysis = ""
        cancelled.joinedOn = Date.distantPast

        XCTAssertEqual(cancelled.firstName, "Non salvato")
        XCTAssertEqual(client.firstName, "Paola")
        XCTAssertEqual(client.email, "paola@example.it")
        XCTAssertEqual(client.notes, "Nota organizzativa")
        XCTAssertEqual(client.anamnesis, "Anamnesi originale")
        XCTAssertEqual(client.physicalAnalysis, "Analisi originale")
        XCTAssertNotEqual(client.joinedOn, cancelled.joinedOn)
        XCTAssertEqual(client.updatedAt, timestamp)
        XCTAssertFalse(context.hasChanges)
        let stored = try XCTUnwrap(ModelContext(container).fetch(FetchDescriptor<Client>()).first)
        XCTAssertEqual(stored.anamnesis, "Anamnesi originale")
        XCTAssertEqual(stored.physicalAnalysis, "Analisi originale")
    }

    func testFailedValidationDoesNotInsertOrMutate() async throws {
        let container = try StoreFactory.makeContainer(inMemory: true)
        let context = container.mainContext
        let repository = ClientRepository(context: context)
        XCTAssertThrowsError(try repository.save(ClientDraft())) {
            XCTAssertEqual($0 as? ClientValidationError, .missingName)
        }
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Client>()), 0)

        let client = try repository.save(makeDraft(email: "paola@example.it"))
        let timestamp = client.updatedAt
        var edit = ClientDraft(client: client)
        edit.firstName = "Cambiato"
        edit.email = "email errata"
        XCTAssertThrowsError(try repository.save(edit, updating: client)) {
            XCTAssertEqual($0 as? ClientValidationError, .invalidEmail)
        }
        XCTAssertEqual(client.firstName, "Paola")
        XCTAssertEqual(client.email, "paola@example.it")
        XCTAssertEqual(client.updatedAt, timestamp)
        XCTAssertFalse(context.hasChanges)
    }

    func testDuplicatesByNamePhoneOrEmailAndExplicitOverride() async throws {
        let container = try StoreFactory.makeContainer(inMemory: true)
        let context = container.mainContext
        let repository = ClientRepository(context: context)
        let original = try repository.save(makeDraft(
            firstName: "Maria José", lastName: "De Rossi",
            phone: "+39 (333) 123-4567", email: "maria@example.it"
        ))
        let duplicates = [
            makeDraft(firstName: "  MARIA \t JOSE ", lastName: "de  rossi"),
            makeDraft(firstName: "Altro", lastName: "Nome", phone: "+39 3331234567"),
            makeDraft(firstName: "Nuovo", lastName: "Cliente", email: " MARIA@EXAMPLE.IT ")
        ]
        for draft in duplicates {
            XCTAssertThrowsError(try repository.save(draft)) {
                XCTAssertEqual($0 as? ClientValidationError, .possibleDuplicate)
            }
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<Client>()), 1)
            XCTAssertFalse(context.hasChanges)
        }

        let copy = try repository.save(duplicates[0], allowDuplicate: true)
        XCTAssertNotEqual(copy.id, original.id)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Client>()), 2)
    }

    func testArchivedClientsParticipateInDuplicateWarning() async throws {
        let container = try StoreFactory.makeContainer(inMemory: true)
        let repository = ClientRepository(context: container.mainContext)
        let client = try repository.save(makeDraft())
        try repository.setArchived(true, for: client)
        XCTAssertThrowsError(try repository.save(makeDraft())) {
            XCTAssertEqual($0 as? ClientValidationError, .possibleDuplicate)
        }
    }

    func testEmptyContactsDoNotMakeUnrelatedClientsDuplicates() async throws {
        let container = try StoreFactory.makeContainer(inMemory: true)
        let context = container.mainContext
        let repository = ClientRepository(context: context)
        try repository.save(makeDraft())
        try repository.save(makeDraft(firstName: "Anna", lastName: "Verdi", phone: " ", email: "\n"))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Client>()), 2)
    }

    func testEditExcludesItselfButChecksOtherClientsWithoutMutation() async throws {
        let container = try StoreFactory.makeContainer(inMemory: true)
        let context = container.mainContext
        let repository = ClientRepository(context: context)
        let first = try repository.save(makeDraft(email: "paola@example.it"))
        let second = try repository.save(makeDraft(firstName: "Anna", email: "anna@example.it"))
        try repository.save(ClientDraft(client: first), updating: first)
        let timestamp = second.updatedAt
        var edit = ClientDraft(client: second)
        edit.email = "paola@example.it"

        XCTAssertThrowsError(try repository.save(edit, updating: second)) {
            XCTAssertEqual($0 as? ClientValidationError, .possibleDuplicate)
        }
        XCTAssertEqual(second.email, "anna@example.it")
        XCTAssertEqual(second.updatedAt, timestamp)
        XCTAssertFalse(context.hasChanges)
        try repository.save(edit, updating: second, allowDuplicate: true)
        XCTAssertEqual(second.email, first.email)
    }

    func testStaleDraftCannotOverwriteNewerEditEvenWithDuplicateOverride() async throws {
        let container = try StoreFactory.makeContainer(inMemory: true)
        let context = container.mainContext
        let repository = ClientRepository(context: context)
        let client = try repository.save(makeDraft())
        var oldDraft = ClientDraft(client: client)
        var newDraft = ClientDraft(client: client)
        oldDraft.phone = "111"
        newDraft.phone = "222"
        try repository.save(newDraft, updating: client)
        let timestamp = client.updatedAt

        XCTAssertThrowsError(try repository.save(oldDraft, updating: client, allowDuplicate: true)) {
            XCTAssertEqual($0 as? ClientValidationError, .staleRecord)
        }
        XCTAssertEqual(client.phone, "222")
        XCTAssertEqual(client.updatedAt, timestamp)
        XCTAssertFalse(context.hasChanges)
    }

    func testArchiveChangeInvalidatesAnOpenDraft() async throws {
        let container = try StoreFactory.makeContainer(inMemory: true)
        let repository = ClientRepository(context: container.mainContext)
        let client = try repository.save(makeDraft())
        let draft = ClientDraft(client: client)
        try repository.setArchived(true, for: client)
        XCTAssertThrowsError(try repository.save(draft, updating: client)) {
            XCTAssertEqual($0 as? ClientValidationError, .staleRecord)
        }
        XCTAssertTrue(client.isArchived)
    }

    func testDraftCannotBeAppliedToWrongClientOrReinserted() async throws {
        let container = try StoreFactory.makeContainer(inMemory: true)
        let context = container.mainContext
        let repository = ClientRepository(context: context)
        let first = try repository.save(makeDraft())
        let second = try repository.save(makeDraft(firstName: "Anna"))
        let draft = ClientDraft(client: first)
        XCTAssertThrowsError(try repository.save(draft, updating: second, allowDuplicate: true)) {
            XCTAssertEqual($0 as? ClientValidationError, .staleRecord)
        }
        XCTAssertThrowsError(try repository.save(draft, allowDuplicate: true)) {
            XCTAssertEqual($0 as? ClientValidationError, .staleRecord)
        }
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Client>()), 2)
        XCTAssertFalse(context.hasChanges)
    }

    func testRepositoryRejectsDetachedOrDeletedClients() async throws {
        let container = try StoreFactory.makeContainer(inMemory: true)
        let context = container.mainContext
        let repository = ClientRepository(context: context)
        let detached = Client(firstName: "Paola", lastName: "Rossi")
        XCTAssertThrowsError(try repository.save(ClientDraft(client: detached), updating: detached)) {
            XCTAssertEqual($0 as? ClientValidationError, .staleRecord)
        }
        XCTAssertThrowsError(try repository.setArchived(true, for: detached)) {
            XCTAssertEqual($0 as? ClientValidationError, .staleRecord)
        }

        let client = try repository.save(makeDraft())
        let edit = ClientDraft(client: client)
        context.delete(client)
        XCTAssertThrowsError(try repository.save(edit, updating: client)) {
            XCTAssertEqual($0 as? ClientValidationError, .staleRecord)
        }
        XCTAssertThrowsError(try repository.setArchived(true, for: client)) {
            XCTAssertEqual($0 as? ClientValidationError, .staleRecord)
        }
        try context.save()
        XCTAssertThrowsError(try repository.save(edit, updating: client)) {
            XCTAssertEqual($0 as? ClientValidationError, .staleRecord)
        }
        XCTAssertThrowsError(try repository.setArchived(true, for: client)) {
            XCTAssertEqual($0 as? ClientValidationError, .staleRecord)
        }
    }

    func testRepositoryRejectsClientFromAnotherContext() async throws {
        let container = try StoreFactory.makeContainer(inMemory: true)
        let context = container.mainContext
        let otherContext = ModelContext(container)
        otherContext.autosaveEnabled = false
        let repository = ClientRepository(context: context)
        let client = try ClientRepository(context: otherContext).save(makeDraft())
        XCTAssertThrowsError(try repository.save(ClientDraft(client: client), updating: client)) {
            XCTAssertEqual($0 as? ClientValidationError, .staleRecord)
        }
        XCTAssertFalse(context.hasChanges)
        XCTAssertFalse(otherContext.hasChanges)
    }
}
