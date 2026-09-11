import Foundation
import SwiftData

/// Schema V8: introduce la fatturazione elettronica.
///
/// Rispetto a V7:
/// - aggiunge il campo opzionale `invoiceDate` (default nil) a TrainingSession e
///   LessonPackage;
/// - aggiunge la nuova entità `Invoice` (documento informativo).
///
/// Il cliente non cambia rispetto a V7, quindi V8 riusa `PaolaSchemaV7.Client`;
/// il pacchetto corrente (con invoiceDate ma senza altri campi successivi) è definito
/// in BusinessModels.swift e riusato qui. La TrainingSession di V8 è congelata nella
/// sua forma storica (con invoiceDate, senza il campo `isPaid` aggiunto in V9).
public enum PaolaSchemaV8: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(8, 0, 0) }
    public static var models: [any PersistentModel.Type] {
        [
            PaolaSchemaV7.Client.self, TrainingService.self, ServiceRate.self,
            PaolaSchemaV8.TrainingSession.self,
            SessionParticipant.self, LessonPackage.self, PackageUse.self, LedgerEntry.self,
            Unavailability.self, ClientAppointmentPreference.self, Invoice.self
        ]
    }

    /// Versione storica della lezione: ha `invoiceDate` (V8) ma non `isPaid` (V9).
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
        public var createdAt: Date = Date()
        public var updatedAt: Date = Date()

        public var status: SessionStatus {
            get { SessionStatus(rawValue: statusRaw) ?? .planned }
            set { statusRaw = newValue.rawValue }
        }

        public init(id: UUID = UUID(), startDate: Date = Date(), durationMinutes: Int = 60,
                    serviceID: UUID? = nil, serviceName: String = "", location: String = "",
                    notes: String = "", status: SessionStatus = .planned,
                    invoiceDate: Date? = nil,
                    createdAt: Date = Date(), updatedAt: Date = Date()) {
            self.id = id; self.startDate = startDate; self.durationMinutes = durationMinutes
            self.serviceID = serviceID; self.serviceName = serviceName; self.location = location
            self.notes = notes; self.statusRaw = status.rawValue; self.invoiceDate = invoiceDate
            self.createdAt = createdAt; self.updatedAt = updatedAt
        }
    }
}
