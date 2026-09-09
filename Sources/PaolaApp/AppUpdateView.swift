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
            .disabled(updater.isBusy)
            .accessibilityIdentifier("update.check")

            statusView
        } header: {
            Text("Aggiornamenti")
        } footer: {
            Text("Il controllo interroga le release pubblicate su GitHub. L'aggiornamento è assistito: l'app scarica e verifica il nuovo pacchetto, poi apri il Finder per sostituire manualmente “Paola Gestionale.app”. La build è firmata solo ad hoc, quindi macOS potrebbe chiedere conferma all'apertura.")
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
        // Istruzioni finali quando il pacchetto è pronto nel Finder.
        .alert("Pacchetto pronto",
               isPresented: Binding(get: { isReady },
                                    set: { if !$0 { updater.reset() } })) {
            Button("OK", role: .cancel) { updater.reset() }
        } message: {
            Text("La nuova versione è stata scaricata e verificata. Nel Finder appena aperto, chiudi questa app e trascina “Paola Gestionale.app” in Applicazioni sostituendo quella esistente, poi riaprila.")
        }
    }

    private var isReady: Bool {
        if case .ready = updater.phase { return true }
        return false
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
        case .ready:
            Label("Pacchetto pronto nel Finder.", systemImage: "shippingbox")
                .font(.caption).foregroundStyle(.secondary)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.caption).foregroundStyle(.orange)
        }
    }
}
#endif
