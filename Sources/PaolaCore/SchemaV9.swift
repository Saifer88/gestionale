import Foundation
import SwiftData

/// Schema V9: aggiunge alla lezione il contrassegno manuale `isPaid` (default false),
/// un promemoria "pagato" indipendente dai movimenti economici e dalla fatturazione.
///
/// Rispetto a V8 cambia solo `TrainingSession`, che qui è il tipo corrente definito in
/// BusinessModels.swift (con `isPaid`). Tutte le altre classi restano quelle di V8.
/// Migrazione lightweight da V8: la nuova colonna booleana viene aggiunta con valore
/// `false` sui record esistenti.
public enum PaolaSchemaV9: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(9, 0, 0) }
    public static var models: [any PersistentModel.Type] {
        [
            PaolaSchemaV7.Client.self, TrainingService.self, ServiceRate.self, TrainingSession.self,
            SessionParticipant.self, LessonPackage.self, PackageUse.self, LedgerEntry.self,
            Unavailability.self, ClientAppointmentPreference.self, Invoice.self
        ]
    }
}
