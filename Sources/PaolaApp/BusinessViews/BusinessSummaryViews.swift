import PaolaCore
import SwiftData
import SwiftUI

struct ClientBusinessSection: View {
    let client: Client
    /// Sola lettura: nasconde i link verso Pacchetti/Storico appuntamenti (che
    /// navigano alle lezioni). Usato quando la scheda è mostrata in uno sheet da un
    /// appuntamento, per non riaprire la catena di navigazione verso le lezioni.
    var readOnly = false
    @Query private var entries: [LedgerEntry]
    @Query private var packages: [LessonPackage]
    @Query private var uses: [PackageUse]
    @Query private var sessions: [TrainingSession]
    @Query private var participants: [SessionParticipant]

    private var clientPackages: [LessonPackage] { packages.filter { $0.clientID == client.id } }
    private var availableLessons: Int {
        clientPackages.filter { $0.expiresOn.map { BusinessDates.exclusiveEnd($0) > Date() } ?? true }
            .reduce(0) { $0 + BusinessReports.remaining(package: $1, uses: uses) }
    }

    private var unpaidSessions: [UnpaidSession] {
        BusinessReports.unpaidCompletedSessions(clientID: client.id, sessions: sessions, participants: participants)
    }
    private var unpaidTotalCents: Int64 {
        unpaidSessions.reduce(0) { $0 + $1.residualCents }
    }

    var body: some View {
        Section {
            if let error = _entries.fetchError ?? _packages.fetchError ?? _uses.fetchError {
                ArchiveReadErrorView(error: error)
            } else {
                BalanceLabel(cents: BusinessReports.balance(clientID: client.id, entries: entries))
                LabeledContent("Lezioni residue non scadute", value: "\(availableLessons)")
                if !readOnly {
                    NavigationLink(value: AppRoute.clientPayments(client.id)) {
                        Label("Saldo e cronologia movimenti", systemImage: "eurosign.circle")
                    }
                    NavigationLink(value: AppRoute.clientPackages(client.id)) {
                        Label("Pacchetti e utilizzi", systemImage: "square.stack.3d.up")
                    }
                    NavigationLink(value: AppRoute.clientSessions(client.id)) {
                        Label("Storico appuntamenti", systemImage: "calendar")
                    }
                    NavigationLink(value: AppRoute.clientReports(client.id)) {
                        Label("Estratto conto ed esportazione", systemImage: "doc.text")
                    }
                }
            }
        } header: {
            Text("Lezioni e conto cliente")
        } footer: {
            Text(client.isArchived
                 ? "Il cliente è archiviato: appuntamenti, pacchetti e movimenti restano consultabili. Sono disponibili le rettifiche."
                 : "Gli incassi si registrano con i pacchetti e al completamento delle lezioni senza pacchetto.")
        }

        if _sessions.fetchError == nil && _participants.fetchError == nil && !unpaidSessions.isEmpty {
            Section {
                // Righe informative (non navigabili): il dettaglio dei singoli appuntamenti
                // è raggiungibile da "Storico appuntamenti" qui sopra. Evitiamo un link a
                // SessionDetailView, che chiuderebbe un ciclo di navigazione Cliente↔Lezione.
                ForEach(unpaidSessions) { unpaid in
                    unpaidRow(unpaid)
                }
                LabeledContent("Totale non pagato") {
                    Text(Money.format(unpaidTotalCents)).monospacedDigit().font(.headline)
                        .foregroundStyle(.orange)
                }
                .accessibilityIdentifier("client.unpaid.total")
            } header: {
                Text("Appuntamenti completati non pagati")
            } footer: {
                Text("Lezioni singole completate con addebito ancora aperto. Le lezioni coperte da pacchetto non compaiono.")
            }
        }
    }

    private func unpaidRow(_ unpaid: UnpaidSession) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(unpaid.serviceName.isEmpty ? "Appuntamento" : unpaid.serviceName).font(.body)
                Text(BusinessFormatting.day(unpaid.date))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(Money.format(unpaid.residualCents)).monospacedDigit().foregroundStyle(.orange)
        }
        .accessibilityIdentifier("client.unpaid.\(unpaid.sessionID.uuidString)")
    }
}
