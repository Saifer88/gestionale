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
            Unavailability.self, ClientAppointmentPreference.self, Invoice.self, Expense.self,
            Course.self, CourseParticipant.self
        ]
    }
}
