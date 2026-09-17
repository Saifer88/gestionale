import PaolaCore
import SwiftData
import SwiftUI

/// Destinazioni di navigazione value-based. Tutti i percorsi usano un identificatore
/// stabile (UUID) invece dell'oggetto @Model: la destinazione viene costruita solo
/// quando l'utente naviga davvero (tramite `navigationDestination(for:)`), non durante
/// il layout delle celle. Questo evita il loop di layout di AppKit che, con push
/// annidati dentro NavigationSplitView su macOS, blocca l'app (freeze).
enum AppRoute: Hashable {
    case client(UUID)
    case session(UUID)
    case package(UUID)
    case ledgerEntry(UUID)
    case clientPayments(UUID)
    case clientPackages(UUID)
    case clientSessions(UUID)
    case clientReports(UUID)
    case clientAllocations(UUID)
    // Viste-sezione senza parametri (raggiunte da Impostazioni).
    case services
    case packagesAll
    case reportsAll
    case credentials
    case backup
}

extension View {
    /// Registra, una sola volta per NavigationStack, la risoluzione di tutti gli AppRoute.
    func appRouteDestinations() -> some View {
        navigationDestination(for: AppRoute.self) { route in
            AppRouteView(route: route)
        }
    }
}

/// Risolve un AppRoute nella vista di destinazione, caricando l'oggetto per id quando
/// necessario. Per gli id non più presenti mostra un avviso invece di bloccare.
struct AppRouteView: View {
    let route: AppRoute

    var body: some View {
        switch route {
        case .client(let id):
            ResolvedModelView(id: id, idOf: { $0.id }) { (client: Client) in ClientDetailView(client: client) }
        case .session(let id):
            ResolvedModelView(id: id, idOf: { $0.id }) { (session: TrainingSession) in SessionDetailView(session: session) }
        case .package(let id):
            ResolvedModelView(id: id, idOf: { $0.id }) { (package: LessonPackage) in PackageDetailView(package: package) }
        case .ledgerEntry(let id):
            ResolvedModelView(id: id, idOf: { $0.id }) { (entry: LedgerEntry) in LedgerEntryDetailView(entry: entry) }
        case .clientPayments(let id):
            PaymentsView(clientID: id)
        case .clientPackages(let id):
            PackagesView(clientID: id)
        case .clientSessions(let id):
            ClientSessionsView(clientID: id)
        case .clientReports(let id):
            ReportsView(clientID: id)
        case .clientAllocations(let id):
            ClientAllocationsView(clientID: id)
        case .services:
            ServicesView()
        case .packagesAll:
            PackagesView()
        case .reportsAll:
            ReportsView()
        case .credentials:
            CredentialsView()
        case .backup:
            BackupView()
        }
    }
}

/// Carica un modello persistente per id e costruisce la destinazione; se l'oggetto non
/// esiste più (eliminato o non ancora sincronizzato) mostra un messaggio non bloccante.
private struct ResolvedModelView<Model: PersistentModel, Destination: View>: View {
    let id: UUID
    let idOf: (Model) -> UUID
    @ViewBuilder let destination: (Model) -> Destination
    @Query private var models: [Model]

    var body: some View {
        if let model = models.first(where: { idOf($0) == id }) {
            destination(model)
        } else {
            ContentUnavailableView("Elemento non disponibile", systemImage: "questionmark.folder",
                                   description: Text("L'elemento non è più presente nell'archivio."))
        }
    }
}
