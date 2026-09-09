import Foundation
@testable import PaolaCore
import SwiftData
import XCTest

@MainActor
final class ClientSensitiveFieldsTests: XCTestCase {
    func testSaveReadEditAndClearPreserveMultilineUnicodeAndMetadata() async throws {
        try withStoreFixture { directory in
            let url = directory.appendingPathComponent("client.store")
            let store = try StoreFactory.makeContainer(url: url)
            let repository = ClientRepository(context: store.mainContext)
            let client = try repository.save(makeDraft(
                anamnesis: " \nStoria: già valutata 🩺\n\n  Dettagli interni.\n ",
                physicalAnalysis: "\tMobilità: così\n\n第二行\n "
            ))
            let id = client.id
            let createdAt = client.createdAt
            XCTAssertEqual(client.anamnesis, "Storia: già valutata 🩺\n\n  Dettagli interni.")
            XCTAssertEqual(client.physicalAnalysis, "Mobilità: così\n\n第二行")
            let reopened = try StoreFactory.makeContainer(url: url)
            let stored = try XCTUnwrap(reopened.mainContext.fetch(FetchDescriptor<Client>()).first)
            XCTAssertEqual(stored.anamnesis, client.anamnesis)
            XCTAssertEqual(stored.physicalAnalysis, client.physicalAnalysis)
            var edit = ClientDraft(client: stored)
            edit.anamnesis = "Aggiornata\n\nNuovo paragrafo"
            edit.physicalAnalysis = "Valutazione aggiornata"
            let updatedAt = stored.updatedAt
            let secondRepository = ClientRepository(context: reopened.mainContext)
            try secondRepository.save(edit, updating: stored)
            XCTAssertEqual(stored.id, id)
            XCTAssertEqual(stored.createdAt, createdAt)
            XCTAssertGreaterThan(stored.updatedAt, updatedAt)
            XCTAssertEqual(stored.anamnesis, edit.anamnesis)
            XCTAssertEqual(stored.physicalAnalysis, edit.physicalAnalysis)
            edit = ClientDraft(client: stored)
            edit.anamnesis = "\n\t"
            edit.physicalAnalysis = " \n "
            try secondRepository.save(edit, updating: stored)
            let final = try StoreFactory.makeContainer(url: url)
            let cleared = try XCTUnwrap(final.mainContext.fetch(FetchDescriptor<Client>()).first)
            XCTAssertEqual(cleared.anamnesis, "")
            XCTAssertEqual(cleared.physicalAnalysis, "")
            XCTAssertEqual(cleared.id, id)
            XCTAssertEqual(cleared.createdAt, createdAt)
            XCTAssertFalse(reopened.mainContext.hasChanges)
        }
    }

    func testInvalidDuplicateAndStaleEditsNeverChangeEitherSensitiveField() async throws {
        let store = try StoreFactory.makeContainer(inMemory: true)
        let context = store.mainContext
        let repository = ClientRepository(context: context)
        let client = try repository.save(makeDraft(email: "prima@example.it",
            anamnesis: "Anamnesi originale", physicalAnalysis: "Analisi originale"))
        _ = try repository.save(makeDraft(firstName: "Anna", email: "seconda@example.it"))
        let original = ArchiveSnapshot.ClientRecord(client)
        for email in ["email errata", "seconda@example.it"] {
            var edit = ClientDraft(client: client)
            edit.email = email
            edit.anamnesis = "Non salvata"
            edit.physicalAnalysis = "Non salvata"
            XCTAssertThrowsError(try repository.save(edit, updating: client))
            XCTAssertEqual(ArchiveSnapshot.ClientRecord(client), original)
            let stored = try XCTUnwrap(ModelContext(store).fetch(FetchDescriptor<Client>()).first { $0.id == client.id })
            XCTAssertEqual(ArchiveSnapshot.ClientRecord(stored), original)
            XCTAssertFalse(context.hasChanges)
        }
        var stale = ClientDraft(client: client)
        stale.anamnesis = "Vecchia scheda"
        stale.physicalAnalysis = "Vecchia analisi"
        var updated = ClientDraft(client: client)
        updated.anamnesis = "Anamnesi aggiornata"
        updated.physicalAnalysis = "Analisi aggiornata"
        try repository.save(updated, updating: client)
        let latest = ArchiveSnapshot.ClientRecord(client)
        XCTAssertThrowsError(try repository.save(stale, updating: client, allowDuplicate: true))
        XCTAssertEqual(ArchiveSnapshot.ClientRecord(client), latest)
        XCTAssertFalse(context.hasChanges)
    }

    func testSensitiveFieldsNeverEnterSearchBusinessSnapshotsOrStatements() async throws {
        let store = try StoreFactory.makeContainer(inMemory: true)
        let context = store.mainContext
        let anamnesis = "RiservatoAnamnesi🩺\n\nInformazioni private"
        let analysis = "RiservatoFisica🧘\n\n第二行"
        let client = try ClientRepository(context: context).save(makeDraft(
            anamnesis: anamnesis, physicalAnalysis: analysis))
        for filter in ClientFilter.allCases {
            for query in ["RiservatoAnamnesi", "RiservatoFisica", "private", "第二行"] {
                XCTAssertFalse(ClientSearch.matches(client, query: query, filter: filter))
            }
        }
        XCTAssertTrue(ClientSearch.matches(client, query: "Paola Rossi", filter: .active))
        let repository = BusinessRepository(context: context)
        let id = try repository.saveSession(BusinessTestStore.session(client))
        try repository.setSessionStatus(id, to: .completed)
        let archive = try BusinessArchive.capture(context: context)
        let json = String(decoding: try JSONEncoder().encode(archive), as: UTF8.self)
        let entries = try context.fetch(FetchDescriptor<LedgerEntry>())
        let statement = BusinessReports.statement(clientID: client.id, from: .distantPast, to: .distantFuture,
                                                  entries: entries)
        let reportText = statement.entries.map { "\($0.clientName) \($0.notes)" }.joined()
        for marker in ["RiservatoAnamnesi", "RiservatoFisica", "anamnesis", "physicalAnalysis", "第二行"] {
            XCTAssertFalse(json.contains(marker))
            XCTAssertFalse(reportText.contains(marker))
        }
        XCTAssertEqual(statement.closingBalance, 0)
        XCTAssertEqual(statement.chargedCents, 5000)
        XCTAssertEqual(statement.paidCents, 5000)
    }
}
