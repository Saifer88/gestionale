import Foundation
@testable import PaolaCore
import SwiftData
import XCTest

@MainActor
final class SchemaV4UpgradeTests: XCTestCase {
    func testMigrationKeepsLegacyPaymentsCompletedSessionsAndClientsWithoutBackfillingIncome() async throws {
        try withStoreFixture { directory in
            let url = directory.appendingPathComponent("v3.store")
            let clientID = UUID()
            let completedID = UUID()
            let packageID = UUID()
            let date = BusinessTestStore.date
            try autoreleasepool {
                let schema = Schema(versionedSchema: PaolaSchemaV3.self)
                let config = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
                let old = try ModelContainer(for: schema, configurations: [config])
                let context = old.mainContext
                context.autosaveEnabled = false
                let client = Client(id: clientID, firstName: "Prova", lastName: "Storico",
                                    anamnesis: "Anamnesi conservata", physicalAnalysis: "Analisi conservata")
                let service = TrainingService(name: "Servizio storico", priceCents: 5000)
                let rate = ServiceRate(serviceID: service.id, name: "Tariffa storica", priceCents: 5000)
                let session = TrainingSession(id: completedID, startDate: date, serviceID: service.id,
                                              serviceName: service.name, status: .completed)
                let person = SessionParticipant(sessionID: session.id, clientID: clientID,
                                                clientName: client.fullName, priceCents: 5000)
                let package = LessonPackage(id: packageID, clientID: clientID, clientName: client.fullName,
                                             purchasedOn: date, priceCents: 40000)
                context.insert(client); context.insert(service); context.insert(rate)
                context.insert(session); context.insert(person); context.insert(package)
                context.insert(LedgerEntry(clientID: clientID, clientName: client.fullName, date: date,
                    kind: .charge, amountCents: 5000,
                    sourceKey: BusinessRules.sessionSource(sessionID: completedID, clientID: clientID)))
                context.insert(LedgerEntry(clientID: clientID, clientName: client.fullName, date: date,
                    kind: .charge, amountCents: 40000, sourceKey: BusinessRules.packageSource(packageID)))
                context.insert(LedgerEntry(clientID: clientID, clientName: client.fullName, date: date,
                    kind: .payment, amountCents: 12345, method: .bankTransfer, sourceKey: "payment:storico"))
                try context.save()
            }
            let migrated = try StoreFactory.makeContainer(url: url)
            let context = migrated.mainContext
            let client = try XCTUnwrap(context.fetch(FetchDescriptor<Client>()).first)
            XCTAssertEqual(client.id, clientID)
            XCTAssertEqual(client.anamnesis, "Anamnesi conservata")
            XCTAssertEqual(client.physicalAnalysis, "Analisi conservata")
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<ServiceRate>()), 1)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<ClientAppointmentPreference>()), 0)
            let initial = try context.fetch(FetchDescriptor<LedgerEntry>())
            XCTAssertEqual(initial.count, 3)
            XCTAssertEqual(initial.filter { $0.kind == .payment }.map(\.amountCents), [12345])
            XCTAssertFalse(initial.contains { $0.sourceKey.hasPrefix("income:") })
            let repository = BusinessRepository(context: context)
            try repository.setSessionStatus(completedID, to: .completed)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<LedgerEntry>()), 3)
            XCTAssertEqual(BusinessReports.balance(clientID: clientID, entries: initial), 32655)

            var draft = PackageDraft()
            draft.clientID = clientID
            draft.purchasedOn = date
            draft.priceCents = 20000
            let newID = try repository.savePackage(draft)
            let saved = try context.fetch(FetchDescriptor<LedgerEntry>())
            XCTAssertEqual(saved.count, 5)
            XCTAssertEqual(saved.filter { $0.sourceKey == BusinessRules.packageIncomeSource(newID) }.count, 1)
            XCTAssertFalse(saved.contains { $0.sourceKey == BusinessRules.packageIncomeSource(packageID) })
        }
    }

    func testVersionFourBackupRestoresPreferencesAndVersionThreeBackupDecodesWithoutThem() async throws {
        try withStoreFixture { directory in
            let container = try StoreFactory.makeContainer(inMemory: true)
            let context = container.mainContext
            let client = try BusinessTestStore.addClient(context)
            let repository = BusinessRepository(context: context)
            var service = ServiceDraft()
            service.name = "Allenamento"
            service.tariffs = [ServiceRateDraft(name: "Base", priceCents: 5000),
                               ServiceRateDraft(name: "Ridotta", priceCents: 3500)]
            let serviceID = try repository.saveService(service)
            var session = BusinessTestStore.session(client, price: 3500)
            session.serviceID = serviceID
            session.participants[0].tariffID = service.tariffs[1].id
            _ = try repository.saveSession(session)
            let snapshot = try ArchiveSnapshot.capture(context: context)
            XCTAssertEqual(snapshot.version, 4)
            XCTAssertEqual(snapshot.business.preferences.count, 1)
            let data = try snapshot.encoded()
            let decoded = try ArchiveSnapshot.decode(data)
            let destination = directory.appendingPathComponent("restored.store")
            try decoded.restore(toNewStoreAt: destination)
            let restored = try StoreFactory.makeContainer(url: destination)
            XCTAssertEqual(try BusinessArchive.capture(context: restored.mainContext), snapshot.business)

            var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            json["version"] = 3
            var business = try XCTUnwrap(json["business"] as? [String: Any])
            business.removeValue(forKey: "preferences")
            json["business"] = business
            let oldBackup = try ArchiveSnapshot.decode(JSONSerialization.data(withJSONObject: json))
            XCTAssertTrue(oldBackup.business.preferences.isEmpty)
            XCTAssertEqual(oldBackup.business.rates, snapshot.business.rates)
            let oldDestination = directory.appendingPathComponent("restored-v3.store")
            try oldBackup.restore(toNewStoreAt: oldDestination)
            let oldRestored = try StoreFactory.makeContainer(url: oldDestination)
            XCTAssertEqual(try oldRestored.mainContext.fetchCount(FetchDescriptor<ClientAppointmentPreference>()), 0)
            let fallback = AppointmentPreferences.lastUsed(clientID: client.id,
                sessions: try oldRestored.mainContext.fetch(FetchDescriptor<TrainingSession>()),
                participants: try oldRestored.mainContext.fetch(FetchDescriptor<SessionParticipant>()), preferences: [])
            XCTAssertEqual(fallback?.priceCents, 3500)
        }
    }
}
