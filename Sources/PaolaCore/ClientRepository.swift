import Foundation
import SwiftData

public enum ClientPersistenceError: LocalizedError {
    case refreshAfterSaveFailed(Error)

    public var errorDescription: String? {
        switch self {
        case .refreshAfterSaveFailed(let error):
            return "I dati sono stati salvati, ma la schermata non e' stata aggiornata. "
                + "Non ripetere l'operazione: chiudi e riapri l'app. Dettaglio: "
                + error.localizedDescription
        }
    }
}

@MainActor
public final class ClientRepository {
    private let context: ModelContext
    private let saveChanges: (ModelContext) throws -> Void

    public convenience init(context: ModelContext) {
        self.init(context: context, saveChanges: { try $0.save() })
    }

    init(context: ModelContext, saveChanges: @escaping (ModelContext) throws -> Void) {
        self.context = context
        self.saveChanges = saveChanges
        context.autosaveEnabled = false
    }

    @discardableResult
    public func save(
        _ draft: ClientDraft,
        updating client: Client? = nil,
        allowDuplicate: Bool = false
    ) throws -> Client {
        let normalized = try draft.validated()
        if let client {
            try checkAvailable(client)
        }
        try normalized.checkOriginal(for: client)
        let writer = makeWriter()
        let savedClient: Client
        if let client {
            savedClient = try fetchClient(client.persistentModelID, in: writer)
            try normalized.checkOriginal(for: savedClient)
        } else {
            savedClient = Client()
        }
        if !allowDuplicate, try hasDuplicate(normalized, excluding: client?.persistentModelID, in: writer) {
            throw ClientValidationError.possibleDuplicate
        }

        if client == nil {
            writer.insert(savedClient)
        } else {
            savedClient.updatedAt = nextTimestamp(after: savedClient.updatedAt)
        }
        savedClient.firstName = normalized.firstName
        savedClient.lastName = normalized.lastName
        savedClient.phone = normalized.phone
        savedClient.email = normalized.email
        savedClient.notes = normalized.notes
        savedClient.anamnesis = normalized.anamnesis
        savedClient.physicalAnalysis = normalized.physicalAnalysis
        savedClient.joinedOn = normalized.joinedOn

        return try commit(savedClient, in: writer)
    }

    public func setArchived(_ archived: Bool, for client: Client) throws {
        try checkAvailable(client)
        guard client.isArchived != archived else { return }
        let writer = makeWriter()
        let storedClient = try fetchClient(client.persistentModelID, in: writer)
        try ClientDraft(client: client).checkOriginal(for: storedClient)
        storedClient.isArchived = archived
        storedClient.updatedAt = nextTimestamp(after: storedClient.updatedAt)
        _ = try commit(storedClient, in: writer)
    }

    private func hasDuplicate(
        _ draft: ClientDraft,
        excluding identifier: PersistentIdentifier?,
        in writer: ModelContext
    ) throws -> Bool {
        let firstName = TextNormalization.key(draft.firstName)
        let lastName = TextNormalization.key(draft.lastName)
        let phone = TextNormalization.phone(draft.phone)
        let email = TextNormalization.key(draft.email)

        return try writer.fetch(FetchDescriptor<Client>()).contains { existing in
            guard existing.persistentModelID != identifier else { return false }
            let sameName = TextNormalization.key(existing.firstName) == firstName
                && TextNormalization.key(existing.lastName) == lastName
            let samePhone = !phone.isEmpty && TextNormalization.phone(existing.phone) == phone
            let sameEmail = !email.isEmpty && TextNormalization.key(existing.email) == email
            return sameName || samePhone || sameEmail
        }
    }

    private func checkAvailable(_ client: Client) throws {
        guard client.modelContext === context, !client.isDeleted else {
            throw ClientValidationError.staleRecord
        }
    }

    private func nextTimestamp(after previous: Date) -> Date {
        max(Date(), previous.addingTimeInterval(0.000001))
    }

    private func makeWriter() -> ModelContext {
        // A failed SwiftData save can invalidate rollback snapshots. Never mutate the UI context.
        let writer = ModelContext(context.container)
        writer.autosaveEnabled = false
        return writer
    }

    private func fetchClient(_ identifier: PersistentIdentifier, in context: ModelContext) throws -> Client {
        var descriptor = FetchDescriptor<Client>(predicate: #Predicate { $0.persistentModelID == identifier })
        descriptor.fetchLimit = 1
        guard let client = try context.fetch(descriptor).first else {
            throw ClientValidationError.staleRecord
        }
        return client
    }

    private func commit(_ client: Client, in writer: ModelContext) throws -> Client {
        try saveChanges(writer)
        do {
            // Refetch merges the committed values into the instances already observed by SwiftUI.
            return try fetchClient(client.persistentModelID, in: context)
        } catch {
            throw ClientPersistenceError.refreshAfterSaveFailed(error)
        }
    }
}
