import Foundation
@testable import PaolaCore
import SwiftData
import XCTest

@MainActor
final class ArchiveHealthCheckerTests: XCTestCase {
    private final class Counter: @unchecked Sendable { var value = 0 }

    func testHealthyArchiveHasNoWarningsAndPassesFullValidation() async throws {
        let container = try StoreFactory.makeContainer(inMemory: true)
        let context = container.mainContext
        let client = try BusinessTestStore.addClient(context)
        let repository = BusinessRepository(context: context)
        _ = try repository.savePackage(BusinessTestStore.package(client))
        let session = try repository.saveSession(BusinessTestStore.session(client))
        try repository.setSessionStatus(session, to: .completed)
        let checker = ArchiveHealthChecker(modelContainer: container)
        let warnings = try await checker.integrityWarnings()
        let message = try await checker.fullValidation()
        XCTAssertEqual(warnings, [])
        XCTAssertNil(message)
    }

    func testCorruptArchiveIsReported() async throws {
        let container = try StoreFactory.makeContainer(inMemory: true)
        let context = container.mainContext
        let client = try BusinessTestStore.addClient(context)
        context.insert(LedgerEntry(clientID: client.id, clientName: client.fullName, date: BusinessTestStore.date,
            kind: .charge, amountCents: -5, notes: "seed", sourceKey: "seed:bad"))
        try context.save()
        let checker = ArchiveHealthChecker(modelContainer: container)
        let warnings = try await checker.integrityWarnings()
        let message = try await checker.fullValidation()
        XCTAssertFalse(warnings.isEmpty)
        XCTAssertNotNil(message)
    }

    func testNotificationIsPostedForEconomicWritesOnly() throws {
        let container = try StoreFactory.makeContainer(inMemory: true)
        let context = container.mainContext
        let client = try BusinessTestStore.addClient(context)
        let repository = BusinessRepository(context: context)
        let session = try repository.saveSession(BusinessTestStore.session(client))
        let counter = Counter()
        let token = NotificationCenter.default.addObserver(
            forName: .paolaEconomicDataDidChange, object: nil, queue: nil) { _ in counter.value += 1 }
        defer { NotificationCenter.default.removeObserver(token) }
        try repository.setSessionBlack(session, true)
        XCTAssertEqual(counter.value, 0)
        try repository.setSessionStatus(session, to: .completed)
        XCTAssertEqual(counter.value, 1)
    }
}
