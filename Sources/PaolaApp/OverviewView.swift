import PaolaCore
import SwiftData
import SwiftUI

struct OverviewView: View {
    @Query private var clients: [Client]
    @Query private var entries: [LedgerEntry]
    @Query private var sessions: [TrainingSession]
    @Query private var participants: [SessionParticipant]
    @Query private var blocks: [Unavailability]
    @Query private var expenses: [Expense]
    let addClient: () -> Void
    @State private var creatingSession = false
    @State private var creatingPackage = false

    private var readError: Error? {
        let errors: [Error?] = [
            _clients.fetchError, _entries.fetchError, _sessions.fetchError, _participants.fetchError,
            _blocks.fetchError, _expenses.fetchError
        ]
        return errors.compactMap { $0 }.first
    }

    var body: some View {
        Group {
            if let error = readError {
                ArchiveReadErrorView(error: error)
            } else {
                TimelineView(.periodic(from: .now, by: 60)) { timeline in
                    dashboard(at: timeline.date)
                }
            }
        }
        .sectionTitle(.overview)
        .sheet(isPresented: $creatingSession) { SessionEditor() }
        .sheet(isPresented: $creatingPackage) { PackageEditor() }
    }

    @ViewBuilder
    private func dashboard(at now: Date) -> some View {
        switch Result(catching: {
            try OverviewSummary(entries: entries, sessions: sessions, participants: participants,
                                expenses: expenses, now: now)
        }) {
        case .failure(let error):
            ArchiveReadErrorView(error: error)
        case .success(let summary):
            // GeometryReader esterno alla ScrollView verticale: riceve la larghezza
            // dal contenitore (non collassa) e permette il layout proporzionale.
            GeometryReader { geo in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        shortcuts
                        dashboardBody(summary, width: min(geo.size.width, 1200))
                    }
                    .padding(24)
                    .frame(maxWidth: 1200)
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    /// Layout a due colonne basato sulla larghezza disponibile.
    /// Appuntamenti a destra (1/4 su schermi ampi, fino a 1/3 sui piccoli),
    /// contatori a sinistra col resto dello spazio. Impilati sotto una soglia.
    @ViewBuilder
    private func dashboardBody(_ summary: OverviewSummary, width: CGFloat) -> some View {
        let spacing: CGFloat = 20
        // Larghezza del contenuto: larghezza disponibile meno il padding orizzontale.
        let available = width - 48
        if available < 620 {
            VStack(alignment: .leading, spacing: spacing) {
                metricsColumn(summary)
                upcomingColumn(summary)
            }
        } else {
            let fraction: CGFloat = available >= 900 ? 0.25 : (1.0 / 3.0)
            let upcomingWidth = available * fraction
            HStack(alignment: .top, spacing: spacing) {
                metricsColumn(summary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                upcomingColumn(summary)
                    .frame(width: upcomingWidth, alignment: .leading)
            }
        }
    }

    // MARK: - Colonna sinistra: contatori compatti

    private func metricsColumn(_ summary: OverviewSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            metricGroup("Incassi", symbol: "arrow.down.circle.fill", tint: .green, rows: [
                ("Settimana", Money.format(summary.income.weeklyCents), "overview.income.week"),
                ("Mese", Money.format(summary.income.monthlyCents), "overview.income.month"),
                ("Anno", Money.format(summary.income.annualCents), "overview.income.year"),
                ("Futuri previsti", Money.format(summary.forecastCents), "overview.income.future")
            ])
            metricGroup("Spese", symbol: "arrow.up.circle.fill", tint: .orange, rows: [
                ("Settimana", Money.format(summary.income.weeklyExpensesCents), "overview.expenses.week"),
                ("Mese", Money.format(summary.income.monthlyExpensesCents), "overview.expenses.month"),
                ("Anno", Money.format(summary.income.annualExpensesCents), "overview.expenses.year")
            ])
            metricGroup("EBIT", symbol: "chart.line.uptrend.xyaxis", tint: .blue, rows: [
                ("Mese", Money.format(summary.income.monthlyEbitCents), "overview.ebit.month"),
                ("Anno", Money.format(summary.income.annualEbitCents), "overview.ebit.year")
            ])
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("overview.metrics")
    }

    private func metricGroup(_ title: String, symbol: String, tint: Color,
                             rows: [(String, String, String)]) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Label(title, systemImage: symbol)
                    .font(.headline)
                    .foregroundStyle(tint)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(rows, id: \.2) { row in
                    HStack {
                        Text(row.0).font(.body).foregroundStyle(.secondary)
                        Spacer()
                        Text(row.1).font(.title3.weight(.semibold)).monospacedDigit()
                            .foregroundStyle(tint)
                            .lineLimit(1).minimumScaleFactor(0.6)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier(row.2)
                }
            }
            .padding(.vertical, 6)
        }
        .backgroundStyle(tint.opacity(0.08))
    }

    // MARK: - Colonna destra: prossimi appuntamenti

    private func upcomingColumn(_ summary: OverviewSummary) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                compactCounter("Appuntamenti futuri", summary.futureAppointmentsCount.formatted(),
                               "person.badge.clock", tint: .indigo)
                    .accessibilityIdentifier("overview.week.futureSessions")
                compactCounter("Clienti settimana", summary.bookedClientsThisWeek.formatted(),
                               "person.2", tint: .teal)
                    .accessibilityIdentifier("overview.week.clients")
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("overview.row.week")
            upcomingList(summary.upcoming)
        }
    }

    private func compactCounter(_ title: String, _ value: String, _ symbol: String,
                                tint: Color) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                Label(title, systemImage: symbol)
                    .font(.caption).foregroundStyle(tint)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(value).font(.title2.weight(.semibold)).foregroundStyle(tint)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        }
        .backgroundStyle(tint.opacity(0.08))
        .accessibilityElement(children: .combine)
    }

    private func upcomingList(_ days: [UpcomingDay]) -> some View {
        GroupBox("Prossimi appuntamenti") {
            if days.isEmpty {
                Text("Nessun appuntamento in programma.").foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
            } else {
                // Due colonne parallele: oggi a sinistra, domani a destra.
                HStack(alignment: .top, spacing: 12) {
                    ForEach(days) { day in
                        dayColumn(day).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.top, 8)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("overview.row.upcoming")
    }

    private func dayColumn(_ day: UpcomingDay) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(dayHeader(day.date))
                .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(day.sessions) { session in
                NavigationLink {
                    SessionDetailView(session: session)
                } label: {
                    upcomingRow(session)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("overview.appointment.\(session.id.uuidString)")
            }
        }
    }

    /// Riga compatta di un appuntamento nella Overview: orario, clienti e stato,
    /// più contenuta della riga usata in agenda.
    private func upcomingRow(_ session: TrainingSession) -> some View {
        var seen = Set<UUID>()
        let people = participants.filter { $0.sessionID == session.id }
            .filter { seen.insert($0.clientID).inserted }
        let conflict = !BusinessDates.conflicts(for: session, sessions: sessions, blocks: blocks).isEmpty
        // Se un partecipante usa un pacchetto, mostra l'icona senza prezzo;
        // altrimenti mostra il totale degli addebiti (euro interi, senza centesimi).
        let usesPackage = people.contains { $0.packageID != nil }
        let priceCents = people.filter { $0.packageID == nil }.reduce(Int64(0)) { $0 + $1.priceCents }
        return HStack(alignment: .bottom, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(SchedulingSuggestions.hourLabel(session.startDate))
                    .font(.caption.weight(.semibold)).monospacedDigit().foregroundStyle(.secondary)
                if people.isEmpty {
                    Text("Cliente non disponibile").font(.subheadline).foregroundStyle(.orange)
                } else {
                    ForEach(people) { person in
                        upcomingName(for: person)
                    }
                }
                if conflict {
                    Label("Sovrapposizione", systemImage: "exclamationmark.triangle")
                        .font(.caption2).foregroundStyle(.orange)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Prezzo o icona pacchetto, ancorati in basso a destra, stessa altezza.
            Group {
                if usesPackage {
                    Image(systemName: "rectangle.stack.fill")
                        .foregroundStyle(.blue)
                        .accessibilityLabel("Pacchetto in uso")
                } else {
                    Text(euroLabel(priceCents))
                        .foregroundStyle(.primary)
                        .accessibilityLabel("Prezzo \(euroLabel(priceCents))")
                }
            }
            .font(.subheadline.weight(.semibold)).monospacedDigit()
        }
        .padding(.vertical, 6).padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
        .accessibilityElement(children: .combine)
        .accessibilityValue(session.status.title)
    }

    /// Nome sopra e cognome sotto per il partecipante indicato.
    @ViewBuilder
    private func upcomingName(for person: SessionParticipant) -> some View {
        if let client = clients.first(where: { $0.id == person.clientID }) {
            VStack(alignment: .leading, spacing: 0) {
                Text(client.firstName).font(.subheadline)
                Text(client.lastName).font(.subheadline)
            }
        } else {
            Text(person.clientName).font(.subheadline)
        }
    }

    /// Importo in euro interi, senza centesimi (es. "45 €").
    private func euroLabel(_ cents: Int64) -> String {
        "\(cents / 100) €"
    }

    /// Intestazione del giorno con nome (es. "Oggi", "Domani" o "Lunedì 5 maggio").
    private func dayHeader(_ date: Date) -> String {
        let calendar = SchedulingSuggestions.calendar
        if calendar.isDateInToday(date) { return "Oggi" }
        if calendar.isDateInTomorrow(date) { return "Domani" }
        let label = date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "it_IT")))
        return label.prefix(1).uppercased() + label.dropFirst()
    }

    private var shortcuts: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { shortcutButtons }
            VStack(alignment: .leading, spacing: 12) { shortcutButtons }
        }
        .buttonStyle(.borderedProminent)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("overview.row.shortcuts")
    }

    @ViewBuilder
    private var shortcutButtons: some View {
        Button("Nuovo appuntamento", systemImage: "calendar.badge.plus") { creatingSession = true }
            .accessibilityIdentifier("dashboard.newSession")
        Button("Nuovo cliente", systemImage: "person.badge.plus", action: addClient)
            .accessibilityIdentifier("overview.newClient")
        Button("Nuovo pacchetto", systemImage: "rectangle.stack.badge.plus") { creatingPackage = true }
            .accessibilityIdentifier("overview.newPackage")
    }

}
