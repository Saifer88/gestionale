import Foundation
import PaolaCore
import SwiftData
import XCTest

@MainActor
final class StoreFactoryTests: XCTestCase {
    func testVersionedSchemaOpensLocallyWithoutSeedDataOrAutosave() async throws {
        let container = try StoreFactory.makeContainer(inMemory: true)
        XCTAssertEqual(PaolaSchemaV1.versionIdentifier, Schema.Version(1, 0, 0))
        XCTAssertEqual(PaolaSchemaV1.models.count, 1)
        XCTAssertEqual(PaolaSchemaMigrationPlan.schemas.count, 9)
        XCTAssertEqual(PaolaSchemaMigrationPlan.stages.count, 8)
        XCTAssertEqual(PaolaSchemaV3.versionIdentifier, Schema.Version(3, 0, 0))
        XCTAssertEqual(PaolaSchemaV3.models.count, 9)
        XCTAssertEqual(PaolaSchemaV4.versionIdentifier, Schema.Version(4, 0, 0))
        XCTAssertEqual(PaolaSchemaV4.models.count, 10)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Client>()), 0)
        XCTAssertFalse(container.mainContext.autosaveEnabled)
        XCTAssertEqual(container.configurations.count, 1)
        let configuration = try XCTUnwrap(container.configurations.first)
        XCTAssertTrue(configuration.isStoredInMemoryOnly)
        XCTAssertNil(configuration.cloudKitContainerIdentifier)
    }

    func testSchemaAttributesHaveDefaultsAndNoUniqueConstraintsOrRelationships() async throws {
        let schema = Schema(versionedSchema: PaolaSchemaV1.self)
        XCTAssertEqual(schema.version, Schema.Version(1, 0, 0))
        XCTAssertEqual(schema.entities.count, 1)
        let entity = try XCTUnwrap(schema.entities.first)
        XCTAssertTrue(entity.relationships.isEmpty)
        XCTAssertEqual(
            Set(entity.attributes.map(\.name)),
            Set(["id", "firstName", "lastName", "phone", "email", "notes", "joinedOn", "createdAt", "updatedAt", "isArchived"])
        )
        for attribute in entity.attributes {
            XCTAssertNotNil(attribute.defaultValue, attribute.name)
            XCTAssertFalse(attribute.isUnique, attribute.name)
        }
    }

    func testMemoryStoreIgnoresDiskURLAndDoesNotCreateItsDirectory() async throws {
        try withStoreFixture { directory in
            let ignoredURL = directory.appendingPathComponent("unused/Clienti-v1.store")
            let first = try StoreFactory.makeContainer(url: ignoredURL, inMemory: true)
            try ClientRepository(context: first.mainContext).save(makeDraft())
            let second = try StoreFactory.makeContainer(inMemory: true)
            XCTAssertEqual(try second.mainContext.fetchCount(FetchDescriptor<Client>()), 0)
            XCTAssertFalse(FileManager.default.fileExists(atPath: ignoredURL.deletingLastPathComponent().path))
        }
    }

    func testDiskPersistenceAcrossReopenWithMigrationPlan() async throws {
        try withStoreFixture { directory in
            let url = directory.appendingPathComponent("nested/Clienti-v1.store")
            let id = UUID()
            let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
            let joinedOn = Calendar.current.startOfDay(for: createdAt)
            try autoreleasepool {
                let container = try StoreFactory.makeContainer(url: url)
                let client = Client(
                    id: id, firstName: "Paola", lastName: "Rossi",
                    phone: "+39 333 1234567", email: "paola@example.it",
                    notes: "Preferisce il pomeriggio", joinedOn: joinedOn, createdAt: createdAt
                )
                container.mainContext.insert(client)
                try container.mainContext.save()
                let configuration = try XCTUnwrap(container.configurations.first)
                XCTAssertEqual(configuration.url, url)
                XCTAssertFalse(configuration.isStoredInMemoryOnly)
                XCTAssertNil(configuration.cloudKitContainerIdentifier)
            }
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
            try autoreleasepool {
                let reopened = try StoreFactory.makeContainer(url: url)
                let clients = try reopened.mainContext.fetch(FetchDescriptor<Client>())
                XCTAssertEqual(clients.count, 1)
                let client = try XCTUnwrap(clients.first)
                XCTAssertEqual(client.id, id)
                XCTAssertEqual(client.createdAt, createdAt)
                XCTAssertEqual(client.updatedAt, createdAt)
                XCTAssertEqual(client.joinedOn, joinedOn)
                XCTAssertEqual(client.email, "paola@example.it")
                XCTAssertEqual(client.phone, "+39 333 1234567")
                XCTAssertEqual(client.notes, "Preferisce il pomeriggio")
                var draft = ClientDraft(client: client)
                draft.firstName = "Maria"
                let repository = ClientRepository(context: reopened.mainContext)
                try repository.save(draft, updating: client)
                try repository.setArchived(true, for: client)
            }
            try autoreleasepool {
                let reopenedAgain = try StoreFactory.makeContainer(url: url)
                let clients = try reopenedAgain.mainContext.fetch(FetchDescriptor<Client>())
                XCTAssertEqual(clients.count, 1)
                let client = try XCTUnwrap(clients.first)
                XCTAssertEqual(client.id, id)
                XCTAssertEqual(client.createdAt, createdAt)
                XCTAssertGreaterThan(client.updatedAt, createdAt)
                XCTAssertEqual(client.firstName, "Maria")
                XCTAssertTrue(client.isArchived)
            }
        }
    }

    func testInvalidDiskPathThrowsWithoutMemoryFallbackOrOverwritingFiles() async throws {
        try withStoreFixture { directory in
            let blocker = directory.appendingPathComponent("not-a-directory")
            let original = Data("Keep this file intact.".utf8)
            try original.write(to: blocker)
            XCTAssertThrowsError(try StoreFactory.makeContainer(url: blocker.appendingPathComponent("Clienti.store")))
            XCTAssertEqual(try Data(contentsOf: blocker), original)
        }
        XCTAssertThrowsError(try StoreFactory.makeContainer(url: XCTUnwrap(URL(string: "https://example.invalid/store"))))
    }

    func testCorruptStoreThrowsAndIsNotReplaced() async throws {
        try withStoreFixture { directory in
            let url = directory.appendingPathComponent("Clienti-v1.store")
            let original = Data("This is not a SQLite store.".utf8)
            try original.write(to: url)
            XCTAssertThrowsError(try StoreFactory.makeContainer(url: url))
            XCTAssertEqual(try Data(contentsOf: url), original)
        }
    }

    func testPersistenceFailureRollsBackEditsArchiveAndInsert() async throws {
        try withStoreFixture { directory in
            let url = directory.appendingPathComponent("Clienti-v1.store")
            try autoreleasepool {
                let container = try StoreFactory.makeContainer(url: url)
                try ClientRepository(context: container.mainContext).save(makeDraft(
                    anamnesis: "Anamnesi salvata", physicalAnalysis: "Analisi salvata"))
            }
            try autoreleasepool {
                let schema = Schema(versionedSchema: PaolaSchemaV9.self)
                let configuration = ModelConfiguration(
                    "PaolaGestionale",
                    schema: schema,
                    url: url,
                    allowsSave: false,
                    cloudKitDatabase: .none
                )
                let container = try ModelContainer(
                    for: schema,
                    migrationPlan: PaolaSchemaMigrationPlan.self,
                    configurations: [configuration]
                )
                let context = container.mainContext
                let repository = ClientRepository(context: context)
                let client = try XCTUnwrap(context.fetch(FetchDescriptor<Client>()).first)
                let id = client.id
                let timestamp = client.updatedAt
                var draft = ClientDraft(client: client)
                draft.firstName = "Non salvato"
                draft.anamnesis = "Anamnesi non salvata"
                draft.physicalAnalysis = "Analisi non salvata"

                XCTAssertThrowsError(try repository.save(draft, updating: client))
                XCTAssertEqual(client.firstName, "Paola")
                XCTAssertEqual(client.anamnesis, "Anamnesi salvata")
                XCTAssertEqual(client.physicalAnalysis, "Analisi salvata")
                XCTAssertEqual(client.id, id)
                XCTAssertEqual(client.updatedAt, timestamp)
                XCTAssertFalse(context.hasChanges)

                XCTAssertThrowsError(try repository.setArchived(true, for: client))
                XCTAssertFalse(client.isArchived)
                XCTAssertEqual(client.updatedAt, timestamp)
                XCTAssertFalse(context.hasChanges)

                XCTAssertThrowsError(try repository.save(makeDraft(firstName: "Anna",
                    anamnesis: "Inserimento non salvato", physicalAnalysis: "Analisi non salvata")))
                XCTAssertEqual(try context.fetchCount(FetchDescriptor<Client>()), 1)
                XCTAssertFalse(context.hasChanges)
            }
            let reopened = try StoreFactory.makeContainer(url: url)
            let client = try XCTUnwrap(reopened.mainContext.fetch(FetchDescriptor<Client>()).first)
            XCTAssertEqual(client.anamnesis, "Anamnesi salvata")
            XCTAssertEqual(client.physicalAnalysis, "Analisi salvata")
        }
    }
}
