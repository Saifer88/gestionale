import Foundation
import SwiftData

/// Schema V6: aggiunge il metodo di pagamento a SessionParticipant e LessonPackage
/// (attributo paymentMethodRaw con default "cash"). Migrazione lightweight da V5.
///
/// Per SessionParticipant usa il tipo corrente (che non è più cambiato da V6). Per
/// TrainingSession e LessonPackage usa invece le classi storiche congelate in V7,
/// senza il campo invoiceDate aggiunto ai tipi correnti in V8: a V6 quel campo non
/// esisteva ancora. V6 differisce da V7 per la classe Client (V7 aggiunge taxCode/
/// billingAddress), quindi può riusare le stesse classi lezione/pacchetto storiche.
public enum PaolaSchemaV6: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(6, 0, 0) }
    public static var models: [any PersistentModel.Type] {
        [
            PaolaSchemaV5.Client.self, TrainingService.self, ServiceRate.self, PaolaSchemaV7.TrainingSession.self,
            PaolaCore.SessionParticipant.self, PaolaSchemaV7.LessonPackage.self, PackageUse.self,
            LedgerEntry.self, Unavailability.self, ClientAppointmentPreference.self
        ]
    }
}
