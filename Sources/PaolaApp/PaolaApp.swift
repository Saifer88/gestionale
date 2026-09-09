import PaolaCore
import SwiftData
import SwiftUI

@main
struct PaolaApp: App {
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
        #endif
        .task {
            if storage.container == nil && storage.errorMessage == nil {
                storage.open()
            }
        }
    }
}
