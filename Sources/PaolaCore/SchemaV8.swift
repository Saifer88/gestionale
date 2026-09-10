import Foundation
import SwiftData

/// Schema V8: introduce la fatturazione elettronica.
///
/// Rispetto a V7:
/// - aggiunge il campo opzionale `invoiceDate` (default nil) ai tipi correnti
///   TrainingSession e LessonPackage definiti in BusinessModels.swift;
/// - aggiunge la nuova entità `Invoice` (documento informativo).
///
/// Il cliente non cambia rispetto a V7, quindi V8 riusa `PaolaSchemaV7.Client`.
/// Il set di classi differisce comunque da V7 (nuova Invoice + TrainingSession/
/// LessonPackage con invoiceDate), evitando checksum duplicati. Migrazione lightweight
/// da V7: le nuove colonne opzionali vengono aggiunte con valore nil sui record esistenti.
public enum PaolaSchemaV8: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(8, 0, 0) }
    public static var models: [any PersistentModel.Type] {
        [
            PaolaSchemaV7.Client.self, TrainingService.self, ServiceRate.self, TrainingSession.self,
            SessionParticipant.self, LessonPackage.self, PackageUse.self, LedgerEntry.self,
            Unavailability.self, ClientAppointmentPreference.self, Invoice.self
        ]
    }
}
