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
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    incomeRow(summary)
                    expensesRow(summary)
                    ebitRow(summary)
                    HStack(alignment: .top, spacing: 14) {
                        metric("Utenti prenotati settimana in corso",
                               value: summary.bookedClientsThisWeek.formatted(), symbol: "person.2")
                            .accessibilityIdentifier("overview.week.clients")
                        metric("Lezioni programmate settimana in corso",
                               value: summary.plannedSessionsThisWeek.formatted(), symbol: "calendar")
                            .accessibilityIdentifier("overview.week.sessions")
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("overview.row.week")
                    todayRow(summary.today)
                    shortcuts
                }
                .padding(24)
                .frame(maxWidth: 1200)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func incomeRow(_ summary: OverviewSummary) -> some View {
        GeometryReader { geometry in
            let width = max(155, (geometry.size.width - 42) / 4)
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 14) {
                    metric("Incassi settimanali", value: Money.format(summary.income.weeklyCents), symbol: "calendar")
                        .frame(width: width).accessibilityIdentifier("overview.income.week")
                    metric("Incassi mensili", value: Money.format(summary.income.monthlyCents), symbol: "calendar")
                        .frame(width: width).accessibilityIdentifier("overview.income.month")
                    metric("Incassi annuali", value: Money.format(summary.income.annualCents), symbol: "calendar")
                        .frame(width: width).accessibilityIdentifier("overview.income.year")
                    metric("Incassi Futuri previsti", value: Money.format(summary.forecastCents), symbol: "chart.line.uptrend.xyaxis")
                        .frame(width: width).accessibilityIdentifier("overview.income.future")
                        .help("Somma dei prezzi delle lezioni programmate con inizio futuro, esclusi i pacchetti già incassati. Non è un incasso registrato né un utile.")
                }
            }
            .accessibilityIdentifier("overview.row.income")
        }
        .frame(height: 154)
    }

    private func expensesRow(_ summary: OverviewSummary) -> some View {
        GeometryReader { geometry in
            let width = max(155, (geometry.size.width - 28) / 3)
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 14) {
                    metric("Spese settimanali", value: Money.format(summary.income.weeklyExpensesCents), symbol: "banknote")
                        .frame(width: width).accessibilityIdentifier("overview.expenses.week")
                    metric("Spese mensili", value: Money.format(summary.income.monthlyExpensesCents), symbol: "banknote")
                        .frame(width: width).accessibilityIdentifier("overview.expenses.month")
                    metric("Spese annuali", value: Money.format(summary.income.annualExpensesCents), symbol: "banknote")
                        .frame(width: width).accessibilityIdentifier("overview.expenses.year")
                }
            }
            .accessibilityIdentifier("overview.row.expenses")
        }
        .frame(height: 154)
    }

    private func ebitRow(_ summary: OverviewSummary) -> some View {
        GeometryReader { geometry in
            let width = max(155, (geometry.size.width - 28) / 3)
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 14) {
                    metric("EBIT mensile", value: Money.format(summary.income.monthlyEbitCents), symbol: "chart.line.uptrend.xyaxis")
                        .frame(width: width).accessibilityIdentifier("overview.ebit.month")
                    metric("EBIT annuale", value: Money.format(summary.income.annualEbitCents), symbol: "chart.line.uptrend.xyaxis")
                        .frame(width: width).accessibilityIdentifier("overview.ebit.year")
                }
            }
            .accessibilityIdentifier("overview.row.ebit")
        }
        .frame(height: 154)
        .help("EBIT = incassi del periodo meno spese del periodo.")
    }

    private func todayRow(_ appointments: [TrainingSession]) -> some View {
        GroupBox("Appuntamenti del giorno") {
            VStack(alignment: .leading, spacing: 12) {
                if appointments.isEmpty {
                    Text("Nessun appuntamento oggi.").foregroundStyle(.secondary)
                }
                ForEach(appointments) { session in
                    NavigationLink {
                        SessionDetailView(session: session)
                    } label: {
                        CalendarSessionRow(session: session, participants: participants, clients: clients,
                            conflict: !BusinessDates.conflicts(for: session, sessions: sessions, blocks: blocks).isEmpty)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("overview.appointment.\(session.id.uuidString)")
                    if session.id != appointments.last?.id { Divider() }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("overview.row.today")
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

    private func metric(_ title: String, value: String, symbol: String) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Label(title, systemImage: symbol)
                    .font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 42, alignment: .topLeading)
                Text(value)
                    .font(.largeTitle.weight(.semibold))
                    .lineLimit(1).minimumScaleFactor(0.55)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
        .accessibilityElement(children: .combine)
    }
}
