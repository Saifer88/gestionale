import Foundation
import SwiftData

/// Schema V14: aggiunge le entità `Course` e `CourseParticipant` (corsi ricorrenti
/// settimanali con partecipanti coperti da pacchetto a tempo).
///
/// Rispetto a V13 aggiunge solo le due nuove entità; nessuna classe esistente cambia.
/// Migrazione lightweight da V13: le nuove tabelle vengono create vuote.
public enum PaolaSchemaV14: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(14, 0, 0) }
    public static var models: [any PersistentModel.Type] {
        [
            Client.self, TrainingService.self, ServiceRate.self, TrainingSession.self,
            SessionParticipant.self, LessonPackage.self, PackageUse.self, LedgerEntry.self,
            Unavailability.self, ClientAppointmentPreference.self, Invoice.self, PaolaSchemaV14.Expense.self,
            Course.self, CourseParticipant.self
        ]
    }

    /// Versione storica della spesa: NON ha `isPersonal` (aggiunto in V15). Serve a
    /// mantenere lo schema V14 distinto da V15 per la migrazione.
    @Model
    public final class Expense {
        public var id: UUID = UUID()
        public var name: String = ""
        public var date: Date = Date()
        public var amountCents: Int64 = 0
        public var kindRaw: String = "oneTime"
        public var sourceKey: String = ""
        public var createdAt: Date = Date()
        public var updatedAt: Date = Date()

        public init(id: UUID = UUID(), name: String = "", date: Date = Date(),
                    amountCents: Int64 = 0, kind: ExpenseKind = .oneTime, sourceKey: String = "",
                    createdAt: Date = Date(), updatedAt: Date = Date()) {
            self.id = id; self.name = name; self.date = date
            self.amountCents = amountCents; self.kindRaw = kind.rawValue; self.sourceKey = sourceKey
            self.createdAt = createdAt; self.updatedAt = updatedAt
        }
    }
}
