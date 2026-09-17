import Foundation
import PaolaCore
import SwiftData

/// Esegue un backup automatico giornaliero (al primo avvio del giorno) nella cartella
/// interna dell'app, cifrato con la password memorizzata in Keychain.
///
/// - La password è la stessa dei backup manuali (min 12 caratteri), salvata in Keychain
///   tramite `BackupPasswordStore`. Se non è impostata, il backup automatico non parte:
///   la UI mostra una dialog per richiederla.
/// - Il file è scritto in `Application Support/PaolaGestionale/Backups/` con nome datato.
/// - L'ultima data di backup automatico è tracciata in UserDefaults per non ripetere
///   più di una volta al giorno.
@MainActor
enum AutoBackupService {
    private static let lastRunKey = "backup.autoLastRun"
    private static let maxDailyBackups = 30

    /// Vero se oggi il backup automatico è già stato eseguito.
    static func alreadyRanToday(now: Date = Date(), calendar: Calendar = .current) -> Bool {
        let last = UserDefaults.standard.double(forKey: lastRunKey)
        guard last > 0 else { return false }
        return calendar.isDate(Date(timeIntervalSince1970: last), inSameDayAs: now)
    }

    /// True se la password del backup è configurata in Keychain.
    static func isConfigured(secrets: SecretStore = KeychainSecretStore()) -> Bool {
        BackupPasswordStore(secrets: secrets).isConfigured
    }

    /// Esegue il backup automatico se non ancora fatto oggi e se la password è impostata.
    /// Ritorna true se il backup è stato eseguito. Non lancia: gli errori sono silenziati
    /// (un backup fallito non deve bloccare l'avvio), ma la data si aggiorna solo in caso
    /// di successo così si riprova al prossimo avvio.
    @discardableResult
    static func runIfNeeded(context: ModelContext, secrets: SecretStore = KeychainSecretStore(),
                            now: Date = Date()) -> Bool {
        guard !alreadyRanToday(now: now) else { return false }
        guard let password = BackupPasswordStore(secrets: secrets).password() else { return false }
        do {
            try performBackup(context: context, password: password, now: now)
            UserDefaults.standard.set(now.timeIntervalSince1970, forKey: lastRunKey)
            pruneOldBackups()
            return true
        } catch {
            // Silenzioso: non aggiorna la data, così riproverà al prossimo avvio.
            return false
        }
    }

    /// Cattura, cifra e scrive il backup nella cartella interna.
    private static func performBackup(context: ModelContext, password: String, now: Date) throws {
        let payload = try ArchiveSnapshot.capture(context: context).encoded()
        let encrypted = try BackupCipher.encrypt(payload, password: password)
        let directory = try StoreFactory.applicationDirectory().appendingPathComponent("Backups", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stamp = now.formatted(.iso8601.year().month().day())
        let url = directory.appendingPathComponent("auto-\(stamp)-\(UUID().uuidString.prefix(8)).paolabackup")
        try encrypted.write(to: url, options: [.atomic])
    }

    /// Mantiene solo i backup automatici più recenti (per non riempire il disco).
    private static func pruneOldBackups() {
        guard let directory = try? StoreFactory.applicationDirectory().appendingPathComponent("Backups", isDirectory: true),
              let files = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        let autoBackups = files.filter { $0.lastPathComponent.hasPrefix("auto-") }
            .sorted { lhs, rhs in
                let l = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                let r = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                return l > r
            }
        guard autoBackups.count > maxDailyBackups else { return }
        for file in autoBackups.dropFirst(maxDailyBackups) {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
