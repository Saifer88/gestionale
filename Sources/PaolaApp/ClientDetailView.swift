import PaolaCore
import SwiftData
import SwiftUI

struct ClientDetailView: View {
    @Environment(\.modelContext) private var context
    let client: Client
    /// True quando la scheda è aperta da un appuntamento (SessionDetailView). In questo
    /// caso i percorsi che riportano a una lezione sono disattivati per evitare un ciclo
    /// di navigazione Cliente↔Lezione, che su macOS manda in freeze la NavigationStack.
    var isNested = false
    @Query private var services: [TrainingService]
    @Query private var rates: [ServiceRate]
    @Query private var sessions: [TrainingSession]
    @Query private var participants: [SessionParticipant]
    @Query private var packages: [LessonPackage]
    @Query private var ledgerEntries: [LedgerEntry]
    @State private var showingEditor = false
    @State private var editingAnamnesis: Anamnesis?
    @State private var deletingAnamnesis: Anamnesis?
    @State private var confirmingArchive = false
    @State private var formError: FormError?
    @State private var savedButRefreshFailed = false
    @State private var creatingSession = false
    @State private var creatingPackage = false

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    if !client.isArchived { quickActions }
                    quadrants(width: geo.size.width)
                    archiveSection
                }
                .padding(20)
                .frame(maxWidth: 1100)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle(client.fullName)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Modifica") { showingEditor = true }
            }
        }
        .sheet(isPresented: $showingEditor) {
            ClientEditor(client: client)
        }
        .sheet(item: $editingAnamnesis) { version in
            AnamnesisEditor(client: client, version: version)
        }
        .confirmationDialog("Eliminare questa anamnesi?",
                            isPresented: Binding(get: { deletingAnamnesis != nil },
                                                 set: { if !$0 { deletingAnamnesis = nil } }),
                            titleVisibility: .visible) {
            Button("Elimina", role: .destructive) {
                if let version = deletingAnamnesis { deleteAnamnesis(version) }
                deletingAnamnesis = nil
            }
            Button("Annulla", role: .cancel) { deletingAnamnesis = nil }
        } message: {
            Text("La versione selezionata verrà rimossa. Le altre versioni restano invariate. L'azione non è reversibile.")
        }
        .sheet(isPresented: $creatingSession) {
            SessionEditor(clientID: client.id)
        }
        .sheet(isPresented: $creatingPackage) {
            PackageEditor(clientID: client.id)
        }
        .confirmationDialog(
            client.isArchived ? "Riattivare il cliente?" : "Archiviare il cliente?",
            isPresented: $confirmingArchive,
            titleVisibility: .visible
        ) {
            Button(client.isArchived ? "Riattiva" : "Archivia", action: toggleArchive)
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("I dati e le note vengono conservati.")
        }
        .alert(savedButRefreshFailed ? "Dati salvati" : "Operazione non riuscita", isPresented: Binding(
            get: { formError != nil },
            set: { if !$0 { formError = nil } }
        )) {
            Button("OK", role: .cancel) { formError = nil }
        } message: {
            Text(formError?.message ?? "")
        }
    }

    // MARK: - Intestazione e azioni

    private var header: some View {
        HStack(spacing: 16) {
            ClientAvatar(client: client, size: 64)
            VStack(alignment: .leading, spacing: 6) {
                Text(client.fullName).font(.title2.bold()).textSelection(.enabled)
                Label(client.isArchived ? "Cliente archiviato" : "Cliente attivo",
                      systemImage: client.isArchived ? "archivebox" : "checkmark.circle")
                    .font(.subheadline)
                    .foregroundStyle(client.isArchived ? Color.secondary : .teal)
            }
            Spacer()
        }
    }

    private var quickActions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { quickActionButtons }
            VStack(alignment: .leading, spacing: 12) { quickActionButtons }
        }
        .buttonStyle(.borderedProminent)
    }

    @ViewBuilder
    private var quickActionButtons: some View {
        Button { creatingSession = true } label: {
            Label("Nuovo appuntamento", systemImage: "calendar.badge.plus")
        }
        .accessibilityIdentifier("client.newAppointment")
        Button { creatingPackage = true } label: {
            Label("Nuovo pacchetto", systemImage: "rectangle.stack.badge.plus")
        }
        .accessibilityIdentifier("client.newPackage")
    }

    // MARK: - Quattro quadranti (2x2)

    @ViewBuilder
    private func quadrants(width: CGFloat) -> some View {
        let stacked = width < 720
        if stacked {
            VStack(alignment: .leading, spacing: 16) {
                anagraficaQuadrant
                informazioniQuadrant
                anamnesiQuadrant
                saldiQuadrant
            }
        } else {
            VStack(spacing: 16) {
                HStack(alignment: .top, spacing: 16) {
                    anagraficaQuadrant.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    informazioniQuadrant.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .top, spacing: 16) {
                    anamnesiQuadrant.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    saldiQuadrant.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // Alto-sinistra: Anagrafica.
    private var anagraficaQuadrant: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                quadrantTitle("Anagrafica", systemImage: "person.text.rectangle", tint: .teal)
                infoRow("Nome", client.firstName)
                infoRow("Cognome", client.lastName)
                infoRow("Data di nascita", client.birthDate.map {
                    $0.formatted(.dateTime.day().month(.wide).year())
                } ?? "—")
                infoRow("Telefono", client.phone.isEmpty ? "—" : client.phone)
                infoRow("Email", client.email.isEmpty ? "—" : client.email)
                infoRow("Codice fiscale", client.taxCode.isEmpty ? "—" : client.taxCode)
                infoRow("Indirizzo", client.billingAddress.isEmpty ? "—" : client.billingAddress)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
            .textSelection(.enabled)
        }
        .accessibilityIdentifier("client.anagrafica")
    }

    // Alto-destra: Informazioni (preferenze + rapporto professionale).
    private var informazioniQuadrant: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                quadrantTitle("Informazioni", systemImage: "info.circle", tint: .blue)
                if let error = _services.fetchError ?? _rates.fetchError {
                    Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                } else if let serviceID = client.preferredServiceID {
                    let service = services.first { $0.id == serviceID }
                    infoRow("Servizio preferito", service.map {
                        $0.name + ($0.isActive ? "" : " · disattivato")
                    } ?? "Non disponibile")
                    let choices = service.map { ServiceTariffs.options(for: $0, rates: rates) } ?? []
                    let preferred = choices.first { $0.id == client.preferredRateID }
                    infoRow("Tariffa preferita", client.preferredRateID == nil
                        ? "Predefinita del servizio"
                        : preferred.map { "\($0.name) · \(Money.format($0.priceCents))" } ?? "Non disponibile")
                } else {
                    infoRow("Preferenze", "Ultime scelte disponibili")
                }
                Divider()
                infoRow("Cliente dal", client.joinedOn.formatted(.dateTime.day().month(.wide).year()))
                infoRow("Scheda creata", client.createdAt.formatted(.dateTime.day().month().year()))
                infoRow("Ultima modifica", client.updatedAt.formatted(.dateTime.day().month().year().hour().minute()))
                if !client.notes.isEmpty {
                    Divider()
                    Text("Note").font(.caption).foregroundStyle(.secondary)
                    Text(client.notes).textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
        }
        .accessibilityIdentifier("client.informazioni")
    }

    // Basso-sinistra: Anamnesi versionata (elenco versioni + aggiungi nuova).
    private var anamnesiQuadrant: some View {
        let history = AnamnesisHistory.parse(client.anamnesis)
        return GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                quadrantTitle("Anamnesi", systemImage: "heart.text.square", tint: .pink)
                if history.isEmpty {
                    Text("Nessuna anamnesi inserita.")
                        .font(.callout).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(history.versions) { version in
                        HStack {
                            Button {
                                editingAnamnesis = version
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(version.title.isEmpty ? "Anamnesi" : version.title)
                                        Text(version.date.formatted(.dateTime.day().month(.wide).year()))
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Button(role: .destructive) {
                                deletingAnamnesis = version
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.red)
                            .help("Elimina questa anamnesi")
                            .accessibilityIdentifier("client.anamnesis.delete.\(version.id.uuidString)")
                        }
                        .contextMenu {
                            Button("Modifica") { editingAnamnesis = version }
                            Button("Elimina", role: .destructive) { deletingAnamnesis = version }
                        }
                        .accessibilityIdentifier("client.anamnesis.version.\(version.id.uuidString)")
                    }
                }
                Button {
                    editingAnamnesis = Anamnesis()
                } label: {
                    Label("Nuova anamnesi", systemImage: "plus.circle")
                }
                .accessibilityIdentifier("client.anamnesis.new")
                if !client.physicalAnalysis.isEmpty {
                    Divider()
                    Text("Analisi fisica").font(.caption).foregroundStyle(.secondary)
                    Text(client.physicalAnalysis).textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
        }
        .accessibilityIdentifier("client.anamnesi")
    }

    // Basso-destra: Saldi (contatori + link rapidi del conto).
    private var saldiQuadrant: some View {
        let totals = BusinessReports.clientTotals(clientID: client.id, sessions: sessions,
                                                  participants: participants, packages: packages)
        return GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                quadrantTitle("Saldi", systemImage: "eurosign.circle", tint: .green)
                if _sessions.fetchError == nil && _participants.fetchError == nil && _packages.fetchError == nil {
                    infoRow("Lezioni non pagate", "\(totals.unpaidCount)")
                    infoRow("Lezioni fatte", "\(totals.completedCount)")
                    infoRow("Valore totale appuntamenti e pacchetti", Money.format(totals.totalValueCents))
                } else {
                    Label("Dati non disponibili", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
                Divider()
                BalanceLabel(cents: BusinessReports.balance(clientID: client.id, entries: ledgerEntries))
                if !isNested {
                    accountLink("Saldo e cronologia movimenti", "eurosign.circle", .clientPayments(client.id))
                    accountLink("Pacchetti e utilizzi", "square.stack.3d.up", .clientPackages(client.id))
                    accountLink("Storico appuntamenti", "calendar", .clientSessions(client.id))
                    accountLink("Estratto conto ed esportazione", "doc.text", .clientReports(client.id))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
        }
        .accessibilityIdentifier("client.saldi")
    }

    private var archiveSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                confirmingArchive = true
            } label: {
                Label(client.isArchived ? "Riattiva cliente" : "Archivia cliente",
                      systemImage: client.isArchived ? "arrow.uturn.backward" : "archivebox")
            }
            .accessibilityIdentifier("client.archive")
            Text("L'archiviazione conserva tutti i dati. Puoi riattivare il cliente in qualsiasi momento.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Helper di layout

    private func quadrantTitle(_ title: String, systemImage: String, tint: Color) -> some View {
        Label(title, systemImage: systemImage)
            .font(.headline).foregroundStyle(tint)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.subheadline).multilineTextAlignment(.trailing)
        }
    }

    private func accountLink(_ title: String, _ symbol: String, _ route: AppRoute) -> some View {
        NavigationLink(value: route) {
            Label(title, systemImage: symbol)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func deleteAnamnesis(_ version: Anamnesis) {
        var history = AnamnesisHistory.parse(client.anamnesis)
        history.remove(version.id)
        var draft = ClientDraft(client: client)
        draft.anamnesis = history.serialized()
        do {
            _ = try ClientRepository(context: context).save(draft, updating: client)
        } catch {
            formError = FormError(error)
        }
    }

    private func toggleArchive() {
        savedButRefreshFailed = false
        do {
            try ClientRepository(context: context).setArchived(!client.isArchived, for: client)
        } catch let error as ClientPersistenceError {
            savedButRefreshFailed = true
            formError = FormError(error)
        } catch {
            formError = FormError(error)
        }
    }
}
