import Foundation
@testable import PaolaCore
import SwiftData
import XCTest

@MainActor
enum BusinessTestStore {
    static var schema: Schema {
        Schema(versionedSchema: PaolaSchemaV8.self)
    }
    static func make() throws -> ModelContainer {
        try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        ])
    }
    static func addClient(_ context: ModelContext, name: String = "Anna", archived: Bool = false) throws -> Client {
        context.autosaveEnabled = false
        let client = Client(firstName: name, lastName: "Rossi", isArchived: archived)
        context.insert(client)
        try context.save()
        return client
    }
    static let date = Date(timeIntervalSince1970: 1_735_689_600)
    static func session(_ client: Client, day: Int = 1, price: Int64 = 5000, packageID: UUID? = nil) -> SessionDraft {
        var draft = SessionDraft()
        draft.startDate = date.addingTimeInterval(Double(day) * 86400 + 10 * 3600)
        draft.durationMinutes = 60
        draft.serviceName = "Allenamento"
        draft.participants = [ParticipantDraft(clientID: client.id, priceCents: price, packageID: packageID)]
        return draft
    }
    static func package(_ client: Client, price: Int64 = 40000) -> PackageDraft {
        var draft = PackageDraft()
        draft.clientID = client.id; draft.priceCents = price; draft.purchasedOn = date
        return draft
    }
    static func payment(_ client: Client, amount: Int64, day: Int = 0) -> PaymentDraft {
        var draft = PaymentDraft()
        draft.clientID = client.id; draft.amountCents = amount
        draft.date = date.addingTimeInterval(Double(day) * 86400)
        return draft
    }

    @discardableResult
    static func seedLegacyPayment(_ draft: PaymentDraft, in context: ModelContext) throws -> UUID {
        let client = try XCTUnwrap(context.fetch(FetchDescriptor<Client>()).first { $0.id == draft.clientID })
        let entry = LedgerEntry(clientID: client.id, clientName: client.fullName, date: draft.date,
            kind: .payment, amountCents: draft.amountCents, method: draft.method, notes: draft.notes)
        entry.sourceKey = "payment:\(entry.id.uuidString.lowercased())"
        context.insert(entry)
        try context.save()
        return entry.id
    }

    @discardableResult
    static func seedLegacySession(_ draft: SessionDraft, in context: ModelContext) throws -> UUID {
        let session = TrainingSession(startDate: draft.startDate, durationMinutes: draft.durationMinutes,
            serviceID: draft.serviceID, serviceName: draft.serviceName,
            location: draft.location, notes: draft.notes)
        context.insert(session)
        let clients = try context.fetch(FetchDescriptor<Client>())
        for participant in draft.participants {
            let client = try XCTUnwrap(clients.first { $0.id == participant.clientID })
            context.insert(SessionParticipant(sessionID: session.id, clientID: client.id,
                clientName: client.fullName, priceCents: participant.priceCents, packageID: participant.packageID))
        }
        try context.save()
        return session.id
    }
}
