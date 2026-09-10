import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case overview, agenda, clients, packages, payments, reports, services, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Panoramica"
        case .agenda: "Agenda"
        case .clients: "Clienti"
        case .packages: "Pacchetti"
        case .payments: "Pagamenti"
        case .reports: "Report"
        case .services: "Servizi"
        case .settings: "Impostazioni"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .agenda: "calendar"
        case .clients: "person.2"
        case .packages: "rectangle.stack"
        case .payments: "creditcard"
        case .reports: "chart.bar"
        case .services: "list.bullet.rectangle"
        case .settings: "gearshape"
        }
    }
}

extension View {
    /// Imposta il titolo nativo della schermata per la sezione indicata.
    func sectionTitle(_ section: AppSection) -> some View {
        navigationTitle(section.title)
    }
    /// Variante per titoli non legati a una sezione (es. dettaglio).
    func sectionTitle(_ title: String, symbol: String = "") -> some View {
        navigationTitle(title)
    }
}

struct AppNavigation: View {
    @State private var selectedSection: AppSection? = .overview
    @State private var showingNewClient = false

    var body: some View {
        navigation
            .sheet(isPresented: $showingNewClient) {
                ClientEditor()
            }
            .background(ReminderSchedulerView())
            .safeAreaInset(edge: .top, spacing: 0) {
                IntegrityStatusView()
            }
    }

    @ViewBuilder
    private var navigation: some View {
        #if os(macOS)
        NavigationSplitView {
            List(selection: $selectedSection) {
                Section("Il tuo studio") {
                    ForEach(AppSection.allCases.filter { $0 != .settings }) { section in
                        Label(section.title, systemImage: section.symbol)
                            .tag(section)
                    }
                }
                Section("Applicazione") {
                    Label(AppSection.settings.title, systemImage: AppSection.settings.symbol)
                        .tag(AppSection.settings)
                }
            }
            .navigationTitle("Paola Gestionale")
            .navigationSplitViewColumnWidth(min: 190, ideal: 225, max: 280)
            .safeAreaInset(edge: .bottom) {
                LocalStorageNotice().padding()
            }
        } detail: {
            NavigationStack {
                destination(selectedSection ?? .overview)
            }
            .id(selectedSection)
        }
        #else
        TabView(selection: $selectedSection) {
            ForEach([AppSection.overview, .agenda, .clients, .payments, .settings]) { section in
                NavigationStack {
                    destination(section)
                }
                .tabItem {
                    Label(section.title, systemImage: section.symbol)
                }
                .tag(Optional(section))
            }
        }
        #endif
    }

    @ViewBuilder
    private func destination(_ section: AppSection) -> some View {
        switch section {
        case .overview:
            OverviewView(addClient: { showingNewClient = true })
        case .clients:
            ClientsView()
        case .agenda:
            AgendaView()
        case .packages:
            PackagesView()
        case .payments:
            PaymentsView()
        case .reports:
            ReportsView()
        case .services:
            ServicesView()
        case .settings:
            SettingsView()
        }
    }
}
