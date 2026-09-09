import Foundation
@testable import PaolaCore
import SwiftData
import XCTest

@MainActor
final class SchemaUpgradeTests: XCTestCase {
    func testVersionOneClientMigratesWithoutLosingData() async throws {
        try withStoreFixture { directory in
            let url = directory.appendingPathComponent("Clienti-v1.store")
            let id = UUID()
            let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
            try autoreleasepool {
                let schema = Schema(versionedSchema: PaolaSchemaV1.self)
                let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
                let old = try ModelContainer(for: schema, configurations: [configuration])
                let client = PaolaSchemaV1.Client(id: id, firstName: "Maria", lastName: "Rossi",
                                    phone: "3331234567", email: "maria@example.it",
                                    notes: "Nota precedente", createdAt: timestamp,
                                    updatedAt: timestamp.addingTimeInterval(100), isArchived: true)
                client.joinedOn = timestamp.addingTimeInterval(-1000)
                old.mainContext.insert(client)
                try old.mainContext.save()
            }
            let upgraded = try StoreFactory.makeContainer(url: url)
            let clients = try upgraded.mainContext.fetch(FetchDescriptor<Client>())
            XCTAssertEqual(clients.count, 1)
            let client = try XCTUnwrap(clients.first)
            XCTAssertEqual(client.id, id)
            XCTAssertEqual(client.createdAt, timestamp)
            XCTAssertEqual(client.updatedAt, timestamp.addingTimeInterval(100))
            XCTAssertEqual(client.joinedOn, timestamp.addingTimeInterval(-1000))
            XCTAssertEqual(client.firstName, "Maria")
            XCTAssertEqual(client.lastName, "Rossi")
            XCTAssertEqual(client.email, "maria@example.it")
            XCTAssertEqual(client.phone, "3331234567")
            XCTAssertEqual(client.notes, "Nota precedente")
            XCTAssertEqual(client.anamnesis, "")
            XCTAssertEqual(client.physicalAnalysis, "")
            XCTAssertTrue(client.isArchived)
            XCTAssertEqual(try upgraded.mainContext.fetchCount(FetchDescriptor<TrainingSession>()), 0)
            XCTAssertEqual(try upgraded.mainContext.fetchCount(FetchDescriptor<LedgerEntry>()), 0)
            XCTAssertEqual(try upgraded.mainContext.fetchCount(FetchDescriptor<LessonPackage>()), 0)
            XCTAssertEqual(try upgraded.mainContext.fetchCount(FetchDescriptor<ServiceRate>()), 0)
        }
    }

    func testVersionTwoModelsKeepCloudCompatibleDefaults() async throws {
        let schema = Schema(versionedSchema: PaolaSchemaV2.self)
        XCTAssertEqual(schema.entities.count, 8)
        for entity in schema.entities {
            for attribute in entity.attributes {
                XCTAssertFalse(attribute.isUnique, "\(entity.name).\(attribute.name)")
                XCTAssertTrue(attribute.isOptional || attribute.defaultValue != nil, "\(entity.name).\(attribute.name)")
            }
        }
        let client = try XCTUnwrap(schema.entities.first { $0.name == "Client" })
        XCTAssertFalse(client.attributes.contains { $0.name == "anamnesis" || $0.name == "physicalAnalysis" })
        XCTAssertTrue(PaolaSchemaV2.models.contains { $0 == PaolaSchemaV1.Client.self })
    }

    func testVersionTwoMigratesAllRecordsMetadataAndMoneyToVersionThree() async throws {
        try withStoreFixture { directory in
            let url = directory.appendingPathComponent("v2.store")
            let clientID = UUID()
            let timestamp = BusinessTestStore.date
            let expected = try autoreleasepool { () -> BusinessArchive in
                let schema = Schema(versionedSchema: PaolaSchemaV2.self)
                let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
                let old = try ModelContainer(for: schema, configurations: [configuration])
                let context = old.mainContext
                context.autosaveEnabled = false
                let client = PaolaSchemaV1.Client(id: clientID, firstName: "María", lastName: "De Rossi",
                    phone: "+39 333 1234567", email: "maria@example.it", notes: "Vecchia nota\n第二行",
                    createdAt: timestamp, updatedAt: timestamp.addingTimeInterval(123), isArchived: true)
                client.joinedOn = timestamp.addingTimeInterval(-12345)
                let service = TrainingService(name: "Individuale", durationMinutes: 45,
                    priceCents: 4321, isActive: false, updatedAt: timestamp)
                let package = LessonPackage(clientID: clientID, clientName: client.fullName,
                    purchasedOn: timestamp, priceCents: 40000,
                    expiresOn: timestamp.addingTimeInterval(30 * 86400), notes: "Pacchetto storico")
                let cashSession = TrainingSession(startDate: timestamp.addingTimeInterval(86400),
                    durationMinutes: 45, serviceID: service.id, serviceName: "Nome storico",
                    location: "Sede storica", notes: "Nota lezione\nSeconda riga", status: .completed,
                    createdAt: timestamp, updatedAt: timestamp.addingTimeInterval(100))
                let packageSession = TrainingSession(startDate: timestamp.addingTimeInterval(2 * 86400),
                    serviceID: service.id, serviceName: service.name, status: .completed,
                    createdAt: timestamp, updatedAt: timestamp.addingTimeInterval(200))
                let cashParticipant = SessionParticipant(sessionID: cashSession.id, clientID: clientID,
                    clientName: client.fullName, priceCents: 3210)
                let packageParticipant = SessionParticipant(sessionID: packageSession.id, clientID: clientID,
                    clientName: client.fullName, priceCents: 3000, packageID: package.id)
                let use = PackageUse(packageID: package.id, sessionID: packageSession.id,
                    clientID: clientID, createdAt: timestamp.addingTimeInterval(300),
                    sourceKey: BusinessRules.sessionSource(sessionID: packageSession.id, clientID: clientID))
                let packageCharge = LedgerEntry(clientID: clientID, clientName: client.fullName,
                    date: package.purchasedOn, createdAt: timestamp, amountCents: package.priceCents,
                    notes: "Acquisto", sourceKey: BusinessRules.packageSource(package.id))
                let sessionCharge = LedgerEntry(clientID: clientID, clientName: client.fullName,
                    date: cashSession.startDate, createdAt: timestamp, amountCents: cashParticipant.priceCents,
                    notes: cashSession.serviceName,
                    sourceKey: BusinessRules.sessionSource(sessionID: cashSession.id, clientID: clientID))
                let payment = LedgerEntry(clientID: clientID, clientName: client.fullName,
                    date: timestamp, createdAt: timestamp, kind: .payment, amountCents: 50000,
                    method: .bankTransfer, notes: "Bonifico", sourceKey: "payment:legacy")
                let refund = LedgerEntry(clientID: clientID, clientName: client.fullName,
                    date: timestamp.addingTimeInterval(3 * 86400), createdAt: timestamp,
                    kind: .refund, amountCents: 1000, method: .bankTransfer,
                    notes: "Rimborso", sourceKey: "refund:legacy", originalEntryID: payment.id)
                let block = Unavailability(startDate: timestamp.addingTimeInterval(10 * 86400),
                    endDate: timestamp.addingTimeInterval(11 * 86400), title: "Ferie")
                context.insert(client); context.insert(service); context.insert(package)
                context.insert(cashSession); context.insert(packageSession)
                context.insert(cashParticipant); context.insert(packageParticipant); context.insert(use)
                for entry in [packageCharge, sessionCharge, payment, refund] { context.insert(entry) }
                context.insert(block)
                try context.save()

                var archive = BusinessArchive()
                archive.services = [BusinessArchive.ServiceRecord(service)]
                archive.sessions = [cashSession, packageSession].map(BusinessArchive.SessionRecord.init)
                archive.participants = [cashParticipant, packageParticipant].map(BusinessArchive.ParticipantRecord.init)
                archive.packages = [BusinessArchive.PackageRecord(package)]
                archive.packageUses = [BusinessArchive.PackageUseRecord(use)]
                archive.ledgerEntries = [packageCharge, sessionCharge, payment, refund].map(BusinessArchive.LedgerRecord.init)
                archive.blocks = [BusinessArchive.BlockRecord(block)]
                try archive.validate(clientIDs: [clientID])
                return archive.canonicalized()
            }
            try autoreleasepool {
                let upgraded = try StoreFactory.makeContainer(url: url)
                let context = upgraded.mainContext
                let client = try XCTUnwrap(context.fetch(FetchDescriptor<Client>()).first)
                XCTAssertEqual(try context.fetchCount(FetchDescriptor<Client>()), 1)
                XCTAssertEqual(client.id, clientID)
                XCTAssertEqual(client.firstName, "María")
                XCTAssertEqual(client.lastName, "De Rossi")
                XCTAssertEqual(client.phone, "+39 333 1234567")
                XCTAssertEqual(client.email, "maria@example.it")
                XCTAssertEqual(client.notes, "Vecchia nota\n第二行")
                XCTAssertEqual(client.createdAt, timestamp)
                XCTAssertEqual(client.updatedAt, timestamp.addingTimeInterval(123))
                XCTAssertEqual(client.joinedOn, timestamp.addingTimeInterval(-12345))
                XCTAssertTrue(client.isArchived)
                XCTAssertEqual(client.anamnesis, "")
                XCTAssertEqual(client.physicalAnalysis, "")
                XCTAssertEqual(try BusinessArchive.capture(context: context), expected)
                let service = try XCTUnwrap(context.fetch(FetchDescriptor<TrainingService>()).first)
                XCTAssertEqual(ServiceTariffs.options(for: service, rates: []),
                               [ServiceRateDraft(id: service.id, priceCents: 4321)])
                XCTAssertEqual(BusinessReports.balance(clientID: clientID,
                    entries: try context.fetch(FetchDescriptor<LedgerEntry>())), -5790)
                var draft = ClientDraft(client: client)
                draft.anamnesis = "Nuova anamnesi"
                draft.physicalAnalysis = "Nuova analisi"
                try ClientRepository(context: context).save(draft, updating: client)
            }
            let reopened = try StoreFactory.makeContainer(url: url)
            XCTAssertEqual(try BusinessArchive.capture(context: reopened.mainContext), expected)
            let client = try XCTUnwrap(reopened.mainContext.fetch(FetchDescriptor<Client>()).first)
            XCTAssertEqual(client.anamnesis, "Nuova anamnesi")
            XCTAssertEqual(client.physicalAnalysis, "Nuova analisi")
        }
    }

    func testVersionThreeModelsKeepCloudCompatibleDefaults() async throws {
        let schema = Schema(versionedSchema: PaolaSchemaV3.self)
        XCTAssertEqual(schema.version, Schema.Version(3, 0, 0))
        XCTAssertEqual(schema.entities.count, 9)
        for entity in schema.entities {
            XCTAssertTrue(entity.relationships.isEmpty)
            for attribute in entity.attributes {
                XCTAssertFalse(attribute.isUnique, "\(entity.name).\(attribute.name)")
                XCTAssertTrue(attribute.isOptional || attribute.defaultValue != nil,
                              "\(entity.name).\(attribute.name)")
            }
        }
        let client = try XCTUnwrap(schema.entities.first { $0.name == "Client" })
        XCTAssertEqual(Set(client.attributes.map(\.name)),
            ["id", "firstName", "lastName", "phone", "email", "notes", "anamnesis", "physicalAnalysis",
             "joinedOn", "createdAt", "updatedAt", "isArchived"])
        let rate = try XCTUnwrap(schema.entities.first { $0.name == "ServiceRate" })
        XCTAssertEqual(Set(rate.attributes.map(\.name)), ["id", "serviceID", "name", "priceCents", "sortOrder"])
    }
}
