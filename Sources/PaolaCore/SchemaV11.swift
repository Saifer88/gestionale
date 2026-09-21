import Foundation
import SwiftData

/// Schema V11: aggiunge l'entità `Expense` (spese una tantum e ricorrenti mensili).
///
/// Rispetto a V10 aggiunge solo la nuova entità; nessuna classe esistente cambia.
/// Migrazione lightweight da V10: la nuova tabella viene creata vuota.
public enum PaolaSchemaV11: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(11, 0, 0) }
    public static var models: [any PersistentModel.Type] {
        [
            PaolaSchemaV7.Client.self, TrainingService.self, ServiceRate.self, TrainingSession.self,
            SessionParticipant.self, PaolaSchemaV12.LessonPackage.self, PackageUse.self, LedgerEntry.self,
            Unavailability.self, ClientAppointmentPreference.self, Invoice.self, PaolaSchemaV14.Expense.self
        ]
    }
}
