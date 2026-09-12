import Foundation
import SwiftData

/// Schema V10: aggiunge la ripartizione contabile "bianco/nero" (`isBlack`, default
/// false) a `TrainingSession` e `LessonPackage`.
///
/// Rispetto a V9 cambiano solo queste due entità, che qui sono i tipi correnti definiti
/// in BusinessModels.swift (con `isBlack`). Tutte le altre classi restano quelle di V9.
/// Migrazione lightweight da V9: la nuova colonna booleana viene aggiunta con valore
/// `false` sui record esistenti.
public enum PaolaSchemaV10: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(10, 0, 0) }
    public static var models: [any PersistentModel.Type] {
        [
            PaolaSchemaV7.Client.self, TrainingService.self, ServiceRate.self, TrainingSession.self,
            SessionParticipant.self, LessonPackage.self, PackageUse.self, LedgerEntry.self,
            Unavailability.self, ClientAppointmentPreference.self, Invoice.self
        ]
    }
}
