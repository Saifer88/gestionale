import PaolaCore
import SwiftData
import SwiftUI

struct ClientBusinessSection: View {
    let client: Client
    @Query private var entries: [LedgerEntry]
    @Query private var packages: [LessonPackage]
    @Query private var uses: [PackageUse]
    @State private var creatingSession = false

    private var clientPackages: [LessonPackage] { packages.filter { $0.clientID == client.id } }
    private var availableLessons: Int {
        clientPackages.filter { $0.expiresOn.map { BusinessDates.exclusiveEnd($0) > Date() } ?? true }
            .reduce(0) { $0 + BusinessReports.remaining(package: $1, uses: uses) }
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
                if !client.isArchived {
                    Button("Nuovo appuntamento", systemImage: "calendar.badge.plus") { creatingSession = true }
                }
            }
        } header: {
            Text("Lezioni e conto cliente")
        } footer: {
            Text(client.isArchived
                 ? "Il cliente è archiviato: appuntamenti, pacchetti e movimenti restano consultabili. Sono disponibili le rettifiche."
                 : "Gli incassi si registrano con i pacchetti e al completamento delle lezioni senza pacchetto.")
        }
        .sheet(isPresented: $creatingSession) { SessionEditor(clientID: client.id) }
    }
}

struct BusinessDashboard: View {
    @Query private var entries: [LedgerEntry]
    @Query(sort: \TrainingSession.startDate) private var sessions: [TrainingSession]
    @Query private var participants: [SessionParticipant]
    @Query private var blocks: [Unavailability]
    @State private var creatingSession = false

    private var monthInterval: DateInterval {
        Calendar.current.dateInterval(of: .month, for: Date())
            ?? DateInterval(start: BusinessDates.monthStart, end: BusinessDates.exclusiveEnd(Date()))
    }
    private var statistics: BusinessStatistics {
        BusinessReports.statistics(from: monthInterval.start, to: monthInterval.end,
                                   sessions: sessions, entries: entries)
    }
    private var balances: [Int64] {
        let currentEntries = entries.filter { $0.date <= Date() }
        return Set(currentEntries.map(\.clientID)).map {
            BusinessReports.balance(clientID: $0, entries: currentEntries)
        }
    }
    private var upcoming: [TrainingSession] {
        Array(sessions.filter { $0.status == .planned && $0.endDate >= Date() }.prefix(5))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let error = _entries.fetchError ?? _sessions.fetchError ?? _participants.fetchError ?? _blocks.fetchError {
                ArchiveReadErrorView(error: error)
            } else {
                GroupBox("Questo mese") {
                    VStack(spacing: 10) {
                        LabeledContent("Incassi registrati", value: Money.format(statistics.receivedCents))
                        LabeledContent("Rimborsi", value: Money.format(statistics.refundedCents))
                        LabeledContent("Lezioni completate", value: "\(statistics.completedSessions)")
                        LabeledContent("Ore lavorate") {
                            Text(statistics.workedMinutes / 60, format: .number.precision(.fractionLength(2)))
                        }
                        NavigationLink("Apri report del mese") { ReportsView() }
                    }
                    .padding(.top, 8)
                }
                GroupBox("Situazione conti attuale") {
                    VStack(alignment: .leading, spacing: 10) {
                        LabeledContent("Totale da saldare", value: Money.format(total(balances.filter { $0 > 0 })))
                        LabeledContent("Clienti con importi da saldare", value: "\(balances.filter { $0 > 0 }.count)")
                        LabeledContent("Credito a favore dei clienti",
                                       value: Money.format(total(balances.filter { $0 < 0 }.map { $0 == Int64.min ? Int64.max : -$0 })))
                        NavigationLink("Consulta pagamenti e movimenti") { PaymentsView() }
                    }
                    .padding(.top, 8)
                }
                GroupBox("Prossimi appuntamenti") {
                    VStack(alignment: .leading, spacing: 12) {
                        if upcoming.isEmpty {
                            Text("Non ci sono appuntamenti programmati.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(upcoming) { session in
                            NavigationLink {
                                SessionDetailView(session: session)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(BusinessFormatting.day(session.startDate))
                                        .font(.caption).foregroundStyle(.secondary)
                                    SessionSummaryRow(
                                        session: session, participants: participants,
                                        conflict: !BusinessDates.conflicts(for: session, sessions: sessions, blocks: blocks).isEmpty
                                    )
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            Divider()
                        }
                        NavigationLink("Apri agenda") { AgendaView() }
                    }
                    .padding(.top, 8)
                }
                ViewThatFits(in: .horizontal) {
                    HStack {
                        appointmentButton
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        appointmentButton
                    }
                }
            }
        }
        .sheet(isPresented: $creatingSession) { SessionEditor() }
    }

    private var appointmentButton: some View {
        Button { creatingSession = true } label: {
            Label("Nuovo appuntamento", systemImage: "calendar.badge.plus")
        }
        .buttonStyle(.borderedProminent)
        .accessibilityIdentifier("dashboard.newSession")
    }

    private func total(_ cents: [Int64]) -> Int64 {
        cents.reduce(0) { sum, value in
            let result = sum.addingReportingOverflow(value)
            return result.overflow ? Int64.max : result.partialValue
        }
    }
}
