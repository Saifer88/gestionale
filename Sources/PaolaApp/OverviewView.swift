import PaolaCore
import SwiftData
import SwiftUI

struct OverviewView: View {
    @Query(sort: \Client.createdAt, order: .reverse) private var clients: [Client]
    @Query private var entries: [LedgerEntry]
    let openClients: () -> Void
    let addClient: () -> Void

    private var activeClients: [Client] { clients.filter { !$0.isArchived } }

    var body: some View {
        if let error = _clients.fetchError ?? _entries.fetchError {
            ArchiveReadErrorView(error: error)
                .navigationTitle("Panoramica")
        } else {
            overview
        }
    }

    private var overview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("IL TUO STUDIO, IN ORDINE")
                        .font(.caption.weight(.semibold))
                        .tracking(1.5)
                        .foregroundStyle(.teal)
                    Text("Spazio alle persone.")
                        .font(.largeTitle.bold())
                    Text("Agenda, clienti e conti in un unico posto.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                TimelineView(.periodic(from: .now, by: 60)) { timeline in
                    incomeCards(now: timeline.date)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], spacing: 14) {
                    metric("Clienti attivi", value: activeClients.count.formatted(), symbol: "person.2.fill")
                    metric("Clienti archiviati", value: (clients.count - activeClients.count).formatted(), symbol: "archivebox")
                    metric("Clienti totali", value: clients.count.formatted(), symbol: "person.crop.rectangle.stack")
                }

                BusinessDashboard()

                GroupBox {
                    VStack(alignment: .leading, spacing: 16) {
                        Label("La tua anagrafica", systemImage: "person.text.rectangle")
                            .font(.headline)
                        Text(clients.isEmpty
                             ? "Aggiungi il primo cliente. Potrai aggiornare recapiti e note, cercarlo e archiviarlo senza perdere i dati."
                             : "Gestisci recapiti, note organizzative e stato dei tuoi clienti.")
                            .foregroundStyle(.secondary)
                        ViewThatFits(in: .horizontal) {
                            HStack {
                                clientActions
                            }
                            VStack(alignment: .leading) {
                                clientActions
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                }

                if !activeClients.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Clienti aggiunti di recente")
                            .font(.headline)
                        ForEach(Array(activeClients.prefix(4))) { client in
                            NavigationLink {
                                ClientDetailView(client: client)
                            } label: {
                                HStack(spacing: 12) {
                                    ClientAvatar(client: client)
                                    Text(client.fullName)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(.secondary)
                                }
                                .padding(12)
                                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Il tuo archivio")
                        .font(.headline)
                    Text("Gli incassi sono registrati con i pacchetti e con il completamento delle lezioni singole. Nessun pagamento reale viene eseguito. Gli estratti sono documenti non fiscali.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    LocalStorageNotice()
                    Text("Conserva un backup cifrato e usa dati di prova fino al collaudo sui tuoi dispositivi.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(24)
            .frame(maxWidth: 950, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Panoramica")
    }

    @ViewBuilder
    private var clientActions: some View {
        Button(action: addClient) {
            Label("Nuovo cliente", systemImage: "plus")
        }
        .buttonStyle(.borderedProminent)
        Button("Apri clienti", action: openClients)
            .buttonStyle(.bordered)
    }

    @ViewBuilder
    private func incomeCards(now: Date) -> some View {
        switch Result(catching: { try IncomeSummary(entries: entries, now: now) }) {
        case .success(let totals):
            VStack(alignment: .leading, spacing: 8) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], spacing: 14) {
                    metric("Incassi annuali", value: Money.format(totals.annualCents), symbol: "calendar")
                        .accessibilityIdentifier("overview.income.year")
                    metric("Incassi mensili", value: Money.format(totals.monthlyCents), symbol: "calendar")
                        .accessibilityIdentifier("overview.income.month")
                    metric("Incassi settimanali", value: Money.format(totals.weeklyCents), symbol: "calendar")
                        .accessibilityIdentifier("overview.income.week")
                }
                Text("Anno, mese e settimana correnti (lunedì–domenica). Incassi lordi; i rimborsi sono esposti separatamente nei report.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        case .failure(let error):
            ArchiveReadErrorView(error: error)
        }
    }

    private func metric(_ title: String, value: String, symbol: String) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Label(title, systemImage: symbol)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.largeTitle.weight(.semibold))
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
        .accessibilityElement(children: .combine)
    }
}
