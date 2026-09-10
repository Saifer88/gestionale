import Foundation
@testable import PaolaCore
import SwiftData
import XCTest

@MainActor
final class ServiceTariffsTests: XCTestCase {
    func testLegacyFallbackAndDeterministicOrderingFilterOtherServices() async throws {
        let service = TrainingService(name: "Individuale", priceCents: 4567)
        let other = ServiceRate(name: "Altro", priceCents: 999)
        let fallback = [ServiceRateDraft(id: service.id, name: "Standard", priceCents: 4567)]
        XCTAssertEqual(ServiceTariffs.options(for: service, rates: []), fallback)
        XCTAssertEqual(ServiceTariffs.options(for: service, rates: [other]), fallback)
        let first = ServiceRate(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            serviceID: service.id, name: "Prima", priceCents: 1234, sortOrder: 1)
        let tie = ServiceRate(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            serviceID: service.id, name: "Seconda", priceCents: 4321, sortOrder: 1)
        let priority = ServiceRate(serviceID: service.id, name: "Iniziale", priceCents: 3000, sortOrder: 0)
        let expected = [
            ServiceRateDraft(id: priority.id, name: priority.name, priceCents: priority.priceCents),
            ServiceRateDraft(id: first.id, name: first.name, priceCents: first.priceCents),
            ServiceRateDraft(id: tie.id, name: tie.name, priceCents: tie.priceCents)
        ]
        XCTAssertEqual(ServiceTariffs.options(for: service, rates: [tie, other, first, priority]), expected)
        XCTAssertEqual(ServiceTariffs.options(for: service, rates: [priority, first, other, tie]), expected)
        XCTAssertEqual(ServiceDraft(service, rates: [tie, priority, first]).tariffs, expected)
        XCTAssertTrue(ServiceDraft(service).tariffs.isEmpty)
        XCTAssertEqual(ServiceRateDraft().name, "Standard")
        XCTAssertEqual(ServiceRate().sortOrder, 0)
    }

    func testMultipleRatesAddRemoveReorderAndUpdatePersistWithoutChangingBookedPrices() async throws {
        try withStoreFixture { directory in
            let url = directory.appendingPathComponent("rates.store")
            let store = try StoreFactory.makeContainer(url: url)
            let context = store.mainContext
            let client = try BusinessTestStore.addClient(context)
            let repository = BusinessRepository(context: context)
            var draft = ServiceDraft()
            draft.name = "  Individuale  "
            draft.priceCents = 9999
            let standard = ServiceRateDraft(name: "  Standard  ", priceCents: 5500)
            let reduced = ServiceRateDraft(name: "Ridotta", priceCents: 3500)
            draft.tariffs = [standard, reduced]
            let serviceID = try repository.saveService(draft)
            let observed = try XCTUnwrap(context.fetch(FetchDescriptor<TrainingService>()).first)
            let observedRate = try XCTUnwrap(context.fetch(FetchDescriptor<ServiceRate>()).first { $0.id == standard.id })
            let persistentRateID = observedRate.persistentModelID
            XCTAssertEqual(observed.name, "Individuale")
            XCTAssertEqual(observed.priceCents, 5500)
            XCTAssertEqual(observedRate.name, "Standard")
            XCTAssertEqual(observedRate.sortOrder, 0)
            var completed = BusinessTestStore.session(client, price: reduced.priceCents)
            completed.serviceID = serviceID
            let completedID = try repository.saveSession(completed)
            try repository.setSessionStatus(completedID, to: .completed)
            var planned = BusinessTestStore.session(client, day: 2, price: standard.priceCents)
            planned.serviceID = serviceID
            let plannedID = try repository.saveSession(planned)
            let before = try BusinessArchive.capture(context: context)

            let added = ServiceRateDraft(name: "Promozione", priceCents: 1999)
            draft.id = serviceID
            draft.name = "Individuale aggiornato"
            draft.tariffs = [added, ServiceRateDraft(id: standard.id, name: "Ordinaria", priceCents: 6500)]
            try repository.saveService(draft)
            XCTAssertEqual(observed.priceCents, 1999)
            XCTAssertEqual(observed.name, draft.name)
            XCTAssertEqual(observedRate.priceCents, 6500)
            XCTAssertEqual(observedRate.name, "Ordinaria")
            XCTAssertEqual(observedRate.sortOrder, 1)
            XCTAssertEqual(observedRate.persistentModelID, persistentRateID)
            let after = try BusinessArchive.capture(context: context)
            XCTAssertEqual(after.sessions, before.sessions)
            XCTAssertEqual(after.participants, before.participants)
            XCTAssertEqual(after.ledgerEntries, before.ledgerEntries)
            XCTAssertEqual(Set(after.rates.map(\.id)), [standard.id, added.id])
            XCTAssertFalse(after.rates.contains { $0.id == reduced.id })
            XCTAssertFalse(context.hasChanges)
            var invalidEdit = completed
            invalidEdit.id = completedID
            invalidEdit.participants[0].priceCents = 1
            XCTAssertThrowsError(try repository.saveSession(invalidEdit))
            XCTAssertThrowsError(try repository.setSessionStatus(completedID, to: .planned))

            let reopened = try StoreFactory.makeContainer(url: url)
            let storedService = try XCTUnwrap(reopened.mainContext.fetch(FetchDescriptor<TrainingService>()).first)
            let storedRates = try reopened.mainContext.fetch(FetchDescriptor<ServiceRate>())
            XCTAssertEqual(ServiceTariffs.options(for: storedService, rates: storedRates), draft.tariffs)
            XCTAssertEqual(storedService.priceCents, 1999)
            XCTAssertEqual(try BusinessArchive.capture(context: reopened.mainContext), after)
            try BusinessRepository(context: reopened.mainContext).setSessionStatus(plannedID, to: .completed)
            let entries = try reopened.mainContext.fetch(FetchDescriptor<LedgerEntry>())
            XCTAssertEqual(entries.map(\.amountCents).sorted(), [3500, 3500, 5500, 5500])
        }
    }

    func testLegacySaveCreatesAndUpdatesStableStandardRateWithExactIntegerPrices() async throws {
        let store = try BusinessTestStore.make()
        let repository = BusinessRepository(context: store.mainContext)
        var draft = ServiceDraft()
        draft.name = "Legacy"
        draft.priceCents = 1234
        let id = try repository.saveService(draft)
        let service = try XCTUnwrap(store.mainContext.fetch(FetchDescriptor<TrainingService>()).first)
        let initial = try XCTUnwrap(store.mainContext.fetch(FetchDescriptor<ServiceRate>()).first)
        XCTAssertEqual(initial.id, id)
        XCTAssertEqual(initial.name, "Standard")
        XCTAssertEqual(initial.priceCents, 1234)
        draft.id = id
        for amount: Int64 in [0, Int64.max] {
            draft.priceCents = amount
            try repository.saveService(draft)
            XCTAssertEqual(service.priceCents, amount)
            XCTAssertEqual(initial.priceCents, amount)
            XCTAssertEqual(try store.mainContext.fetchCount(FetchDescriptor<ServiceRate>()), 1)
            XCTAssertEqual(initial.id, id)
        }
    }

    func testLegacyEmptyTariffsEditKeepsExistingAndNewlyAddedNamedRates() async throws {
        try withStoreFixture { directory in
            let url = directory.appendingPathComponent("legacy-edit.store")
            let store = try StoreFactory.makeContainer(url: url)
            let context = store.mainContext
            let repository = BusinessRepository(context: context)
            var catalog = ServiceDraft()
            catalog.name = "Individuale"
            catalog.tariffs = [ServiceRateDraft(name: "Ordinaria", priceCents: 5000),
                               ServiceRateDraft(name: "Ridotta", priceCents: 3000)]
            catalog.id = try repository.saveService(catalog)
            let service = try XCTUnwrap(context.fetch(FetchDescriptor<TrainingService>()).first)
            var legacy = ServiceDraft(service)
            XCTAssertTrue(legacy.tariffs.isEmpty)
            catalog.tariffs.append(ServiceRateDraft(name: "Promozione", priceCents: 1999))
            try repository.saveService(catalog)

            legacy.name = "Servizio rinominato"
            legacy.durationMinutes = 45
            legacy.priceCents = 6500
            try repository.saveService(legacy)
            var expected = catalog.tariffs
            expected[0].priceCents = 6500
            XCTAssertEqual(service.name, legacy.name)
            XCTAssertEqual(service.durationMinutes, 45)
            XCTAssertEqual(service.priceCents, 6500)
            XCTAssertEqual(ServiceTariffs.options(for: service,
                rates: try context.fetch(FetchDescriptor<ServiceRate>())), expected)
            XCTAssertFalse(context.hasChanges)
            let reopened = try StoreFactory.makeContainer(url: url)
            let stored = try XCTUnwrap(reopened.mainContext.fetch(FetchDescriptor<TrainingService>()).first)
            XCTAssertEqual(ServiceTariffs.options(for: stored,
                rates: try reopened.mainContext.fetch(FetchDescriptor<ServiceRate>())), expected)
        }
    }

    func testInvalidNamesDuplicateIDsNegativePricesAndForeignRateIDsAreAtomic() async throws {
        let store = try BusinessTestStore.make()
        let context = store.mainContext
        let repository = BusinessRepository(context: context)
        var draft = ServiceDraft()
        draft.name = "Individuale"
        draft.tariffs = [ServiceRateDraft(name: "Base", priceCents: 5000)]
        draft.id = try repository.saveService(draft)
        var other = ServiceDraft()
        other.name = "Coppia"
        other.tariffs = [ServiceRateDraft(name: "Duo", priceCents: 3000)]
        try repository.saveService(other)
        let original = try BusinessArchive.capture(context: context)
        let observed = try XCTUnwrap(context.fetch(FetchDescriptor<TrainingService>()).first { $0.id == draft.id })
        let timestamp = observed.updatedAt
        let sharedID = UUID()
        let cases: [[ServiceRateDraft]] = [
            [ServiceRateDraft(name: " \n\t ")],
            [ServiceRateDraft(name: "Base"), ServiceRateDraft(name: "  bASE \n")],
            [ServiceRateDraft(id: sharedID, name: "Prima"), ServiceRateDraft(id: sharedID, name: "Seconda")],
            [ServiceRateDraft(name: "Negativa", priceCents: -1)],
            [ServiceRateDraft(name: "Minima", priceCents: .min)],
            [ServiceRateDraft(name: "Valida"), other.tariffs[0]]
        ]
        for tariffs in cases {
            var invalid = draft
            invalid.name = "Non salvato"
            invalid.tariffs = tariffs
            for id in [draft.id, nil] {
                invalid.id = id
                XCTAssertThrowsError(try repository.saveService(invalid))
                XCTAssertEqual(try BusinessArchive.capture(context: context), original)
                XCTAssertEqual(try BusinessArchive.capture(context: ModelContext(store)), original)
                XCTAssertEqual(observed.name, "Individuale")
                XCTAssertEqual(observed.updatedAt, timestamp)
                XCTAssertFalse(context.hasChanges)
            }
        }
        draft.tariffs = []
        draft.priceCents = -1
        XCTAssertThrowsError(try repository.saveService(draft))
        XCTAssertEqual(try BusinessArchive.capture(context: context), original)
    }

    func testInjectedSaveFailureNeverMergesPartialCatalogChangesAndRetrySucceeds() async throws {
        let store = try BusinessTestStore.make()
        let context = store.mainContext
        var draft = ServiceDraft()
        draft.name = "Individuale"
        draft.tariffs = [ServiceRateDraft(name: "Base", priceCents: 5000),
                         ServiceRateDraft(name: "Ridotta", priceCents: 3000)]
        draft.id = try BusinessRepository(context: context).saveService(draft)
        let original = try BusinessArchive.capture(context: context)
        let observed = try XCTUnwrap(context.fetch(FetchDescriptor<TrainingService>()).first)
        let rate = try XCTUnwrap(context.fetch(FetchDescriptor<ServiceRate>()).first { $0.id == draft.tariffs[0].id })
        let failure = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError)
        var shouldFail = true
        let repository = BusinessRepository(context: context) { writer in
            XCTAssertFalse(writer === context)
            XCTAssertFalse(writer.autosaveEnabled)
            writer.processPendingChanges()
            XCTAssertEqual(observed.name, "Individuale")
            XCTAssertEqual(rate.priceCents, 5000)
            if shouldFail { throw failure }
            try writer.save()
        }
        draft.name = "Nuovo"
        draft.tariffs = [ServiceRateDraft(id: rate.id, name: "Aggiornata", priceCents: 6000),
                         ServiceRateDraft(name: "Aggiunta", priceCents: 4000)]
        for _ in 0..<2 {
            XCTAssertThrowsError(try repository.saveService(draft)) { XCTAssertEqual($0 as NSError, failure) }
            var insert = draft
            insert.id = nil
            insert.tariffs = [ServiceRateDraft(name: "Inserita", priceCents: 1000)]
            XCTAssertThrowsError(try repository.saveService(insert)) { XCTAssertEqual($0 as NSError, failure) }
            XCTAssertEqual(try BusinessArchive.capture(context: context), original)
            XCTAssertEqual(try BusinessArchive.capture(context: ModelContext(store)), original)
            XCTAssertFalse(context.hasChanges)
        }
        shouldFail = false
        try repository.saveService(draft)
        XCTAssertEqual(observed.name, "Nuovo")
        XCTAssertEqual(observed.priceCents, 6000)
        XCTAssertEqual(rate.priceCents, 6000)
        XCTAssertEqual(ServiceTariffs.options(for: observed, rates: try context.fetch(FetchDescriptor<ServiceRate>())),
                       draft.tariffs)
        XCTAssertFalse(context.hasChanges)
    }

    func testRealReadOnlyFailureLeavesServiceRatesAndDiskUnchanged() async throws {
        try withStoreFixture { directory in
            let url = directory.appendingPathComponent("readonly.store")
            let writable = try StoreFactory.makeContainer(url: url)
            var draft = ServiceDraft()
            draft.name = "Originale"
            draft.tariffs = [ServiceRateDraft(name: "Base", priceCents: 5000),
                             ServiceRateDraft(name: "Ridotta", priceCents: 3000)]
            draft.id = try BusinessRepository(context: writable.mainContext).saveService(draft)
            let original = try BusinessArchive.capture(context: writable.mainContext)
            let schema = Schema(versionedSchema: PaolaSchemaV8.self)
            let readonly = try ModelContainer(for: schema, migrationPlan: PaolaSchemaMigrationPlan.self,
                configurations: [ModelConfiguration(schema: schema, url: url, allowsSave: false, cloudKitDatabase: .none)])
            let context = readonly.mainContext
            let observed = try XCTUnwrap(context.fetch(FetchDescriptor<TrainingService>()).first)
            let rates = try context.fetch(FetchDescriptor<ServiceRate>())
            let repository = BusinessRepository(context: context)
            draft.name = "Non salvato"
            draft.tariffs[0].priceCents = 9000
            draft.tariffs.removeLast()
            draft.tariffs.append(ServiceRateDraft(name: "Non salvata", priceCents: 2000))
            XCTAssertThrowsError(try repository.saveService(draft)) { XCTAssertFalse($0 is ClientPersistenceError) }
            XCTAssertEqual(observed.name, "Originale")
            XCTAssertEqual(observed.priceCents, 5000)
            XCTAssertEqual(rates.map(BusinessArchive.RateRecord.init).sorted { $0.id.uuidString < $1.id.uuidString },
                           original.rates)
            draft.id = nil
            draft.tariffs = [ServiceRateDraft(priceCents: 1000)]
            XCTAssertThrowsError(try repository.saveService(draft)) { XCTAssertFalse($0 is ClientPersistenceError) }
            XCTAssertFalse(context.hasChanges)
            XCTAssertEqual(try BusinessArchive.capture(context: context), original)
            let reopened = try StoreFactory.makeContainer(url: url)
            XCTAssertEqual(try BusinessArchive.capture(context: reopened.mainContext), original)
        }
    }
}
