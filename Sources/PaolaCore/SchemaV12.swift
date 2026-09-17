import Foundation
import SwiftData

/// Schema V12: aggiunge al cliente la data di nascita (`birthDate`, opzionale).
///
/// Rispetto a V11 cambia solo l'entità Client (nuovo campo opzionale); tutte le altre
/// entità restano quelle correnti. Migrazione lightweight da V11: la nuova colonna
/// viene aggiunta con valore nil sui record esistenti.
public enum PaolaSchemaV12: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(12, 0, 0) }
    public static var models: [any PersistentModel.Type] {
        [
            Client.self, TrainingService.self, ServiceRate.self, TrainingSession.self,
            SessionParticipant.self, LessonPackage.self, PackageUse.self, LedgerEntry.self,
            Unavailability.self, ClientAppointmentPreference.self, Invoice.self, Expense.self
        ]
    }

    @Model
    public final class Client {
        public var id: UUID = UUID()
        public var firstName: String = ""
        public var lastName: String = ""
        public var phone: String = ""
        public var email: String = ""
        public var taxCode: String = ""
        public var billingAddress: String = ""
        /// Data di nascita (schema V12). Opzionale: nil finché non inserita.
        public var birthDate: Date?
        public var notes: String = ""
        public var anamnesis: String = ""
        public var physicalAnalysis: String = ""
        public var preferredServiceID: UUID?
        public var preferredRateID: UUID?
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
            taxCode: String = "",
            billingAddress: String = "",
            birthDate: Date? = nil,
            notes: String = "",
            anamnesis: String = "",
            physicalAnalysis: String = "",
            joinedOn: Date = Date(),
            createdAt: Date = Date(),
            updatedAt: Date? = nil,
            isArchived: Bool = false,
            preferredServiceID: UUID? = nil,
            preferredRateID: UUID? = nil
        ) {
            self.id = id
            self.firstName = firstName
            self.lastName = lastName
            self.phone = phone
            self.email = email
            self.taxCode = taxCode
            self.billingAddress = billingAddress
            self.birthDate = birthDate
            self.notes = notes
            self.anamnesis = anamnesis
            self.physicalAnalysis = physicalAnalysis
            self.joinedOn = Calendar.current.startOfDay(for: joinedOn)
            self.createdAt = createdAt
            self.updatedAt = updatedAt ?? createdAt
            self.isArchived = isArchived
            self.preferredServiceID = preferredServiceID
            self.preferredRateID = preferredRateID
        }

        public var fullName: String {
            TextNormalization.spaces("\(firstName) \(lastName)")
        }
    }
}
