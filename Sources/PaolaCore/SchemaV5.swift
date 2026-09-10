import Foundation
import SwiftData

public enum PaolaSchemaV5: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(5, 0, 0) }
    public static var models: [any PersistentModel.Type] {
        [
            PaolaSchemaV5.Client.self, TrainingService.self, ServiceRate.self, TrainingSession.self,
            SessionParticipant.self, LessonPackage.self, PackageUse.self, LedgerEntry.self,
            Unavailability.self, ClientAppointmentPreference.self
        ]
    }

    /// Versione storica del partecipante, senza metodo di pagamento (aggiunto in V6).
    @Model
    public final class SessionParticipant {
        public var id: UUID = UUID()
        public var sessionID: UUID = UUID()
        public var clientID: UUID = UUID()
        public var clientName: String = ""
        public var priceCents: Int64 = 0
        public var packageID: UUID?

        public init(id: UUID = UUID(), sessionID: UUID = UUID(), clientID: UUID = UUID(),
                    clientName: String = "", priceCents: Int64 = 0, packageID: UUID? = nil) {
            self.id = id; self.sessionID = sessionID; self.clientID = clientID
            self.clientName = clientName; self.priceCents = priceCents; self.packageID = packageID
        }
    }

    /// Versione storica del pacchetto, senza metodo di pagamento (aggiunto in V6).
    @Model
    public final class LessonPackage {
        public var id: UUID = UUID()
        public var clientID: UUID = UUID()
        public var clientName: String = ""
        public var purchasedOn: Date = Date()
        public var priceCents: Int64 = 0
        public var capacity: Int = 10
        public var expiresOn: Date?
        public var notes: String = ""

        public init(id: UUID = UUID(), clientID: UUID = UUID(), clientName: String = "",
                    purchasedOn: Date = Date(), priceCents: Int64 = 0, capacity: Int = 10,
                    expiresOn: Date? = nil, notes: String = "") {
            self.id = id; self.clientID = clientID; self.clientName = clientName
            self.purchasedOn = purchasedOn; self.priceCents = priceCents; self.capacity = capacity
            self.expiresOn = expiresOn; self.notes = notes
        }
    }

    /// Versione storica del cliente, senza codice fiscale e indirizzo di fatturazione
    /// (aggiunti nella classe corrente in V7). Congelata per distinguere il checksum
    /// degli schemi V5/V6 da quello di V7 e per collaudare la migrazione lightweight.
    @Model
    public final class Client {
        public var id: UUID = UUID()
        public var firstName: String = ""
        public var lastName: String = ""
        public var phone: String = ""
        public var email: String = ""
        public var notes: String = ""
        public var anamnesis: String = ""
        public var physicalAnalysis: String = ""
        public var preferredServiceID: UUID?
        public var preferredRateID: UUID?
        public var joinedOn: Date = Date()
        public var createdAt: Date = Date()
        public var updatedAt: Date = Date()
        public var isArchived: Bool = false

        public init(
            id: UUID = UUID(),
            firstName: String = "",
            lastName: String = "",
            phone: String = "",
            email: String = "",
            notes: String = "",
            anamnesis: String = "",
            physicalAnalysis: String = "",
            joinedOn: Date = Date(),
            createdAt: Date = Date(),
            updatedAt: Date? = nil,
            isArchived: Bool = false,
            preferredServiceID: UUID? = nil,
            preferredRateID: UUID? = nil
        ) {
            self.id = id
            self.firstName = firstName
            self.lastName = lastName
            self.phone = phone
            self.email = email
            self.notes = notes
            self.anamnesis = anamnesis
            self.physicalAnalysis = physicalAnalysis
            self.joinedOn = Calendar.current.startOfDay(for: joinedOn)
            self.createdAt = createdAt
            self.updatedAt = updatedAt ?? createdAt
            self.isArchived = isArchived
            self.preferredServiceID = preferredServiceID
            self.preferredRateID = preferredRateID
        }

        public var fullName: String {
            TextNormalization.spaces("\(firstName) \(lastName)")
        }
    }
}
