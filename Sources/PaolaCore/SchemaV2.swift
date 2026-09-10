import SwiftData

public enum PaolaSchemaV2: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }
    public static var models: [any PersistentModel.Type] {
        [
            PaolaSchemaV1.Client.self, TrainingService.self, PaolaSchemaV7.TrainingSession.self,
            PaolaSchemaV5.SessionParticipant.self, PaolaSchemaV5.LessonPackage.self, PackageUse.self,
            LedgerEntry.self, Unavailability.self
        ]
    }
}
