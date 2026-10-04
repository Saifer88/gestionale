import Foundation
@testable import PaolaCore
import SwiftData
import XCTest

@MainActor
final class WritePerformanceTests: XCTestCase {
    /// Archivio simile a circa due anni di attività: 3000 lezioni completate con
    /// addebito e incasso, più 200 appuntamenti programmati.
    private func seed(_ context: ModelContext) throws -> [SessionParticipant] {
        context.autosaveEnabled = false
        let clients = (0..<60).map { Client(firstName: "Cliente\($0)", lastName: "Rossi") }
        clients.forEach(context.insert)
        var planned: [SessionParticipant] = []
        for index in 0..<3200 {
            let client = clients[index % clients.count]
            let completed = index < 3000
            let start = BusinessTestStore.date.addingTimeInterval(Double(index) * 7200)
            let session = TrainingSession(startDate: start, serviceName: "Allenamento",
                                          status: completed ? .completed : .planned)
            context.insert(session)
            let participant = SessionParticipant(sessionID: session.id, clientID: client.id,
                                                 clientName: client.fullName, priceCents: 5000)
            context.insert(participant)
            if completed {
                context.insert(LedgerEntry(clientID: client.id, clientName: client.fullName, date: start,
                    kind: .charge, amountCents: 5000, notes: "Allenamento",
                    sourceKey: BusinessRules.sessionSource(sessionID: session.id, clientID: client.id)))
                context.insert(LedgerEntry(clientID: client.id, clientName: client.fullName, date: start,
                    kind: .payment, amountCents: 5000, method: .cash, notes: "Allenamento",
                    sourceKey: BusinessRules.sessionIncomeSource(sessionID: session.id, clientID: client.id)))
            } else {
                planned.append(participant)
            }
        }
        try context.save()
        return planned
    }

    private func measure(_ label: String, _ block: () throws -> Void) rethrows -> TimeInterval {
        let started = Date()
        try block()
        let elapsed = Date().timeIntervalSince(started)
        print("[perf] \(label): \(Int(elapsed * 1000)) ms")
        return elapsed
    }

    func testLocalWritesOnLargeArchiveStayFast() throws {
        let container = try BusinessTestStore.make()
        let context = ModelContext(container)
        let planned = try seed(context)
        let repository = BusinessRepository(context: context)
        let participant = try XCTUnwrap(planned.first)
        let client = try XCTUnwrap(context.fetch(FetchDescriptor<Client>()).first { $0.id == participant.clientID })
        var draft = BusinessTestStore.session(client, day: 900)
        draft.startDate = BusinessTestStore.date.addingTimeInterval(900 * 86_400)

        let local = try [
            measure("setParticipantPaid") { try repository.setParticipantPaid(participant.id, true) },
            measure("setSessionBlack") { try repository.setSessionBlack(participant.sessionID, true) },
            measure("rescheduleSession") {
                try repository.rescheduleSession(participant.sessionID, to: draft.startDate.addingTimeInterval(-86_400))
            },
            measure("saveSession") { _ = try repository.saveSession(draft) }
        ]
        // Economic operations still validate the whole archive; this guards against quadratic checks.
        let completion = try measure("setSessionStatus completed") {
            try repository.setSessionStatus(participant.sessionID, to: .completed)
        }
        for elapsed in local { XCTAssertLessThan(elapsed, 0.8) }
        XCTAssertLessThan(completion, 6.0)
    }
}
