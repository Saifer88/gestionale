import Foundation
@testable import PaolaCore
import SwiftData
import XCTest

@MainActor
final class ArchiveV3Tests: XCTestCase {
    private let legacyV2 = Data(#"""
    {
      "version": 2,
      "createdAt": 12345,
      "clients": [{
        "id": "00000000-0000-0000-0000-000000000001",
        "firstName": "María", "lastName": "De Rossi", "phone": "+39 333 1234567",
        "email": "maria@example.it", "notes": "Nota storica\n\n第二行",
        "joinedOn": 1234, "createdAt": 5678, "updatedAt": 9012, "isArchived": true
      }],
      "business": {
        "services": [{
          "id": "00000000-0000-0000-0000-000000000002",
          "name": "Individuale", "durationMinutes": 45, "priceCents": 4321,
          "isActive": false, "updatedAt": 6789
        }],
        "sessions": [{
          "id": "00000000-0000-0000-0000-000000000003",
          "startDate": 10000, "durationMinutes": 45,
          "serviceID": "00000000-0000-0000-0000-000000000002",
          "serviceName": "Nome storico", "location": "Sede storica",
          "notes": "Nota lezione\nSeconda riga", "statusRaw": "completed",
          "createdAt": 6000, "updatedAt": 10001
        }],
        "participants": [{
          "id": "00000000-0000-0000-0000-000000000004",
          "sessionID": "00000000-0000-0000-0000-000000000003",
          "clientID": "00000000-0000-0000-0000-000000000001",
          "clientName": "María De Rossi", "priceCents": 3210
        }],
        "packages": [], "packageUses": [],
        "ledgerEntries": [{
          "id": "00000000-0000-0000-0000-000000000005",
          "clientID": "00000000-0000-0000-0000-000000000001",
          "clientName": "María De Rossi", "date": 10000, "createdAt": 10001,
          "kindRaw": "charge", "amountCents": 3210, "methodRaw": "other",
          "notes": "Nome storico",
          "sourceKey": "00000000-0000-0000-0000-000000000003:00000000-0000-0000-0000-000000000001"
        }],
        "blocks": [{
          "id": "00000000-0000-0000-0000-000000000006",
          "startDate": 20000, "endDate": 30000, "title": "Pausa"
        }]
      }
    }
    """#.utf8)

    func testVersionTwoJSONMissingFieldsAndRatesRoundTripsAndRestoresEveryLegacyValue() async throws {
        try withStoreFixture { directory in
            let decoded = try ArchiveSnapshot.decode(legacyV2)
            XCTAssertEqual(decoded.version, 2)
            XCTAssertEqual(decoded.createdAt, Date(timeIntervalSinceReferenceDate: 12345))
            XCTAssertEqual(decoded.recordCount, 6)
            let client = try XCTUnwrap(decoded.clients.first)
            XCTAssertEqual(client.anamnesis, "")
            XCTAssertEqual(client.physicalAnalysis, "")
            XCTAssertEqual(client.firstName, "María")
            XCTAssertEqual(client.lastName, "De Rossi")
            XCTAssertEqual(client.phone, "+39 333 1234567")
            XCTAssertEqual(client.email, "maria@example.it")
            XCTAssertEqual(client.notes, "Nota storica\n\n第二行")
            XCTAssertEqual(client.joinedOn, Date(timeIntervalSinceReferenceDate: 1234))
            XCTAssertEqual(client.createdAt, Date(timeIntervalSinceReferenceDate: 5678))
            XCTAssertEqual(client.updatedAt, Date(timeIntervalSinceReferenceDate: 9012))
            XCTAssertTrue(client.isArchived)
            XCTAssertTrue(decoded.business.rates.isEmpty)
            let roundTrip = try ArchiveSnapshot.decode(decoded.encoded())
            XCTAssertEqual(roundTrip.clients, decoded.clients)
            XCTAssertEqual(roundTrip.business, decoded.business)
            XCTAssertEqual(roundTrip.version, 2)
            XCTAssertEqual(roundTrip.createdAt, decoded.createdAt)
            let url = directory.appendingPathComponent("restored.store")
            try roundTrip.restore(toNewStoreAt: url)
            let restored = try StoreFactory.makeContainer(url: url)
            let captured = try ArchiveSnapshot.capture(context: restored.mainContext)
            XCTAssertEqual(captured.version, 5)
            XCTAssertEqual(captured.clients, decoded.clients)
            XCTAssertEqual(captured.business, decoded.business.canonicalized())
            let service = try XCTUnwrap(restored.mainContext.fetch(FetchDescriptor<TrainingService>()).first)
            XCTAssertEqual(ServiceTariffs.options(for: service,
                rates: try restored.mainContext.fetch(FetchDescriptor<ServiceRate>())),
                [ServiceRateDraft(id: service.id, priceCents: 4321)])
            XCTAssertEqual(captured.business.sessions.first?.location, "Sede storica")
            XCTAssertEqual(captured.business.ledgerEntries.first?.amountCents, 3210)
        }
    }

    func testMalformedNewFieldsAreNotSilentlyDiscardedAndNullLegacyFieldsDefaultEmpty() async throws {
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: legacyV2) as? [String: Any])
        var clients = try XCTUnwrap(json["clients"] as? [[String: Any]])
        clients[0]["anamnesis"] = NSNull()
        clients[0]["physicalAnalysis"] = NSNull()
        json["clients"] = clients
        var business = try XCTUnwrap(json["business"] as? [String: Any])
        business["rates"] = NSNull()
        json["business"] = business
        let decoded = try ArchiveSnapshot.decode(JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(decoded.clients[0].anamnesis, "")
        XCTAssertEqual(decoded.clients[0].physicalAnalysis, "")
        XCTAssertTrue(decoded.business.rates.isEmpty)
        for field in ["anamnesis", "physicalAnalysis"] {
            var invalid = clients
            invalid[0][field] = 123
            json["clients"] = invalid
            XCTAssertThrowsError(try ArchiveSnapshot.decode(JSONSerialization.data(withJSONObject: json)))
        }
        json["clients"] = clients
        business["rates"] = "invalid"
        json["business"] = business
        XCTAssertThrowsError(try ArchiveSnapshot.decode(JSONSerialization.data(withJSONObject: json)))
    }

    func testInvalidTariffArchiveNeverCreatesDestinationAndCanonicalEqualityIncludesRates() async throws {
        try withStoreFixture { directory in
            let store = try StoreFactory.makeContainer(inMemory: true)
            var service = ServiceDraft()
            service.name = "Individuale"
            service.tariffs = [ServiceRateDraft(name: "Base", priceCents: 5000),
                               ServiceRateDraft(name: "Ridotta", priceCents: 3000)]
            try BusinessRepository(context: store.mainContext).saveService(service)
            let original = try ArchiveSnapshot.capture(context: store.mainContext)
            var reordered = original.business
            reordered.rates.reverse()
            XCTAssertEqual(reordered.canonicalized(), original.business)
            let mutations: [(inout BusinessArchive) -> Void] = [
                { $0.rates[0].serviceID = UUID() },
                { $0.rates[0].priceCents = -1 },
                { $0.rates[0].name = " \n\t " },
                { $0.rates[1].name = $0.rates[0].name.uppercased() },
                { $0.rates[0].sortOrder = -1 },
                { $0.rates.append($0.rates[0]) }
            ]
            for (index, mutation) in mutations.enumerated() {
                var invalid = original
                mutation(&invalid.business)
                XCTAssertNotEqual(invalid.business.canonicalized(), original.business)
                let url = directory.appendingPathComponent("invalid-\(index)/store")
                XCTAssertThrowsError(try invalid.validate())
                XCTAssertThrowsError(try invalid.restore(toNewStoreAt: url))
                XCTAssertFalse(FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path))
                XCTAssertEqual(try BusinessArchive.capture(context: store.mainContext), original.business)
            }
            let destination = try BusinessTestStore.make()
            var invalid = original.business
            invalid.rates[0].serviceID = UUID()
            XCTAssertThrowsError(try invalid.insert(into: destination.mainContext))
            XCTAssertFalse(destination.mainContext.hasChanges)
            XCTAssertEqual(try destination.mainContext.fetchCount(FetchDescriptor<ServiceRate>()), 0)
            let rate = try XCTUnwrap(store.mainContext.fetch(FetchDescriptor<ServiceRate>()).first)
            rate.serviceID = UUID()
            try store.mainContext.save()
            let corrupted = try BusinessArchive.capture(context: store.mainContext)
            XCTAssertThrowsError(try BusinessRepository(context: store.mainContext).saveService(service))
            XCTAssertEqual(try BusinessArchive.capture(context: store.mainContext), corrupted)
            XCTAssertFalse(store.mainContext.hasChanges)
        }
    }
}
