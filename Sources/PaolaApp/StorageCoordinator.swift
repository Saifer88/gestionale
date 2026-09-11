import CloudKit
import CoreData
import PaolaCore
import SwiftData
import SwiftUI

@MainActor
final class StorageCoordinator: ObservableObject {
    @Published private(set) var container: ModelContainer?
    @Published private(set) var errorMessage: String?
    @Published private(set) var status = "Apertura archivio..."
    @Published private(set) var lastSync: Date?
    @Published private(set) var generation = UUID()
    @Published var maintenanceMessage: String?
    private var openingTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    var cloudEnabled: Bool {
        Bundle.main.object(forInfoDictionaryKey: "PaolaCloudEnabled") as? String == "YES"
    }

    init() {
        observers.append(NotificationCenter.default.addObserver(
            forName: .CKAccountChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.cloudEnabled else { return }
                self.container = nil
                self.status = "Account iCloud cambiato. Verifica in corso..."
                self.open()
            }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event else { return }
            Task { @MainActor in
                guard let self, self.cloudEnabled, self.container != nil else { return }
                if let error = event.error {
                    self.status = "Sincronizzazione non riuscita: \(error.localizedDescription)"
                } else if event.endDate == nil {
                    self.status = "Sincronizzazione iCloud in corso..."
                } else if event.succeeded {
                    self.lastSync = event.endDate
                    self.status = "Ultimo trasferimento iCloud completato"
                }
            }
        })
    }

    deinit {
        openingTask?.cancel()
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    func open() {
        openingTask?.cancel()
        errorMessage = nil
        generation = UUID()
        let attempt = generation
        openingTask = Task {
            do {
                let opened: ModelContainer
                if cloudEnabled {
                    guard let identifier = Bundle.main.object(forInfoDictionaryKey: "PaolaCloudContainerIdentifier")
                            as? String, identifier.hasPrefix("iCloud.") else {
                        throw StorageError.invalidCloudConfiguration
                    }
                    let cloud = CKContainer(identifier: identifier)
                    guard try await cloud.accountStatus() == .available else {
                        throw StorageError.unavailableAccount
                    }
                    let recordID = try await cloud.userRecordID()
                    try Task.checkCancellation()
                    let namespace = try CloudNamespace.directoryName(
                        containerIdentifier: identifier, accountRecordName: recordID.recordName
                    )
                    let base = try StoreFactory.applicationDirectory()
                    let url = base.appendingPathComponent("iCloud/\(namespace)/Clienti-v1.store")
                    opened = try StoreFactory.makeContainer(url: url, cloudKitContainerIdentifier: identifier)
                } else {
                    #if DEBUG
                    if let namespace = ProcessInfo.processInfo.environment["PAOLA_UI_TEST_NAMESPACE"] {
                        guard UUID(uuidString: namespace) != nil else { throw CocoaError(.fileReadInvalidFileName) }
                        let base = try StoreFactory.applicationDirectory()
                        opened = try StoreFactory.makeContainer(
                            url: base.appendingPathComponent("UITests/\(namespace)/Clienti-v1.store")
                        )
                    } else if let testPath = ProcessInfo.processInfo.environment["PAOLA_SMOKE_STORE"] {
                        guard testPath.hasPrefix("/") else { throw CocoaError(.fileReadInvalidFileName) }
                        opened = try StoreFactory.makeContainer(url: URL(fileURLWithPath: testPath))
                    } else {
                        opened = try StoreFactory.makeContainer()
                    }
                    #else
                    opened = try StoreFactory.makeContainer()
                    #endif
                }
                guard !Task.isCancelled, generation == attempt else { return }
                container = opened
                status = cloudEnabled ? "Archivio iCloud aperto; in attesa di trasferimento" : "Archivio locale"
            } catch is CancellationError {
                return
            } catch {
                guard generation == attempt else { return }
                container = nil
                errorMessage = error.localizedDescription
                status = "Archivio non disponibile"
            }
        }
    }

    func installRestoredStore(at url: URL) throws {
        guard !cloudEnabled else { throw StorageError.restoreWhileCloudEnabled }
        let restored = try StoreFactory.makeContainer(url: url)
        try StoreFactory.activateRestoredStore(at: url)
        container = restored
        generation = UUID()
        status = "Archivio locale ripristinato"
    }

    /// Reset totale: cancella TUTTI i dati (clienti, servizi, pacchetti, appuntamenti,
    /// movimenti, fatture), le credenziali Aruba dal Keychain e le impostazioni locali,
    /// riportando l'app allo stato di prima installazione. Operazione non reversibile.
    func resetEverything() throws {
        guard let container else { throw StorageError.resetWithoutArchive }
        // 1. Svuota l'archivio di dominio.
        try StoreFactory.eraseAllData(in: container.mainContext)
        // 2. Rimuove le credenziali Aruba dal Keychain.
        try ArubaCredentialsStore(secrets: KeychainSecretStore()).clear()
        // 3. Azzera profilo fiscale e preferenze salvate.
        StoreFactory.clearUserDefaults()
        // 4. Riapre l'archivio così la UI riparte pulita.
        generation = UUID()
        open()
    }
}

enum StorageError: LocalizedError {
    case invalidCloudConfiguration, unavailableAccount, restoreWhileCloudEnabled, resetWithoutArchive

    var errorDescription: String? {
        switch self {
        case .invalidCloudConfiguration:
            "Configurazione iCloud incompleta. Controlla container, capability e firma in Xcode."
        case .unavailableAccount:
            "Account iCloud non disponibile. Accedi nelle impostazioni del dispositivo e riprova."
        case .restoreWhileCloudEnabled:
            "Il ripristino sostitutivo e' disponibile solo nell'archivio locale, per evitare sovrascritture su iCloud."
        case .resetWithoutArchive:
            "Archivio non disponibile: impossibile eseguire il reset."
        }
    }
}
