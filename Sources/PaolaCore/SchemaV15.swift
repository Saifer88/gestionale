import Foundation
import SwiftData

/// Schema V15: aggiunge a `Expense` il flag `isPersonal` (spesa personale, esclusa dai
/// riepiloghi economici), con default false.
///
/// Rispetto a V14 cambia solo un campo (con default) su Expense; nessuna entità nuova.
/// Migrazione lightweight da V14: la colonna viene aggiunta con valore false.
public enum PaolaSchemaV15: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(15, 0, 0) }
    public static var models: [any PersistentModel.Type] {
        [
            Client.self, TrainingService.self, ServiceRate.self, PaolaSchemaV15.TrainingSession.self,
            PaolaSchemaV15.SessionParticipant.self, LessonPackage.self, PackageUse.self, LedgerEntry.self,
            Unavailability.self, ClientAppointmentPreference.self, Invoice.self, Expense.self,
            Course.self, CourseParticipant.self
        ]
    }

    /// Versione storica dell'appuntamento: ha ancora `isPaid` (spostato su
    /// `SessionParticipant` in V16). Serve a mantenere lo schema V15 distinto da V16.
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
        public var isBlack: Bool = false
        public var createdAt: Date = Date()
        public var updatedAt: Date = Date()

        public init(id: UUID = UUID(), startDate: Date = Date(), durationMinutes: Int = 60,
                    serviceID: UUID? = nil, serviceName: String = "", location: String = "",
                    notes: String = "", statusRaw: String = "planned",
                    invoiceDate: Date? = nil, isPaid: Bool = false, isBlack: Bool = false,
                    createdAt: Date = Date(), updatedAt: Date = Date()) {
            self.id = id; self.startDate = startDate; self.durationMinutes = durationMinutes
            self.serviceID = serviceID; self.serviceName = serviceName; self.location = location
            self.notes = notes; self.statusRaw = statusRaw; self.invoiceDate = invoiceDate
            self.isPaid = isPaid; self.isBlack = isBlack
            self.createdAt = createdAt; self.updatedAt = updatedAt
        }
    }

    /// Versione storica del partecipante: NON ha ancora `isPaid` (aggiunto in V16).
    @Model
    public final class SessionParticipant {
        public var id: UUID = UUID()
        public var sessionID: UUID = UUID()
        public var clientID: UUID = UUID()
        public var clientName: String = ""
        public var priceCents: Int64 = 0
        public var packageID: UUID?
        public var paymentMethodRaw: String = "cash"

        public init(id: UUID = UUID(), sessionID: UUID = UUID(), clientID: UUID = UUID(),
                    clientName: String = "", priceCents: Int64 = 0, packageID: UUID? = nil,
                    paymentMethodRaw: String = "cash") {
            self.id = id; self.sessionID = sessionID; self.clientID = clientID
            self.clientName = clientName; self.priceCents = priceCents; self.packageID = packageID
            self.paymentMethodRaw = paymentMethodRaw
        }
    }
}
