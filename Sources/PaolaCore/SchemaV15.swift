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
            Client.self, TrainingService.self, ServiceRate.self, TrainingSession.self,
            SessionParticipant.self, LessonPackage.self, PackageUse.self, LedgerEntry.self,
            Unavailability.self, ClientAppointmentPreference.self, Invoice.self, Expense.self,
            Course.self, CourseParticipant.self
        ]
    }
}
