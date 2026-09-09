import PaolaCore
import SwiftData
import SwiftUI

struct ClientsView: View {
    @Query(sort: [SortDescriptor(\Client.lastName), SortDescriptor(\Client.firstName)])
    private var clients: [Client]
    @State private var searchText = ""
    @State private var filter: ClientFilter = .active
    @State private var showingNewClient = false

    private var filteredClients: [Client] {
        clients.filter { ClientSearch.matches($0, query: searchText, filter: filter) }
    }

    var body: some View {
        if let error = _clients.fetchError {
            ArchiveReadErrorView(error: error)
                .navigationTitle("Clienti")
        } else {
            clientList
        }
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
        .navigationTitle("Clienti")
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
