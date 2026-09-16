import PaolaCore
import SwiftData
import SwiftUI

struct ClientBusinessSection: View {
    let client: Client
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
                NavigationLink {
                    PaymentsView(clientID: client.id)
                } label: {
                    Label("Saldo e cronologia movimenti", systemImage: "eurosign.circle")
                }
                NavigationLink {
                    PackagesView(clientID: client.id)
                } label: {
                    Label("Pacchetti e utilizzi", systemImage: "square.stack.3d.up")
                }
                NavigationLink {
                    ClientSessionsView(clientID: client.id)
                } label: {
                    Label("Storico appuntamenti", systemImage: "calendar")
                }
                NavigationLink {
                    ReportsView(clientID: client.id)
                } label: {
                    Label("Estratto conto ed esportazione", systemImage: "doc.text")
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
                ForEach(unpaidSessions) { unpaid in
                    if let session = sessions.first(where: { $0.id == unpaid.sessionID }) {
                        NavigationLink {
                            SessionDetailView(session: session)
                        } label: {
                            unpaidRow(unpaid)
                        }
                    } else {
                        unpaidRow(unpaid)
                    }
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
