import Foundation
@testable import PaolaCore
import SwiftData
import XCTest

@MainActor
final class SchemaV5UpgradeTests: XCTestCase {
    func testMigratesVersionFourWithLastChoicesWithoutInventingExplicitPreferences() async throws {
        try withStoreFixture { directory in
            let url = directory.appendingPathComponent("v4.store")
            let clientID = UUID()
            let serviceID = UUID()
            let rateID = UUID()
            let timestamp = BusinessTestStore.date
            try autoreleasepool {
                let schema = Schema(versionedSchema: PaolaSchemaV4.self)
                let config = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
                let old = try ModelContainer(for: schema, configurations: [config])
                old.mainContext.autosaveEnabled = false
                let client = PaolaSchemaV3.Client(id: clientID, firstName: "Cliente", lastName: "Precedente",
                    phone: "3331234567", anamnesis: "Nota riservata", physicalAnalysis: "Analisi precedente",
                    createdAt: timestamp, updatedAt: timestamp)
                let service = TrainingService(id: serviceID, name: "Preferenza storica", priceCents: 3500)
                let rate = ServiceRate(id: rateID, serviceID: serviceID, name: "Ridotta", priceCents: 3500)
                let last = ClientAppointmentPreference(clientID: clientID, serviceID: serviceID,
                    preferredHour: 16, rateID: rateID, priceCents: 3500, updatedAt: timestamp)
                old.mainContext.insert(client); old.mainContext.insert(service)
                old.mainContext.insert(rate); old.mainContext.insert(last)
                try old.mainContext.save()
            }
            let current = try StoreFactory.makeContainer(url: url)
            let client = try XCTUnwrap(current.mainContext.fetch(FetchDescriptor<Client>()).first)
            XCTAssertEqual(client.id, clientID)
            XCTAssertEqual(client.createdAt, timestamp)
            XCTAssertEqual(client.phone, "3331234567")
            XCTAssertEqual(client.anamnesis, "Nota riservata")
            XCTAssertEqual(client.physicalAnalysis, "Analisi precedente")
            XCTAssertNil(client.preferredServiceID)
            XCTAssertNil(client.preferredRateID)
            let preference = try XCTUnwrap(current.mainContext.fetch(FetchDescriptor<ClientAppointmentPreference>()).first)
            XCTAssertEqual(preference.serviceID, serviceID)
            XCTAssertEqual(preference.rateID, rateID)
            XCTAssertEqual(preference.preferredHour, 16)
            XCTAssertEqual(try current.mainContext.fetchCount(FetchDescriptor<LedgerEntry>()), 0)
        }
    }

    func testBackupRoundTripKeepsExplicitPreferencesAndOldBackupRemainsReadable() async throws {
        try withStoreFixture { directory in
            let store = try StoreFactory.makeContainer(inMemory: true)
            let context = store.mainContext
            var service = ServiceDraft()
            service.name = "Preferito"
            service.tariffs = [ServiceRateDraft(name: "Tariffa", priceCents: 3500)]
            let serviceID = try BusinessRepository(context: context).saveService(service)
            var draft = makeDraft()
            draft.preferredServiceID = serviceID
            draft.preferredRateID = service.tariffs[0].id
            _ = try ClientRepository(context: context).save(draft)
            let snapshot = try ArchiveSnapshot.capture(context: context)
            XCTAssertEqual(snapshot.version, 5)
            let payload = try snapshot.encoded()
            let archive = try ArchiveSnapshot.decode(payload)
            let newURL = directory.appendingPathComponent("new.store")
            try archive.restore(toNewStoreAt: newURL)
            let restored = try StoreFactory.makeContainer(url: newURL)
            let restoredSnapshot = try ArchiveSnapshot.capture(context: restored.mainContext)
            XCTAssertEqual(snapshot.clients, restoredSnapshot.clients)
            XCTAssertEqual(snapshot.business, restoredSnapshot.business)

            var old = try XCTUnwrap(JSONSerialization.jsonObject(with: payload) as? [String: Any])
            old["version"] = 4
            var oldClients = try XCTUnwrap(old["clients"] as? [[String: Any]])
            oldClients[0].removeValue(forKey: "preferredServiceID")
            oldClients[0].removeValue(forKey: "preferredRateID")
            old["clients"] = oldClients
            let decoded = try ArchiveSnapshot.decode(JSONSerialization.data(withJSONObject: old))
            XCTAssertNil(decoded.clients.first?.preferredServiceID)
            XCTAssertNil(decoded.clients.first?.preferredRateID)
            XCTAssertEqual(decoded.business, snapshot.business)
        }
    }

    func testSnapshotRejectsPreferenceWithMissingServiceOrForeignRate() async throws {
        let store = try StoreFactory.makeContainer(inMemory: true)
        let context = store.mainContext
        var service = ServiceDraft()
        service.name = "Servizio"
        service.tariffs = [ServiceRateDraft()]
        let firstID = try BusinessRepository(context: context).saveService(service)
        let firstRate = service.tariffs[0].id
        service.id = nil
        service.tariffs = [ServiceRateDraft()]
        let secondID = try BusinessRepository(context: context).saveService(service)
        _ = try ClientRepository(context: context).save(makeDraft())
        let original = try ArchiveSnapshot.capture(context: context)
        var invalid = original
        invalid.clients[0].preferredServiceID = UUID()
        XCTAssertThrowsError(try invalid.validate())
        invalid.clients[0].preferredServiceID = nil
        invalid.clients[0].preferredRateID = firstRate
        XCTAssertThrowsError(try invalid.validate())
        invalid.clients[0].preferredServiceID = secondID
        XCTAssertThrowsError(try invalid.validate())
        invalid.clients[0].preferredServiceID = firstID
        XCTAssertNoThrow(try invalid.validate())
    }
}
