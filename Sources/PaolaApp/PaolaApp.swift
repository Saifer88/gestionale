import Combine
import PaolaCore
import SwiftData
import SwiftUI
#if os(macOS)
import AppKit
#endif

@main
struct PaolaApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif

    var body: some Scene {
        #if os(macOS)
        Window("Paola Gestionale", id: "main") {
            content
        }
        .defaultSize(width: 1100, height: 760)
        #else
        WindowGroup {
            content
        }
        #endif
    }

    private var content: some View {
        ApplicationRoot()
            .tint(.teal)
            .environment(\.locale, Locale(identifier: "it_IT"))
    }
}

private struct ApplicationRoot: View {
    @StateObject private var storage = StorageCoordinator()
    #if os(macOS)
    @StateObject private var updater = AppUpdater()
    #endif
    @State private var askBackupPassword = false
    @State private var backupPasswordChecked = false

    var body: some View {
        Group {
            if let container = storage.container {
                AppLockView {
                    AppNavigation()
                        .modelContainer(container)
                        .id(storage.generation)
                }
            } else if let startupError = storage.errorMessage {
                ContentUnavailableView {
                    Label("Archivio non disponibile", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text("Impossibile aprire i dati. Nessun archivio temporaneo e' stato creato.")
                    Text(startupError)
                        .textSelection(.enabled)
                } actions: {
                    Button("Riprova", action: storage.open)
                        .buttonStyle(.borderedProminent)
                }
            } else {
                ProgressView("Apertura archivio...")
            }
        }
        .environmentObject(storage)
        .disabled(storage.maintenanceMessage != nil)
        .overlay {
            if let message = storage.maintenanceMessage {
                ZStack {
                    Rectangle().fill(.regularMaterial).ignoresSafeArea()
                    ProgressView(message).padding(32)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 780, minHeight: 560)
        // Il controllo aggiornamenti vive a livello root, indipendente dallo stato
        // dell'archivio: la richiesta d'installazione appare anche se i dati non si
        // aprono. Il prompt e l'updater condiviso sono disponibili anche nelle Impostazioni.
        .environmentObject(updater)
        .appUpdatePrompt(updater)
        // Controllo all'apertura dell'app.
        .task { await updater.checkOnActivation() }
        // Controllo a ogni riattivazione (click sull'icona nel Dock, ritorno in primo
        // piano) anche se l'app è già in esecuzione.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await updater.checkOnActivation() }
        }
        // Controllo automatico periodico ogni ora mentre l'app resta aperta.
        .onReceive(Timer.publish(every: 60 * 60, tolerance: 60, on: .main, in: .common).autoconnect()) { _ in
            Task { await updater.checkOnActivation() }
        }
        #endif
        .task {
            if storage.container == nil && storage.errorMessage == nil {
                storage.open()
            }
        }
        // Backup automatico giornaliero: quando l'archivio è pronto, al primo avvio del
        // giorno esegue il backup se la password è impostata, altrimenti chiede di impostarla.
        .task(id: storage.container == nil) {
            handleDailyBackup()
        }
        .sheet(isPresented: $askBackupPassword) {
            BackupPasswordPrompt(onSaved: {
                askBackupPassword = false
                runAutoBackup()
            }, onSkip: {
                askBackupPassword = false
            })
        }
    }

    /// Decide cosa fare al primo avvio del giorno riguardo al backup automatico.
    private func handleDailyBackup() {
        guard let container = storage.container, !backupPasswordChecked else { return }
        guard !AutoBackupService.alreadyRanToday() else { backupPasswordChecked = true; return }
        backupPasswordChecked = true
        if AutoBackupService.isConfigured() {
            AutoBackupService.runIfNeeded(context: container.mainContext)
        } else {
            // Password non impostata: chiedila una volta.
            askBackupPassword = true
        }
    }

    private func runAutoBackup() {
        guard let container = storage.container else { return }
        AutoBackupService.runIfNeeded(context: container.mainContext)
    }
}

/// Dialog che chiede la password del backup automatico e la salva in Keychain.
private struct BackupPasswordPrompt: View {
    let onSaved: () -> Void
    let onSkip: () -> Void
    @State private var password = ""
    @State private var confirmation = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Password del backup (almeno 12 caratteri)", text: $password)
                    SecureField("Ripeti la password", text: $confirmation)
                } footer: {
                    Text("Usata per cifrare i backup automatici giornalieri, salvati nella cartella dell'app. La password è conservata nel Keychain del dispositivo. Puoi cambiarla nelle impostazioni di backup.")
                }
                if let error {
                    Text(error).foregroundStyle(.orange).font(.caption)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Backup automatico")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Più tardi") { onSkip() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Attiva") { save() }
                }
            }
        }
        .frame(minWidth: 420, minHeight: 320)
    }

    private func save() {
        guard password == confirmation else { error = "Le password non coincidono."; return }
        do {
            try BackupPasswordStore(secrets: KeychainSecretStore()).save(password)
            onSaved()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

#if os(macOS)
/// Mantiene l'app in esecuzione quando si chiude la finestra: l'icona resta nel Dock
/// e cliccandola la finestra viene riaperta. L'uscita vera resta disponibile da
/// menu/⌘Q e dalla chiusura forzata dell'aggiornamento (NSApp.terminate).
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Se non c'è una finestra visibile, ripristina/porta in primo piano quella principale.
        if !flag {
            for window in sender.windows where window.canBecomeMain {
                window.deminiaturize(nil)
                window.makeKeyAndOrderFront(nil)
            }
            sender.activate(ignoringOtherApps: true)
        }
        return true
    }
}
#endif
