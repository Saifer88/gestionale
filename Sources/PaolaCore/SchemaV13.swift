import Foundation
import SwiftData

/// Schema V13: aggiunge a `LessonPackage` il tipo di pacchetto (`kindRaw`: a lezioni o
/// a tempo), con default "lessons".
///
/// Rispetto a V12 cambia solo un campo (con default) su LessonPackage; nessuna entità
/// nuova. Migrazione lightweight da V12: la colonna viene aggiunta con valore "lessons".
public enum PaolaSchemaV13: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(13, 0, 0) }
    public static var models: [any PersistentModel.Type] {
        [
            Client.self, TrainingService.self, ServiceRate.self, TrainingSession.self,
            SessionParticipant.self, LessonPackage.self, PackageUse.self, LedgerEntry.self,
            Unavailability.self, ClientAppointmentPreference.self, Invoice.self, PaolaSchemaV14.Expense.self
        ]
    }
}
