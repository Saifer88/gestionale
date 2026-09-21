import Foundation
import SwiftData

/// Schema V16: sposta il contrassegno manuale "pagato" dall'appuntamento
/// (`TrainingSession.isPaid`) al singolo partecipante (`SessionParticipant.isPaid`).
///
/// Un appuntamento con più partecipanti può ora avere alcuni pagati e altri no; i
/// partecipanti con `packageID != nil` non hanno un `isPaid` significativo (il
/// pagamento è gestito dal pacchetto, nessun incasso diretto).
///
/// Migrazione da V15: non è lightweight, perché il valore di `isPaid` deve essere
/// **ereditato** dall'appuntamento di origine su ogni partecipante che non usa un
/// pacchetto (requisito esplicito: non si riparte da `false` per tutti). Lo stage
/// `custom` in `PaolaSchemaMigrationPlan` (Client.swift) esegue questa copia dopo la
/// creazione dello schema V16, prima del salvataggio.
public enum PaolaSchemaV16: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(16, 0, 0) }
    public static var models: [any PersistentModel.Type] {
        [
            Client.self, TrainingService.self, ServiceRate.self, TrainingSession.self,
            SessionParticipant.self, LessonPackage.self, PackageUse.self, LedgerEntry.self,
            Unavailability.self, ClientAppointmentPreference.self, Invoice.self, Expense.self,
            Course.self, CourseParticipant.self
        ]
    }
}
