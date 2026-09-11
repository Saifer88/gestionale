import Foundation
@testable import PaolaCore
import SwiftData
import XCTest

@MainActor
final class SessionProvisionalRescheduleTests: XCTestCase {

    private func draft(_ client: Client, day: Int = 1, hour: Double = 10,
                       status: SessionStatus? = nil) -> SessionDraft {
        var draft = SessionDraft()
        draft.startDate = BusinessTestStore.date.addingTimeInterval(Double(day) * 86400 + hour * 3600)
        draft.durationMinutes = 60
        draft.serviceName = "Allenamento"
        draft.status = status
        draft.participants = [ParticipantDraft(clientID: client.id, priceCents: 5000)]
        return draft
    }

    // MARK: - Provvisorio

    func testProvisionalSaveStoresProvisionalStatusAndNoLedger() throws {
        let store = try BusinessTestStore.make()
        let context = store.mainContext
        let client = try BusinessTestStore.addClient(context)
        let repo = BusinessRepository(context: context)

        let id = try repo.saveSession(draft(client, status: .provisional))

        let session = try XCTUnwrap(context.fetch(FetchDescriptor<TrainingSession>()).first { $0.id == id })
        XCTAssertEqual(session.status, .provisional)
        // Un appuntamento provvisorio non genera alcun movimento economico.
        XCTAssertTrue(try context.fetch(FetchDescriptor<LedgerEntry>()).isEmpty)
    }

    func testNewSessionWithoutStatusDefaultsToPlanned() throws {
        let store = try BusinessTestStore.make()
        let context = store.mainContext
        let client = try BusinessTestStore.addClient(context)
        let repo = BusinessRepository(context: context)

        let id = try repo.saveSession(draft(client, status: nil))
        let session = try XCTUnwrap(context.fetch(FetchDescriptor<TrainingSession>()).first { $0.id == id })
        XCTAssertEqual(session.status, .planned)
    }

    func testProvisionalDoesNotBlockOverlapButPlannedDoes() throws {
        let store = try BusinessTestStore.make()
        let context = store.mainContext
        let client = try BusinessTestStore.addClient(context)
        let other = try BusinessTestStore.addClient(context, name: "Bea")
        let repo = BusinessRepository(context: context)

        // Un appuntamento programmato occupa le 10:00.
        _ = try repo.saveSession(draft(client, hour: 10, status: .planned))

        // Provvisorio alla stessa ora: consentito (nessun errore di sovrapposizione).
        XCTAssertNoThrow(try repo.saveSession(draft(other, hour: 10, status: .provisional)))

        // Programmato alla stessa ora: sovrapposizione bloccante.
        XCTAssertThrowsError(try repo.saveSession(draft(other, hour: 10, status: .planned))) {
            guard case BusinessError.overlap = $0 else { return XCTFail("Atteso overlap, ricevuto \($0)") }
        }
    }

    func testConfirmingProvisionalBecomesPlannedWithoutLedger() throws {
        let store = try BusinessTestStore.make()
        let context = store.mainContext
        let client = try BusinessTestStore.addClient(context)
        let repo = BusinessRepository(context: context)

        let id = try repo.saveSession(draft(client, status: .provisional))
        try repo.setSessionStatus(id, to: .planned)

        let session = try XCTUnwrap(context.fetch(FetchDescriptor<TrainingSession>()).first { $0.id == id })
        XCTAssertEqual(session.status, .planned)
        XCTAssertTrue(try context.fetch(FetchDescriptor<LedgerEntry>()).isEmpty)
    }

    func testEditingPlannedWithoutStatusKeepsPlanned() throws {
        let store = try BusinessTestStore.make()
        let context = store.mainContext
        let client = try BusinessTestStore.addClient(context)
        let repo = BusinessRepository(context: context)

        let id = try repo.saveSession(draft(client, status: .planned))
        var edit = draft(client, status: nil)
        edit.id = id
        edit.notes = "aggiornata"
        _ = try repo.saveSession(edit)

        let session = try XCTUnwrap(context.fetch(FetchDescriptor<TrainingSession>()).first { $0.id == id })
        XCTAssertEqual(session.status, .planned)
        XCTAssertEqual(session.notes, "aggiornata")
    }

    // MARK: - Reschedule (drag & drop)

    func testRescheduleMovesStartDateKeepingDuration() throws {
        let store = try BusinessTestStore.make()
        let context = store.mainContext
        let client = try BusinessTestStore.addClient(context)
        let repo = BusinessRepository(context: context)

        let id = try repo.saveSession(draft(client, hour: 10, status: .planned))
        let newStart = BusinessTestStore.date.addingTimeInterval(86400 + 15 * 3600)
        try repo.rescheduleSession(id, to: newStart)

        let session = try XCTUnwrap(context.fetch(FetchDescriptor<TrainingSession>()).first { $0.id == id })
        XCTAssertEqual(session.startDate, newStart)
        XCTAssertEqual(session.durationMinutes, 60)
    }

    func testReschedulePlannedOntoOccupiedSlotThrowsWithoutAllowOverlap() throws {
        let store = try BusinessTestStore.make()
        let context = store.mainContext
        let client = try BusinessTestStore.addClient(context)
        let other = try BusinessTestStore.addClient(context, name: "Bea")
        let repo = BusinessRepository(context: context)

        _ = try repo.saveSession(draft(client, hour: 10, status: .planned))
        let movableID = try repo.saveSession(draft(other, hour: 15, status: .planned))
        let occupied = BusinessTestStore.date.addingTimeInterval(86400 + 10 * 3600)

        XCTAssertThrowsError(try repo.rescheduleSession(movableID, to: occupied)) {
            guard case BusinessError.overlap = $0 else { return XCTFail("Atteso overlap, ricevuto \($0)") }
        }
        // Con allowOverlap lo spostamento è consentito (usato per lo scambio di posto).
        XCTAssertNoThrow(try repo.rescheduleSession(movableID, to: occupied, allowOverlap: true))
    }

    func testSwapTwoAppointmentsExchangesStartTimes() throws {
        let store = try BusinessTestStore.make()
        let context = store.mainContext
        let client = try BusinessTestStore.addClient(context)
        let other = try BusinessTestStore.addClient(context, name: "Bea")
        let repo = BusinessRepository(context: context)

        let aID = try repo.saveSession(draft(client, hour: 10, status: .planned))
        let bID = try repo.saveSession(draft(other, hour: 15, status: .planned))
        let aStart = BusinessTestStore.date.addingTimeInterval(86400 + 10 * 3600)
        let bStart = BusinessTestStore.date.addingTimeInterval(86400 + 15 * 3600)

        // Scambio: A va all'ora di B e viceversa (allowOverlap perché transitoriamente
        // i due si sovrappongono al vecchio orario).
        try repo.rescheduleSession(aID, to: bStart, allowOverlap: true)
        try repo.rescheduleSession(bID, to: aStart, allowOverlap: true)

        let sessions = try context.fetch(FetchDescriptor<TrainingSession>())
        XCTAssertEqual(try XCTUnwrap(sessions.first { $0.id == aID }).startDate, bStart)
        XCTAssertEqual(try XCTUnwrap(sessions.first { $0.id == bID }).startDate, aStart)
    }

    func testRescheduleCompletedSessionIsBlocked() throws {
        let store = try BusinessTestStore.make()
        let context = store.mainContext
        let client = try BusinessTestStore.addClient(context)
        let repo = BusinessRepository(context: context)

        let id = try repo.saveSession(draft(client, hour: 10, status: .planned))
        try repo.setSessionStatus(id, to: .completed)
        let newStart = BusinessTestStore.date.addingTimeInterval(86400 + 16 * 3600)

        XCTAssertThrowsError(try repo.rescheduleSession(id, to: newStart)) {
            guard case BusinessError.completedSessionLocked = $0 else {
                return XCTFail("Atteso completedSessionLocked, ricevuto \($0)")
            }
        }
    }
}
