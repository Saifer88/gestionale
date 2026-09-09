import SwiftData

public enum PaolaSchemaV4: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(4, 0, 0) }
    public static var models: [any PersistentModel.Type] {
        PaolaSchemaV3.models + [ClientAppointmentPreference.self]
    }
}
