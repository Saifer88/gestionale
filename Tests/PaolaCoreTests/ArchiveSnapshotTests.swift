import Foundation
@testable import PaolaCore
import SwiftData
import XCTest

@MainActor
final class ArchiveSnapshotTests: XCTestCase {
    func testEncryptedCompleteArchiveRestoresClientsSessionsPackagesAndBalances() async throws {
        try withStoreFixture { directory in
            let container = try StoreFactory.makeContainer(url: directory.appendingPathComponent("source.store"))
            let context = container.mainContext
            let clientRepo = ClientRepository(context: context)
            let first = try clientRepo.save(makeDraft(firstName: "Prima", email: "prima@example.it",
                anamnesis: "Anamnesi: già valutata 🩺\n\n  Secondo paragrafo.",
                physicalAnalysis: "Mobilità\n\n第二行"))
            let second = try clientRepo.save(makeDraft(firstName: "Seconda", email: "seconda@example.it"))
            let repository = BusinessRepository(context: context)
            var service = ServiceDraft()
            service.name = "Allenamento"
            service.durationMinutes = 60
            service.priceCents = 5000
            service.tariffs = [ServiceRateDraft(name: "Ordinaria", priceCents: 5000),
                               ServiceRateDraft(name: "Ridotta", priceCents: 3500)]
            let serviceID = try repository.saveService(service)
            var package = PackageDraft()
            package.clientID = first.id
            package.priceCents = 40000
            let packageID = try repository.savePackage(package)
            var session = SessionDraft()
            session.serviceID = serviceID
            session.serviceName = service.name
            session.location = "Sede storica conservata"
            session.startDate = Date().addingTimeInterval(3600)
            session.durationMinutes = 60
            session.participants = [
                ParticipantDraft(clientID: first.id, priceCents: 5000, packageID: packageID),
                ParticipantDraft(clientID: second.id, priceCents: 5000)
            ]
            let sessionID = try BusinessTestStore.seedLegacySession(session, in: context)
            try repository.setSessionStatus(sessionID, to: .completed)
            var payment = PaymentDraft()
            payment.clientID = first.id
            payment.amountCents = 40000
            _ = try BusinessTestStore.seedLegacyPayment(payment, in: context)
            payment.clientID = second.id
            payment.amountCents = 5000
            _ = try BusinessTestStore.seedLegacyPayment(payment, in: context)
            var block = BlockDraft()
            block.title = "Pausa"
            block.startDate = session.startDate.addingTimeInterval(7200)
            block.endDate = block.startDate.addingTimeInterval(1800)
            _ = try repository.saveBlock(block)

            let captured = try ArchiveSnapshot.capture(context: context)
            XCTAssertEqual(captured.version, 6)
            XCTAssertEqual(captured.business.rates.count, 2)
            let cipher = try BackupCipher.encrypt(captured.encoded(), password: "Password-di-prova-123")
            let decoded = try ArchiveSnapshot.decode(BackupCipher.decrypt(cipher, password: "Password-di-prova-123"))
            let restoredURL = directory.appendingPathComponent("restored/Clienti-v1.store")
            try decoded.restore(toNewStoreAt: restoredURL)
            let restored = try StoreFactory.makeContainer(url: restoredURL)
            let restoredSnapshot = try ArchiveSnapshot.capture(context: restored.mainContext)
            XCTAssertEqual(captured.recordCount, restoredSnapshot.recordCount)
            XCTAssertEqual(captured.clients, restoredSnapshot.clients)
            let restoredFirst = try XCTUnwrap(restoredSnapshot.clients.first { $0.id == first.id })
            XCTAssertEqual(restoredFirst.anamnesis, first.anamnesis)
            XCTAssertEqual(restoredFirst.physicalAnalysis, first.physicalAnalysis)
            XCTAssertEqual(captured.business.rates, restoredSnapshot.business.rates)
            XCTAssertEqual(captured.business.canonicalized(), restoredSnapshot.business.canonicalized())
            XCTAssertEqual(Set(captured.clients.map(\.id)), Set(restoredSnapshot.clients.map(\.id)))
            let sessions = try restored.mainContext.fetch(FetchDescriptor<TrainingSession>())
            XCTAssertEqual(sessions.count, 1)
            XCTAssertEqual(sessions.first?.id, sessionID)
            XCTAssertEqual(sessions.first?.status, .completed)
            XCTAssertEqual(sessions.first?.location, "Sede storica conservata")
            let entries = try restored.mainContext.fetch(FetchDescriptor<LedgerEntry>())
            XCTAssertEqual(BusinessReports.balance(clientID: first.id, entries: entries), -40000)
            XCTAssertEqual(BusinessReports.balance(clientID: second.id, entries: entries), -5000)
            let restoredPackage = try XCTUnwrap(restored.mainContext.fetch(FetchDescriptor<LessonPackage>()).first)
            let uses = try restored.mainContext.fetch(FetchDescriptor<PackageUse>())
            XCTAssertEqual(BusinessReports.remaining(package: restoredPackage, uses: uses), 9)
            XCTAssertEqual(try restored.mainContext.fetchCount(FetchDescriptor<Unavailability>()), 1)
            XCTAssertThrowsError(try decoded.restore(toNewStoreAt: restoredURL))
            XCTAssertEqual(try restored.mainContext.fetchCount(FetchDescriptor<Client>()), 2)
        }
    }

    func testInvalidBackupReferencesAreRejectedBeforeCreatingStore() async throws {
        try withStoreFixture { directory in
            let container = try StoreFactory.makeContainer(inMemory: true)
            let client = try ClientRepository(context: container.mainContext).save(makeDraft())
            var payment = PaymentDraft()
            payment.clientID = client.id
            payment.amountCents = 1000
            _ = try BusinessTestStore.seedLegacyPayment(payment, in: container.mainContext)
            var snapshot = try ArchiveSnapshot.capture(context: container.mainContext)
            snapshot.clients.removeAll()
            let destination = directory.appendingPathComponent("must-not-exist.store")
            XCTAssertThrowsError(try snapshot.restore(toNewStoreAt: destination))
            XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        }
    }

    func testUnsupportedVersionAndDuplicateClientsAreRejected() async throws {
        let container = try StoreFactory.makeContainer(inMemory: true)
        _ = try ClientRepository(context: container.mainContext).save(makeDraft())
        var snapshot = try ArchiveSnapshot.capture(context: container.mainContext)
        snapshot.version = 99
        XCTAssertThrowsError(try snapshot.validate())
        snapshot.version = 2
        snapshot.clients.append(try XCTUnwrap(snapshot.clients.first))
        XCTAssertThrowsError(try snapshot.validate())
    }

    func testMissingSelectedRestoreDoesNotSilentlyCreateAnEmptyArchive() async throws {
        try withStoreFixture { directory in
            XCTAssertEqual(try StoreFactory.selectedStoreURL(in: directory, relativePath: nil),
                           directory.appendingPathComponent("Clienti-v1.store"))
            XCTAssertThrowsError(try StoreFactory.selectedStoreURL(
                in: directory, relativePath: "Restored/missing/Clienti-v1.store"
            ))
            XCTAssertThrowsError(try StoreFactory.selectedStoreURL(
                in: directory, relativePath: "Restored/../Clienti-v1.store"
            ))
            let relative = "Restored/example/Clienti-v1.store"
            let url = directory.appendingPathComponent(relative)
            _ = try StoreFactory.makeContainer(url: url)
            XCTAssertEqual(try StoreFactory.selectedStoreURL(in: directory, relativePath: relative), url)
        }
    }
}
