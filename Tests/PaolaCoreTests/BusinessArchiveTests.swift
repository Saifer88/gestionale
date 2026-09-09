import Foundation
@testable import PaolaCore
import SwiftData
import XCTest

@MainActor
final class BusinessArchiveTests: XCTestCase {
    private func fixture() throws -> (ModelContainer, Client, BusinessArchive) {
        let store = try BusinessTestStore.make()
        let context = store.mainContext
        let client = try BusinessTestStore.addClient(context)
        let repo = BusinessRepository(context: context)
        var service = ServiceDraft(); service.name = "Individuale"; service.priceCents = 6000
        let serviceID = try repo.saveService(service)
        var package = BusinessTestStore.package(client)
        package.capacity = 5
        let packageID = try repo.savePackage(package)
        var lesson = BusinessTestStore.session(client, packageID: packageID)
        lesson.serviceID = serviceID
        try repo.setSessionStatus(repo.saveSession(lesson), to: .completed)
        try repo.setSessionStatus(repo.saveSession(BusinessTestStore.session(client, day: 2)), to: .completed)
        let paymentID = try BusinessTestStore.seedLegacyPayment(BusinessTestStore.payment(client, amount: 25000, day: 3), in: context)
        try repo.recordRefund(paymentID: paymentID, amountCents: 1000,
                              date: BusinessTestStore.date.addingTimeInterval(4 * 86400), notes: "Reso")
        let charge = try XCTUnwrap(context.fetch(FetchDescriptor<LedgerEntry>()).first { $0.sourceKey == packageID.uuidString.lowercased() })
        try repo.recordCredit(chargeID: charge.id, amountCents: 2000,
                             date: BusinessTestStore.date.addingTimeInterval(4 * 86400), notes: "Sconto")
        var block = BlockDraft()
        block.title = "Ferie"; block.startDate = BusinessTestStore.date.addingTimeInterval(20 * 86400)
        block.endDate = block.startDate.addingTimeInterval(86400)
        try repo.saveBlock(block)
        return (store, client, try BusinessArchive.capture(context: context))
    }

    func testJSONRoundTripPreservesAllRecordsIDsMetadataAndInsertDoesNotSave() async throws {
        let (source, client, original) = try fixture()
        _ = source
        XCTAssertEqual(original.recordCount, 17)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(BusinessArchive.self, from: data)
        try decoded.validate(clientIDs: [client.id])
        let destination = try BusinessTestStore.make()
        let context = destination.mainContext
        context.autosaveEnabled = false
        context.insert(Client(id: client.id, firstName: client.firstName, lastName: client.lastName))
        try context.save()
        try decoded.insert(into: context)
        XCTAssertTrue(context.hasChanges)
        XCTAssertEqual(try ModelContext(destination).fetchCount(FetchDescriptor<LedgerEntry>()), 0)
        try context.save()
        let restored = try BusinessArchive.capture(context: ModelContext(destination))
        XCTAssertEqual(restored, original.canonicalized())
        XCTAssertEqual(restored.services.sorted { $0.id.uuidString < $1.id.uuidString },
                       original.services.sorted { $0.id.uuidString < $1.id.uuidString })
        XCTAssertEqual(restored.sessions.sorted { $0.id.uuidString < $1.id.uuidString },
                       original.sessions.sorted { $0.id.uuidString < $1.id.uuidString })
        XCTAssertEqual(restored.participants.sorted { $0.id.uuidString < $1.id.uuidString },
                       original.participants.sorted { $0.id.uuidString < $1.id.uuidString })
        XCTAssertEqual(restored.packages, original.packages)
        XCTAssertEqual(restored.packages.first?.capacity, 5)
        XCTAssertEqual(restored.packageUses, original.packageUses)
        XCTAssertEqual(restored.ledgerEntries.sorted { $0.id.uuidString < $1.id.uuidString },
                       original.ledgerEntries.sorted { $0.id.uuidString < $1.id.uuidString })
        XCTAssertEqual(restored.blocks, original.blocks)
        XCTAssertThrowsError(try decoded.insert(into: context))
        XCTAssertFalse(context.hasChanges)
    }

    func testCanonicalizationIgnoresOrderButEqualityDetectsMetadataChanges() async throws {
        let (store, _, archive) = try fixture()
        _ = store
        var reordered = archive
        reordered.services.reverse(); reordered.sessions.reverse(); reordered.participants.reverse()
        reordered.packages.reverse(); reordered.packageUses.reverse()
        reordered.ledgerEntries.reverse(); reordered.blocks.reverse()
        XCTAssertEqual(reordered.canonicalized(), archive)
        XCTAssertEqual(archive.canonicalized().canonicalized(), archive)
        var changed = reordered.canonicalized()
        changed.sessions[0].notes += "modificata"
        XCTAssertNotEqual(changed, archive)
        changed = archive
        changed.ledgerEntries[0].createdAt = changed.ledgerEntries[0].createdAt.addingTimeInterval(0.001)
        XCTAssertNotEqual(changed, archive)
    }

    func testArchiveRejectsInvalidReferencesIDsEnumsMoneyDatesAndPairSize() async throws {
        let (store, client, archive) = try fixture()
        _ = store
        let mutations: [(inout BusinessArchive) -> Void] = [
            { $0.services.append($0.services[0]) },
            { $0.sessions[0].statusRaw = "invalid" },
            { $0.sessions[0].serviceID = UUID() },
            { $0.sessions[0].durationMinutes = 0 },
            { $0.sessions[0].startDate = Date(timeIntervalSinceReferenceDate: .infinity) },
            { $0.participants[0].clientID = UUID() },
            { $0.participants[0].sessionID = UUID() },
            { $0.participants[0].packageID = UUID() },
            { $0.participants[0].priceCents = -1 },
            { var p = $0.participants[0]; p.id = UUID(); $0.participants.append(p) },
            { $0.packages[0].capacity = 0 },
            { $0.packageUses[0].sourceKey = "bad" },
            { $0.packageUses[0].packageID = UUID() },
            { $0.ledgerEntries[0].amountCents = -1 },
            { $0.ledgerEntries[0].kindRaw = "invalid" },
            { $0.ledgerEntries[0].methodRaw = "invalid" },
            { $0.ledgerEntries[0].sourceKey = "" },
            { $0.ledgerEntries[0].originalEntryID = UUID() },
            { $0.ledgerEntries.removeAll { $0.kindRaw == "charge" } },
            { $0.blocks[0].endDate = $0.blocks[0].startDate },
            { $0.blocks[0].title = " " }
        ]
        for (index, mutate) in mutations.enumerated() {
            var invalid = archive
            mutate(&invalid)
            XCTAssertThrowsError(try invalid.validate(clientIDs: [client.id]), "mutation \(index)")
        }
        XCTAssertThrowsError(try archive.validate(clientIDs: []))
    }

    func testDuplicateLogicalSourcesAreDeduplicatedButConflictsAndOverRefundAreRejected() async throws {
        let (store, client, archive) = try fixture()
        _ = store
        var duplicate = archive
        var use = duplicate.packageUses[0]
        use.id = UUID()
        duplicate.packageUses.append(use)
        var charge = try XCTUnwrap(duplicate.ledgerEntries.first { $0.kindRaw == "charge" })
        charge.id = UUID()
        duplicate.ledgerEntries.append(charge)
        try duplicate.validate(clientIDs: [client.id])
        duplicate.ledgerEntries[duplicate.ledgerEntries.count - 1].amountCents += 1
        XCTAssertThrowsError(try duplicate.validate(clientIDs: [client.id]))
        var overRefund = archive
        let index = try XCTUnwrap(overRefund.ledgerEntries.firstIndex { $0.kindRaw == "refund" })
        overRefund.ledgerEntries[index].amountCents = 25001
        XCTAssertThrowsError(try overRefund.validate(clientIDs: [client.id]))
    }

    func testInvalidInsertNeverChangesTargetContext() async throws {
        let (store, client, archive) = try fixture()
        _ = store
        let destination = try BusinessTestStore.make()
        let context = destination.mainContext
        context.autosaveEnabled = false
        context.insert(Client(id: client.id))
        try context.save()
        var invalid = archive
        invalid.packageUses[0].clientID = UUID()
        XCTAssertThrowsError(try invalid.insert(into: context))
        XCTAssertFalse(context.hasChanges)
        XCTAssertEqual(try BusinessArchive.capture(context: context).recordCount, 0)
    }

    func testArchiveRejectsElevenDistinctPackageUses() async throws {
        let (store, client, original) = try fixture()
        _ = store
        var archive = original
        let package = archive.packages[0]
        for day in 30...39 {
            let session = TrainingSession(startDate: BusinessTestStore.date.addingTimeInterval(Double(day) * 86400),
                                          status: .completed)
            let participant = SessionParticipant(sessionID: session.id, clientID: client.id, packageID: package.id)
            let use = PackageUse(packageID: package.id, sessionID: session.id, clientID: client.id,
                sourceKey: BusinessRules.sessionSource(sessionID: session.id, clientID: client.id))
            archive.sessions.append(BusinessArchive.SessionRecord(session))
            archive.participants.append(BusinessArchive.ParticipantRecord(participant))
            archive.packageUses.append(BusinessArchive.PackageUseRecord(use))
        }
        XCTAssertEqual(archive.packageUses.count, 11)
        XCTAssertThrowsError(try archive.validate(clientIDs: [client.id]))
    }

    func testConflictingSourceInStorePreventsAnyRepositoryWrite() async throws {
        let (store, client, archive) = try fixture()
        let context = store.mainContext
        let original = try XCTUnwrap(archive.ledgerEntries.first { $0.kindRaw == "charge" })
        var duplicate = original
        duplicate.id = UUID(); duplicate.amountCents += 1
        context.insert(duplicate.model())
        try context.save()
        let initialCount = try context.fetchCount(FetchDescriptor<LedgerEntry>())
        XCTAssertThrowsError(try BusinessRepository(context: context).savePackage(
            BusinessTestStore.package(client, price: 100))) {
            guard case BusinessError.inconsistentData = $0 else { return XCTFail("\($0)") }
        }
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<LedgerEntry>()), initialCount)
        XCTAssertFalse(context.hasChanges)
    }

    func testRealReadOnlySaveFailureLeavesUIAndDiskUnchanged() async throws {
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".business-store-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("business.store")
        let schema = BusinessTestStore.schema
        let writable = try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        ])
        let client = try BusinessTestStore.addClient(writable.mainContext)
        let sessionID = try BusinessRepository(context: writable.mainContext).saveSession(BusinessTestStore.session(client))
        let readonly = try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, url: url, allowsSave: false, cloudKitDatabase: .none)
        ])
        let context = readonly.mainContext
        let observed = try XCTUnwrap(context.fetch(FetchDescriptor<TrainingSession>()).first)
        let before = try BusinessArchive.capture(context: context)
        XCTAssertThrowsError(try BusinessRepository(context: context).setSessionStatus(sessionID, to: .completed)) {
            XCTAssertFalse($0 is ClientPersistenceError, "The original save failure must not be masked as a refresh error.")
        }
        XCTAssertEqual(observed.status, .planned)
        let repository = BusinessRepository(context: context)
        XCTAssertThrowsError(try repository.savePackage(BusinessTestStore.package(client))) {
            XCTAssertFalse($0 is ClientPersistenceError)
        }
        var edit = SessionDraft(observed, participants: try context.fetch(FetchDescriptor<SessionParticipant>()))
        edit.durationMinutes = 45
        XCTAssertThrowsError(try repository.saveSession(edit)) { XCTAssertFalse($0 is ClientPersistenceError) }
        XCTAssertEqual(try BusinessArchive.capture(context: context), before)
        XCTAssertEqual(try BusinessArchive.capture(context: ModelContext(writable)), before)
        XCTAssertFalse(context.hasChanges)
        XCTAssertTrue(try context.fetch(FetchDescriptor<LedgerEntry>()).isEmpty)
        let reader = ModelContext(writable)
        XCTAssertEqual(try reader.fetch(FetchDescriptor<TrainingSession>()).first?.status, .planned)
        XCTAssertEqual(try reader.fetchCount(FetchDescriptor<LedgerEntry>()), 0)
    }
}
