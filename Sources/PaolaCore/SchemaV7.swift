import Foundation
import SwiftData

/// Schema V7: aggiunge al cliente il codice fiscale e l'indirizzo di fatturazione
/// (taxCode, billingAddress; default stringa vuota). Migrazione lightweight da V6.
///
/// V7 congela inoltre TrainingSession e LessonPackage nella loro forma storica
/// (senza il campo invoiceDate, aggiunto ai tipi correnti in V8): il campo di
/// fatturazione compare solo dallo schema V8. Le classi congelate qui sono usate
/// anche da V2/V3/V4/V6, dove TrainingSession/LessonPackage non avevano invoiceDate.
public enum PaolaSchemaV7: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(7, 0, 0) }
    public static var models: [any PersistentModel.Type] {
        [
            Client.self, TrainingService.self, ServiceRate.self, PaolaSchemaV7.TrainingSession.self,
            SessionParticipant.self, PaolaSchemaV7.LessonPackage.self, PackageUse.self, LedgerEntry.self,
            Unavailability.self, ClientAppointmentPreference.self
        ]
    }

    /// Versione storica della lezione, senza data di fatturazione (aggiunta in V8).
    @Model
    public final class TrainingSession {
        public var id: UUID = UUID()
        public var startDate: Date = Date()
        public var durationMinutes: Int = 60
        public var serviceID: UUID?
        public var serviceName: String = ""
        public var location: String = ""
        public var notes: String = ""
        public var statusRaw: String = "planned"
        public var createdAt: Date = Date()
        public var updatedAt: Date = Date()

        public var status: SessionStatus {
            get { SessionStatus(rawValue: statusRaw) ?? .planned }
            set { statusRaw = newValue.rawValue }
        }

        public init(id: UUID = UUID(), startDate: Date = Date(), durationMinutes: Int = 60,
                    serviceID: UUID? = nil, serviceName: String = "", location: String = "",
                    notes: String = "", status: SessionStatus = .planned,
                    createdAt: Date = Date(), updatedAt: Date = Date()) {
            self.id = id; self.startDate = startDate; self.durationMinutes = durationMinutes
            self.serviceID = serviceID; self.serviceName = serviceName; self.location = location
            self.notes = notes; self.statusRaw = status.rawValue
            self.createdAt = createdAt; self.updatedAt = updatedAt
        }
    }

    /// Versione storica del pacchetto, con metodo di pagamento (aggiunto in V6) ma senza
    /// data di fatturazione (aggiunta in V8).
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
        public var paymentMethodRaw: String = "cash"

        public init(id: UUID = UUID(), clientID: UUID = UUID(), clientName: String = "",
                    purchasedOn: Date = Date(), priceCents: Int64 = 0, capacity: Int = 10,
                    expiresOn: Date? = nil, notes: String = "", paymentMethod: PaymentMethod = .cash) {
            self.id = id; self.clientID = clientID; self.clientName = clientName
            self.purchasedOn = purchasedOn; self.priceCents = priceCents; self.capacity = capacity
            self.expiresOn = expiresOn; self.notes = notes
            self.paymentMethodRaw = paymentMethod.rawValue
        }
    }

    @Model
    public final class Client {
        public var id: UUID = UUID()
        public var firstName: String = ""
        public var lastName: String = ""
        public var phone: String = ""
        public var email: String = ""
        public var taxCode: String = ""
        public var billingAddress: String = ""
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
            taxCode: String = "",
            billingAddress: String = "",
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
            self.taxCode = taxCode
            self.billingAddress = billingAddress
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
