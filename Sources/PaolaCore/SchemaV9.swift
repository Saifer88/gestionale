import Foundation
import SwiftData

/// Schema V9: aggiunge alla lezione il contrassegno manuale `isPaid` (default false),
/// un promemoria "pagato" indipendente dai movimenti economici e dalla fatturazione.
///
/// V9 congela `TrainingSession` (con `isPaid` ma senza `isBlack`, aggiunto in V10) e
/// `LessonPackage` (con `invoiceDate` ma senza `isBlack`). Le altre classi sono quelle
/// riusate da V8. Migrazione lightweight da V8: la colonna `isPaid` viene aggiunta con
/// valore `false` sui record esistenti.
public enum PaolaSchemaV9: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(9, 0, 0) }
    public static var models: [any PersistentModel.Type] {
        [
            PaolaSchemaV7.Client.self, TrainingService.self, ServiceRate.self,
            PaolaSchemaV9.TrainingSession.self,
            SessionParticipant.self, PaolaSchemaV9.LessonPackage.self, PackageUse.self, LedgerEntry.self,
            Unavailability.self, ClientAppointmentPreference.self, Invoice.self
        ]
    }

    /// Versione storica della lezione: ha `invoiceDate` (V8) e `isPaid` (V9) ma non
    /// `isBlack` (aggiunto in V10).
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
        public var invoiceDate: Date?
        public var isPaid: Bool = false
        public var createdAt: Date = Date()
        public var updatedAt: Date = Date()

        public var status: SessionStatus {
            get { SessionStatus(rawValue: statusRaw) ?? .planned }
            set { statusRaw = newValue.rawValue }
        }

        public init(id: UUID = UUID(), startDate: Date = Date(), durationMinutes: Int = 60,
                    serviceID: UUID? = nil, serviceName: String = "", location: String = "",
                    notes: String = "", status: SessionStatus = .planned,
                    invoiceDate: Date? = nil, isPaid: Bool = false,
                    createdAt: Date = Date(), updatedAt: Date = Date()) {
            self.id = id; self.startDate = startDate; self.durationMinutes = durationMinutes
            self.serviceID = serviceID; self.serviceName = serviceName; self.location = location
            self.notes = notes; self.statusRaw = status.rawValue; self.invoiceDate = invoiceDate
            self.isPaid = isPaid
            self.createdAt = createdAt; self.updatedAt = updatedAt
        }
    }

    /// Versione storica del pacchetto: ha `invoiceDate` (V8) ma non `isBlack` (V10).
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
        public var invoiceDate: Date?

        public init(id: UUID = UUID(), clientID: UUID = UUID(), clientName: String = "",
                    purchasedOn: Date = Date(), priceCents: Int64 = 0, capacity: Int = 10,
                    expiresOn: Date? = nil, notes: String = "", paymentMethod: PaymentMethod = .cash,
                    invoiceDate: Date? = nil) {
            self.id = id; self.clientID = clientID; self.clientName = clientName
            self.purchasedOn = purchasedOn; self.priceCents = priceCents; self.capacity = capacity
            self.expiresOn = expiresOn; self.notes = notes
            self.paymentMethodRaw = paymentMethod.rawValue
            self.invoiceDate = invoiceDate
        }
    }
}
