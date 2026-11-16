import Foundation
import SwiftData

/// Controlli globali sull'archivio, eseguiti su un contesto separato dal main.
/// Il risultato è un calcolo effimero: non viene salvato né messo in cache.
@ModelActor
public actor ArchiveHealthChecker {
    /// Avvisi di integrità economica (movimenti, pacchetti, utilizzi).
    public func integrityWarnings() throws -> [String] {
        BusinessReports.integrityWarnings(
            entries: try modelContext.fetch(FetchDescriptor<LedgerEntry>()),
            packages: try modelContext.fetch(FetchDescriptor<LessonPackage>()),
            uses: try modelContext.fetch(FetchDescriptor<PackageUse>()))
    }

    /// Validazione completa dell'archivio. Ritorna il messaggio del primo problema, o `nil`.
    public func fullValidation() throws -> String? {
        try PaolaSignpost.interval("fullValidation") {
            let clients = try modelContext.fetch(FetchDescriptor<Client>())
            let clientIDs = Set(clients.map(\.id))
            guard clientIDs.count == clients.count else { return "Clienti duplicati." }
            do {
                try BusinessArchive.uncanonicalizedCapture(context: modelContext).validate(clientIDs: clientIDs)
                return nil
            } catch let error as BusinessError {
                return error.localizedDescription
            }
        }
    }
}
