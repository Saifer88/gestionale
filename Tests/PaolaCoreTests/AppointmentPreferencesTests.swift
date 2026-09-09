import Foundation
@testable import PaolaCore
import SwiftData
import XCTest

@MainActor
final class AppointmentPreferencesTests: XCTestCase {
    private func defaults(_ clientID: UUID, context: ModelContext) throws -> AppointmentDefaults? {
        AppointmentPreferences.lastUsed(clientID: clientID,
            sessions: try context.fetch(FetchDescriptor<TrainingSession>()),
            participants: try context.fetch(FetchDescriptor<SessionParticipant>()),
            preferences: try context.fetch(FetchDescriptor<ClientAppointmentPreference>()))
    }

    private func service(in repository: BusinessRepository) throws -> (UUID, [ServiceRateDraft]) {
        var draft = ServiceDraft()
        draft.name = "Individuale"
        draft.tariffs = [ServiceRateDraft(name: "Base", priceCents: 5000),
                        ServiceRateDraft(name: "Convenzione", priceCents: 5000)]
        return (try repository.saveService(draft), draft.tariffs)
    }

    func testSuccessfulChoicesPersistExactSamePriceRatePackageAndTimePerClient() async throws {
        try withStoreFixture { directory in
            let url = directory.appendingPathComponent("preferences.store")
            let store = try StoreFactory.makeContainer(url: url)
            let context = store.mainContext
            let first = try BusinessTestStore.addClient(context)
            let second = try BusinessTestStore.addClient(context, name: "Elena")
            let repository = BusinessRepository(context: context)
            let (serviceID, rates) = try service(in: repository)
            let packageID = try repository.savePackage(BusinessTestStore.package(first))
            var draft = BusinessTestStore.session(first, packageID: packageID)
            draft.startDate = try XCTUnwrap(SchedulingSuggestions.calendar.date(
                bySettingHour: 8, minute: 35, second: 0, of: draft.startDate))
            draft.serviceID = serviceID
            draft.durationMinutes = 45
            draft.participants[0].tariffID = rates[1].id
            let firstSession = try repository.saveSession(draft)
            var secondDraft = BusinessTestStore.session(second, day: 2)
            secondDraft.serviceID = serviceID
            secondDraft.participants[0].tariffID = rates[0].id
            try repository.saveSession(secondDraft)
            let expected = AppointmentDefaults(serviceID: serviceID, hour: 8, minute: 35,
                rateID: rates[1].id, priceCents: 5000, packageID: packageID, durationMinutes: 45)
            XCTAssertEqual(try defaults(first.id, context: context), expected)
            XCTAssertEqual(try defaults(second.id, context: context)?.rateID, rates[0].id)
            XCTAssertEqual(Set(try context.fetch(FetchDescriptor<ClientAppointmentPreference>()).map(\.id)),
                           [first.id, second.id])
            let reopened = try StoreFactory.makeContainer(url: url)
            XCTAssertEqual(try defaults(first.id, context: reopened.mainContext), expected)
            let before = try BusinessArchive.capture(context: context)
            try repository.setSessionStatus(firstSession, to: .completed)
            XCTAssertEqual(try BusinessArchive.capture(context: context).preferences, before.preferences)
        }
    }

    func testLatestSuccessfulSaveWinsRegardlessOfSessionDateAndUpdatesOnePreference() async throws {
        let store = try BusinessTestStore.make()
        let context = store.mainContext
        let client = try BusinessTestStore.addClient(context)
        let repository = BusinessRepository(context: context)
        let (serviceID, rates) = try service(in: repository)
        var future = BusinessTestStore.session(client, day: 50)
        future.serviceID = serviceID
        future.participants[0].tariffID = rates[0].id
        let id = try repository.saveSession(future)
        var past = BusinessTestStore.session(client, day: 1, price: 4321)
        past.durationMinutes = 90
        try repository.saveSession(past)
        XCTAssertEqual(try defaults(client.id, context: context)?.priceCents, 4321)
        XCTAssertEqual(try defaults(client.id, context: context)?.durationMinutes, 90)
        XCTAssertNil(try defaults(client.id, context: context)?.serviceID)
        future.id = id
        future.participants[0].tariffID = rates[1].id
        future.participants[0].priceCents = 6789
        try repository.saveSession(future)
        XCTAssertEqual(try defaults(client.id, context: context)?.rateID, rates[1].id)
        XCTAssertEqual(try defaults(client.id, context: context)?.priceCents, 6789)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ClientAppointmentPreference>()), 1)
        XCTAssertFalse(context.hasChanges)
    }

    func testUnsavedCancelledDraftAndFailedCreationDoNotCreatePreferences() async throws {
        let store = try BusinessTestStore.make()
        let context = store.mainContext
        let client = try BusinessTestStore.addClient(context)
        var unsaved = BusinessTestStore.session(client)
        unsaved.durationMinutes = 45
        XCTAssertNil(try defaults(client.id, context: context))
        XCTAssertFalse(context.hasChanges)
        let failure = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError)
        let failing = BusinessRepository(context: context) { writer in
            XCTAssertEqual(try writer.fetchCount(FetchDescriptor<ClientAppointmentPreference>()), 1)
            writer.processPendingChanges()
            throw failure
        }
        XCTAssertThrowsError(try failing.saveSession(unsaved)) { XCTAssertEqual($0 as NSError, failure) }
        XCTAssertNil(try defaults(client.id, context: context))
        XCTAssertEqual(try BusinessArchive.capture(context: ModelContext(store)).recordCount, 0)
        XCTAssertFalse(context.hasChanges)
    }

    func testFailedUpdateAndInvalidRateRetainAllPreviousSnapshotsAndObservedPreference() async throws {
        let store = try BusinessTestStore.make()
        let context = store.mainContext
        let client = try BusinessTestStore.addClient(context)
        let repository = BusinessRepository(context: context)
        let (serviceID, rates) = try service(in: repository)
        var draft = BusinessTestStore.session(client)
        draft.serviceID = serviceID
        draft.participants[0].tariffID = rates[1].id
        draft.id = try repository.saveSession(draft)
        let original = try BusinessArchive.capture(context: context)
        let observed = try XCTUnwrap(context.fetch(FetchDescriptor<ClientAppointmentPreference>()).first)
        let originalPreference = BusinessArchive.PreferenceRecord(observed)
        let failure = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)
        let failing = BusinessRepository(context: context) { writer in
            XCTAssertFalse(writer === context)
            XCTAssertFalse(writer.autosaveEnabled)
            writer.processPendingChanges()
            throw failure
        }
        draft.durationMinutes = 90
        draft.participants[0].tariffID = rates[0].id
        XCTAssertThrowsError(try failing.saveSession(draft)) { XCTAssertEqual($0 as NSError, failure) }
        draft.participants[0].tariffID = UUID()
        XCTAssertThrowsError(try repository.saveSession(draft))
        XCTAssertEqual(BusinessArchive.PreferenceRecord(observed), originalPreference)
        XCTAssertEqual(try BusinessArchive.capture(context: context), original)
        XCTAssertEqual(try BusinessArchive.capture(context: ModelContext(store)), original)
        XCTAssertFalse(context.hasChanges)
    }

    func testTariffMustBeCurrentOptionOfChosenServiceButCustomPriceAndNilAreAllowed() async throws {
        let store = try BusinessTestStore.make()
        let context = store.mainContext
        let client = try BusinessTestStore.addClient(context)
        let repository = BusinessRepository(context: context)
        let (serviceID, rates) = try service(in: repository)
        let (_, otherRates) = try service(in: repository)
        var draft = BusinessTestStore.session(client)
        draft.participants[0].tariffID = rates[0].id
        XCTAssertThrowsError(try repository.saveSession(draft))
        draft.serviceID = serviceID
        draft.participants[0].tariffID = otherRates[0].id
        XCTAssertThrowsError(try repository.saveSession(draft))
        draft.participants[0].tariffID = UUID()
        XCTAssertThrowsError(try repository.saveSession(draft))
        draft.participants[0].tariffID = rates[0].id
        draft.participants[0].priceCents = 1234
        draft.id = try repository.saveSession(draft)
        XCTAssertEqual(try defaults(client.id, context: context)?.priceCents, 1234)
        draft.participants[0].tariffID = nil
        try repository.saveSession(draft)
        XCTAssertNil(try defaults(client.id, context: context)?.rateID)
    }

    func testDeletedRateAndExpiredPackageRemainHistoricalPreferencesWithoutGuessingSamePriceRate() async throws {
        let store = try BusinessTestStore.make()
        let context = store.mainContext
        let client = try BusinessTestStore.addClient(context)
        let repository = BusinessRepository(context: context)
        let (serviceID, rates) = try service(in: repository)
        var package = BusinessTestStore.package(client)
        package.expiresOn = BusinessTestStore.date.addingTimeInterval(5 * 86400)
        let packageID = try repository.savePackage(package)
        var draft = BusinessTestStore.session(client, packageID: packageID)
        draft.serviceID = serviceID
        draft.participants[0].tariffID = rates[1].id
        try repository.saveSession(draft)
        let before = try defaults(client.id, context: context)
        let model = try XCTUnwrap(context.fetch(FetchDescriptor<TrainingService>()).first)
        var edit = ServiceDraft(model, rates: try context.fetch(FetchDescriptor<ServiceRate>()))
        edit.tariffs = [rates[0]]
        edit.isActive = false
        try repository.saveService(edit)
        XCTAssertEqual(try defaults(client.id, context: context), before)
        XCTAssertEqual(before?.rateID, rates[1].id)
        XCTAssertEqual(before?.packageID, packageID)
        try BusinessArchive.capture(context: context).validate(clientIDs: [client.id])
    }

    func testLegacyFallbackUsesCreationThenUpdateNotScheduledDateAndExcludesCancelledAndNoShow() async throws {
        let client = UUID()
        let other = UUID()
        let date = BusinessTestStore.date
        let oldFuture = TrainingSession(startDate: date.addingTimeInterval(50 * 86400), createdAt: date)
        let latest = TrainingSession(startDate: date, durationMinutes: 45, serviceID: UUID(),
            createdAt: date.addingTimeInterval(1), updatedAt: date.addingTimeInterval(2))
        let tied = TrainingSession(startDate: date, createdAt: latest.createdAt, updatedAt: date)
        let cancelled = TrainingSession(status: .cancelled, createdAt: date.addingTimeInterval(3))
        let noShow = TrainingSession(status: .noShow, createdAt: date.addingTimeInterval(4))
        let foreign = TrainingSession(createdAt: date.addingTimeInterval(5))
        let sessions = [oldFuture, latest, tied, cancelled, noShow, foreign]
        let participants = sessions.map {
            SessionParticipant(sessionID: $0.id, clientID: $0.id == foreign.id ? other : client, priceCents: 4321)
        }
        let result = AppointmentPreferences.lastUsed(clientID: client, sessions: sessions,
            participants: participants, preferences: [])
        XCTAssertEqual(result?.serviceID, latest.serviceID)
        XCTAssertEqual(result?.durationMinutes, 45)
        XCTAssertEqual(result?.priceCents, 4321)
        XCTAssertEqual(result?.hour, SchedulingSuggestions.calendar.component(.hour, from: date))
        XCTAssertNil(result?.rateID)
        XCTAssertNil(AppointmentPreferences.lastUsed(clientID: UUID(), sessions: sessions,
            participants: participants, preferences: []))
        XCTAssertNil(AppointmentPreferences.lastUsed(clientID: client, sessions: [cancelled, noShow],
            participants: participants, preferences: []))
    }

    func testNewestPreferenceWinsWithDeterministicIDTieAndNoOtherClientLeak() async throws {
        let client = UUID()
        let date = BusinessTestStore.date
        let first = ClientAppointmentPreference(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            clientID: client, preferredHour: 8, rateID: UUID(), updatedAt: date)
        let second = ClientAppointmentPreference(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            clientID: client, preferredHour: 9, rateID: UUID(), updatedAt: date)
        let foreign = ClientAppointmentPreference(clientID: UUID(), preferredHour: 17)
        for preferences in [[first, second, foreign], [foreign, second, first]] {
            XCTAssertEqual(AppointmentPreferences.lastUsed(clientID: client, sessions: [],
                participants: [], preferences: preferences)?.rateID, first.rateID)
        }
        second.updatedAt = date.addingTimeInterval(1)
        XCTAssertEqual(AppointmentPreferences.lastUsed(clientID: client, sessions: [],
            participants: [], preferences: [first, foreign, second])?.rateID, second.rateID)
    }
}
