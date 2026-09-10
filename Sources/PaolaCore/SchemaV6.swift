import Foundation
import SwiftData

/// Schema V6: aggiunge il metodo di pagamento a SessionParticipant e LessonPackage
/// (attributo paymentMethodRaw con default "cash"). Usa i tipi correnti definiti in
/// BusinessModels.swift, che includono il nuovo attributo. Migrazione lightweight da V5.
public enum PaolaSchemaV6: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(6, 0, 0) }
    public static var models: [any PersistentModel.Type] {
        [
            PaolaSchemaV5.Client.self, TrainingService.self, ServiceRate.self, TrainingSession.self,
            PaolaCore.SessionParticipant.self, PaolaCore.LessonPackage.self, PackageUse.self,
            LedgerEntry.self, Unavailability.self, ClientAppointmentPreference.self
        ]
    }
}
