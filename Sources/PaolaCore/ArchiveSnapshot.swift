import Foundation
import SwiftData

public struct ArchiveSnapshot: Codable {
    public var version: Int = 6
    public var createdAt: Date = Date()
    public var clients: [ClientRecord]
    public var business: BusinessArchive
    public var recordCount: Int { clients.count + business.recordCount }

    public struct ClientRecord: Codable, Equatable {
        public var id: UUID
        public var firstName: String
        public var lastName: String
        public var phone: String
        public var email: String
        public var taxCode: String
        public var billingAddress: String
        public var notes: String
        public var anamnesis: String
        public var physicalAnalysis: String
        public var preferredServiceID: UUID?
        public var preferredRateID: UUID?
        public var joinedOn: Date
        public var createdAt: Date
        public var updatedAt: Date
        public var isArchived: Bool

        init(_ client: Client) {
            id = client.id
            firstName = client.firstName
            lastName = client.lastName
            phone = client.phone
            email = client.email
            taxCode = client.taxCode
            billingAddress = client.billingAddress
            notes = client.notes
            anamnesis = client.anamnesis
            physicalAnalysis = client.physicalAnalysis
            preferredServiceID = client.preferredServiceID
            preferredRateID = client.preferredRateID
            joinedOn = client.joinedOn
            createdAt = client.createdAt
            updatedAt = client.updatedAt
            isArchived = client.isArchived
        }

        private enum CodingKeys: String, CodingKey {
            case id, firstName, lastName, phone, email, taxCode, billingAddress, notes, anamnesis, physicalAnalysis
            case joinedOn, createdAt, updatedAt, isArchived
            case preferredServiceID, preferredRateID
        }

        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            id = try values.decode(UUID.self, forKey: .id)
            firstName = try values.decode(String.self, forKey: .firstName)
            lastName = try values.decode(String.self, forKey: .lastName)
            phone = try values.decode(String.self, forKey: .phone)
            email = try values.decode(String.self, forKey: .email)
            taxCode = try values.decodeIfPresent(String.self, forKey: .taxCode) ?? ""
            billingAddress = try values.decodeIfPresent(String.self, forKey: .billingAddress) ?? ""
            notes = try values.decode(String.self, forKey: .notes)
            anamnesis = try values.decodeIfPresent(String.self, forKey: .anamnesis) ?? ""
            physicalAnalysis = try values.decodeIfPresent(String.self, forKey: .physicalAnalysis) ?? ""
            preferredServiceID = try values.decodeIfPresent(UUID.self, forKey: .preferredServiceID)
            preferredRateID = try values.decodeIfPresent(UUID.self, forKey: .preferredRateID)
            joinedOn = try values.decode(Date.self, forKey: .joinedOn)
            createdAt = try values.decode(Date.self, forKey: .createdAt)
            updatedAt = try values.decode(Date.self, forKey: .updatedAt)
            isArchived = try values.decode(Bool.self, forKey: .isArchived)
        }

        func model() -> Client {
            let client = Client(id: id, firstName: firstName, lastName: lastName, phone: phone,
                                email: email, taxCode: taxCode, billingAddress: billingAddress,
                                notes: notes, anamnesis: anamnesis,
                                physicalAnalysis: physicalAnalysis, joinedOn: joinedOn,
                                createdAt: createdAt, updatedAt: updatedAt, isArchived: isArchived,
                                preferredServiceID: preferredServiceID, preferredRateID: preferredRateID)
            client.joinedOn = joinedOn
            return client
        }
    }

    @MainActor
    public static func capture(context: ModelContext) throws -> ArchiveSnapshot {
        let reader = ModelContext(context.container)
        reader.autosaveEnabled = false
        let snapshot = try ArchiveSnapshot(
            clients: reader.fetch(FetchDescriptor<Client>()).map(ClientRecord.init)
                .sorted { $0.id.uuidString < $1.id.uuidString },
            business: BusinessArchive.capture(context: reader)
        )
        try snapshot.validate()
        return snapshot
    }

    public func validate() throws {
        guard (2...6).contains(version), createdAt.timeIntervalSinceReferenceDate.isFinite,
              clients.count <= 100_000,
              Set(clients.map(\.id)).count == clients.count else { throw ArchiveError.invalidArchive }
        for client in clients {
            guard !client.firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !client.lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  [client.joinedOn, client.createdAt, client.updatedAt].allSatisfy({
                      $0.timeIntervalSinceReferenceDate.isFinite
                  }) else { throw ArchiveError.invalidArchive }
            guard client.preferredRateID == nil || client.preferredServiceID != nil else {
                throw ArchiveError.invalidArchive
            }
            if let serviceID = client.preferredServiceID {
                guard business.services.contains(where: { $0.id == serviceID }) else { throw ArchiveError.invalidArchive }
                if let rateID = client.preferredRateID, let rate = business.rates.first(where: { $0.id == rateID }) {
                    guard rate.serviceID == serviceID else { throw ArchiveError.invalidArchive }
                }
            }
        }
        try business.validate(clientIDs: Set(clients.map(\.id)))
    }

    public func encoded() throws -> Data {
        try validate()
        return try JSONEncoder().encode(self)
    }

    public static func decode(_ data: Data) throws -> ArchiveSnapshot {
        guard data.count <= 100_000_000 else { throw ArchiveError.invalidArchive }
        let snapshot = try JSONDecoder().decode(ArchiveSnapshot.self, from: data)
        try snapshot.validate()
        return snapshot
    }

    @MainActor
    public func restore(toNewStoreAt url: URL) throws {
        try validate()
        guard !FileManager.default.fileExists(atPath: url.path) else { throw ArchiveError.existingStore }
        let container = try StoreFactory.makeContainer(url: url)
        let writer = ModelContext(container)
        writer.autosaveEnabled = false
        for client in clients { writer.insert(client.model()) }
        try business.insert(into: writer)
        try writer.save()
        let verified = try Self.capture(context: container.mainContext)
        guard verified.clients == clients.sorted(by: { $0.id.uuidString < $1.id.uuidString }),
              verified.business == business.canonicalized() else {
            throw ArchiveError.verificationFailed
        }
    }
}

public enum ArchiveError: LocalizedError {
    case invalidArchive, existingStore, verificationFailed

    public var errorDescription: String? {
        switch self {
        case .invalidArchive: "Backup non valido, incompatibile o contenente riferimenti incoerenti."
        case .existingStore: "Il ripristino richiede un nuovo archivio vuoto; nessun dato esistente e' stato sovrascritto."
        case .verificationFailed: "Verifica del ripristino non riuscita. L'archivio attuale non e' stato sostituito."
        }
    }
}
