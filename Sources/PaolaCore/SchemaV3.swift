import Foundation
import SwiftData

public enum PaolaSchemaV3: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [
            Client.self, TrainingService.self, ServiceRate.self, PaolaSchemaV7.TrainingSession.self,
            PaolaSchemaV5.SessionParticipant.self, PaolaSchemaV5.LessonPackage.self, PackageUse.self,
            LedgerEntry.self, Unavailability.self
        ]
    }

    @Model
    public final class Client {
        public var id: UUID = UUID()
        public var firstName: String = ""
        public var lastName: String = ""
        public var phone: String = ""
        public var email: String = ""
        public var notes: String = ""
        public var anamnesis: String = ""
        public var physicalAnalysis: String = ""
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
            anamnesis: String = "",
            physicalAnalysis: String = "",
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
            self.anamnesis = anamnesis
            self.physicalAnalysis = physicalAnalysis
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
