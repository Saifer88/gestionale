#if os(macOS)
import PaolaCore
import SwiftUI

/// Sezione delle Impostazioni per controllare e preparare gli aggiornamenti dell'app.
struct AppUpdateSection: View {
    @StateObject private var updater = AppUpdater()

    var body: some View {
        Section {
            LabeledContent("Versione installata", value: updater.currentVersionText)

            Button {
                Task { await updater.checkForUpdates() }
            } label: {
                Label("Controlla aggiornamenti", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(updater.isBusy || updater.isLocalBuild)
            .accessibilityIdentifier("update.check")

            statusView
        } header: {
            Text("Aggiornamenti")
        } footer: {
            Text("Il controllo interroga le release pubblicate su GitHub. Se c'è una nuova versione, l'app la scarica, ne verifica l'integrità, apre la finestra di installazione (trascina l'app nella cartella Applicazioni) e si chiude automaticamente. La build è firmata solo ad hoc, quindi macOS potrebbe chiedere conferma alla prima apertura.")
        }
        // Conferma prima di scaricare la nuova versione.
        .alert("Aggiornamento disponibile",
               isPresented: Binding(get: { updater.availableRelease != nil },
                                    set: { if !$0 { updater.availableRelease = nil } })) {
            Button("Scarica e prepara") {
                if let release = updater.availableRelease {
                    Task { await updater.downloadAndPrepare(release) }
                }
            }
            Button("Più tardi", role: .cancel) { updater.availableRelease = nil }
        } message: {
            if let release = updater.availableRelease {
                Text("È disponibile la versione \(release.version.description) (attuale \(updater.currentVersionText)). Vuoi scaricarla e prepararla per l'installazione?")
            }
        }
        .onAppear { updater.prepareInitialState() }
    }

    @ViewBuilder
    private var statusView: some View {
        switch updater.phase {
        case .idle:
            EmptyView()
        case .checking:
            Label("Controllo in corso...", systemImage: "hourglass")
                .font(.caption).foregroundStyle(.secondary)
        case .downloading:
            HStack(spacing: 8) {
                ProgressView()
                Text("Download e verifica in corso...").font(.caption).foregroundStyle(.secondary)
            }
        case .upToDate:
            Label("L'app è aggiornata all'ultima versione.", systemImage: "checkmark.circle")
                .font(.caption).foregroundStyle(.secondary)
        case .localBuild:
            Label("Build locale di sviluppo: il controllo aggiornamenti è disattivato.", systemImage: "hammer")
                .font(.caption).foregroundStyle(.secondary)
        case .ready:
            Label("Installazione aperta. L'app si chiude per completare l'aggiornamento.", systemImage: "shippingbox")
                .font(.caption).foregroundStyle(.secondary)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.caption).foregroundStyle(.orange)
        }
    }
}
#endif
