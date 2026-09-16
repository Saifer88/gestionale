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
