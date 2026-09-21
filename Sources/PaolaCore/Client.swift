import Foundation
import SwiftData

public enum PaolaSchemaV1: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    public static var models: [any PersistentModel.Type] { [Client.self] }

    @Model
    public final class Client {
        public var id: UUID = UUID()
        public var firstName: String = ""
        public var lastName: String = ""
        public var phone: String = ""
        public var email: String = ""
        public var notes: String = ""
        public var joinedOn: Date = Date()
        public var createdAt: Date = Date()
        public var updatedAt: Date = Date()
        public var isArchived: Bool = false

        public init(
            id: UUID = UUID(),
            firstName: String = "",
            lastName: String = "",
            phone: String = "",
            email: String = "",
            notes: String = "",
            joinedOn: Date = Date(),
            createdAt: Date = Date(),
            updatedAt: Date? = nil,
            isArchived: Bool = false
        ) {
            self.id = id
            self.firstName = firstName
            self.lastName = lastName
            self.phone = phone
            self.email = email
            self.notes = notes
            self.joinedOn = Calendar.current.startOfDay(for: joinedOn)
            self.createdAt = createdAt
            self.updatedAt = updatedAt ?? createdAt
            self.isArchived = isArchived
        }

        public var fullName: String {
            TextNormalization.spaces("\(firstName) \(lastName)")
        }
    }
}

public typealias Client = PaolaSchemaV12.Client

public enum PaolaSchemaMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [PaolaSchemaV1.self, PaolaSchemaV2.self, PaolaSchemaV3.self, PaolaSchemaV4.self,
         PaolaSchemaV5.self, PaolaSchemaV6.self, PaolaSchemaV7.self, PaolaSchemaV8.self,
         PaolaSchemaV9.self, PaolaSchemaV10.self, PaolaSchemaV11.self, PaolaSchemaV12.self,
         PaolaSchemaV13.self, PaolaSchemaV14.self, PaolaSchemaV15.self, PaolaSchemaV16.self]
    }
    public static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: PaolaSchemaV1.self, toVersion: PaolaSchemaV2.self),
            .lightweight(fromVersion: PaolaSchemaV2.self, toVersion: PaolaSchemaV3.self),
            .lightweight(fromVersion: PaolaSchemaV3.self, toVersion: PaolaSchemaV4.self),
            .lightweight(fromVersion: PaolaSchemaV4.self, toVersion: PaolaSchemaV5.self),
            .lightweight(fromVersion: PaolaSchemaV5.self, toVersion: PaolaSchemaV6.self),
            .lightweight(fromVersion: PaolaSchemaV6.self, toVersion: PaolaSchemaV7.self),
            .lightweight(fromVersion: PaolaSchemaV7.self, toVersion: PaolaSchemaV8.self),
            .lightweight(fromVersion: PaolaSchemaV8.self, toVersion: PaolaSchemaV9.self),
            .lightweight(fromVersion: PaolaSchemaV9.self, toVersion: PaolaSchemaV10.self),
            .lightweight(fromVersion: PaolaSchemaV10.self, toVersion: PaolaSchemaV11.self),
            .lightweight(fromVersion: PaolaSchemaV11.self, toVersion: PaolaSchemaV12.self),
            .lightweight(fromVersion: PaolaSchemaV12.self, toVersion: PaolaSchemaV13.self),
            .lightweight(fromVersion: PaolaSchemaV13.self, toVersion: PaolaSchemaV14.self),
            .lightweight(fromVersion: PaolaSchemaV14.self, toVersion: PaolaSchemaV15.self),
            .custom(
                fromVersion: PaolaSchemaV15.self, toVersion: PaolaSchemaV16.self,
                willMigrate: { context in
                    // Prima della migrazione lo schema è ancora V15: leggiamo l'isPaid
                    // storico di ogni appuntamento e lo teniamo pronto per ereditarlo sui
                    // partecipanti dopo il cambio di schema (in willMigrate lo schema
                    // corrente è ancora V15, i partecipanti non hanno isPaid).
                    let sessions = try context.fetch(FetchDescriptor<PaolaSchemaV15.TrainingSession>())
                    let paidSessionIDs = Set(sessions.filter(\.isPaid).map(\.id))
                    UserDefaults.standard.set(paidSessionIDs.map(\.uuidString),
                                              forKey: migrationPaidSessionIDsKey)
                },
                didMigrate: { context in
                    // Dopo la migrazione lo schema è V16: eredita isPaid sui partecipanti
                    // che non usano un pacchetto, per ogni appuntamento segnato pagato.
                    defer { UserDefaults.standard.removeObject(forKey: migrationPaidSessionIDsKey) }
                    let ids = UserDefaults.standard.stringArray(forKey: migrationPaidSessionIDsKey) ?? []
                    let paidSessionIDs = Set(ids.compactMap(UUID.init(uuidString:)))
                    guard !paidSessionIDs.isEmpty else { return }
                    let participants = try context.fetch(FetchDescriptor<SessionParticipant>())
                    for participant in participants
                    where participant.packageID == nil && paidSessionIDs.contains(participant.sessionID) {
                        participant.isPaid = true
                    }
                    try context.save()
                }
            )
        ]
    }

    /// Chiave temporanea in UserDefaults per portare l'elenco degli appuntamenti pagati
    /// da `willMigrate` a `didMigrate` (i due blocchi non condividono altrimenti stato).
    private static let migrationPaidSessionIDsKey = "migration.v15Tov16.paidSessionIDs"
}
