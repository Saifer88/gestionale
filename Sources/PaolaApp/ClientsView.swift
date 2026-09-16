import PaolaCore
import SwiftData
import SwiftUI

struct ClientsView: View {
    @Query(sort: [SortDescriptor(\Client.lastName), SortDescriptor(\Client.firstName)])
    private var clients: [Client]
    @Query private var sessions: [TrainingSession]
    @Query private var participants: [SessionParticipant]
    @State private var searchText = ""
    @State private var filter: ClientFilter = .active
    @State private var showingNewClient = false

    private var filteredClients: [Client] {
        clients.filter { ClientSearch.matches($0, query: searchText, filter: filter) }
    }

    /// Importo "da incassare" (appuntamenti completati non pagati) per cliente.
    private var unpaidByClient: [UUID: UnpaidClientSummary] {
        Dictionary(
            BusinessReports.unpaidCompletedByClient(sessions: sessions, participants: participants)
                .map { ($0.clientID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    var body: some View {
        if let error = _clients.fetchError ?? _sessions.fetchError ?? _participants.fetchError {
            ArchiveReadErrorView(error: error)
                .navigationTitle("Clienti")
        } else {
            clientList
        }
    }

    /// Badge "da incassare" con importo e numero di lezioni completate non pagate.
    private func unpaidBadge(_ due: UnpaidClientSummary) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(Money.format(due.residualCents))
                .font(.subheadline.weight(.semibold)).monospacedDigit()
                .foregroundStyle(.orange)
            Text("\(due.sessionCount) da incassare")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("clients.unpaid.\(due.clientID.uuidString)")
    }

    private var clientList: some View {
        VStack(spacing: 0) {
            Picker("Mostra clienti", selection: $filter) {
                ForEach(ClientFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            if filteredClients.isEmpty {
                ContentUnavailableView {
                    Label(clients.isEmpty ? "La tua anagrafica inizia qui" : "Nessun cliente trovato",
                          systemImage: "person.crop.rectangle.badge.plus")
                } description: {
                    Text(clients.isEmpty
                         ? "Aggiungi un cliente per conservare recapiti e note organizzative."
                         : "Prova a cambiare la ricerca o il filtro.")
                } actions: {
                    if clients.isEmpty {
                        Button("Nuovo cliente") { showingNewClient = true }
                            .buttonStyle(.borderedProminent)
                    }
                }
                .frame(maxHeight: .infinity)
            } else {
                let unpaid = unpaidByClient
                List(filteredClients) { client in
                    NavigationLink {
                        ClientDetailView(client: client)
                    } label: {
                        HStack(spacing: 12) {
                            ClientAvatar(client: client)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(client.fullName)
                                    .font(.headline)
                                if !client.phone.isEmpty {
                                    Label(client.phone, systemImage: "phone")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else if !client.email.isEmpty {
                                    Text(client.email)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if let due = unpaid[client.id] {
                                unpaidBadge(due)
                            }
                            if client.isArchived {
                                Label("Archiviato", systemImage: "archivebox")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 5)
                    }
                }
                .listStyle(.plain)
            }

            HStack {
                Text("Clienti visualizzati: \(filteredClients.count)")
                Spacer()
                Label("Locale", systemImage: "internaldrive")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding()
        }
        .sectionTitle(.clients)
        .searchable(text: $searchText, prompt: "Nome, telefono o email")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingNewClient = true
                } label: {
                    Label("Nuovo cliente", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
        .sheet(isPresented: $showingNewClient) {
            ClientEditor()
        }
    }
}
