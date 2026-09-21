import PaolaCore
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
    @Query private var packages: [LessonPackage]
    @Query private var courses: [Course]
    @Query private var courseParticipants: [CourseParticipant]
    let addClient: () -> Void
    @Environment(\.modelContext) private var context
    @State private var creatingSession = false
    @State private var creatingPackage = false
    @State private var payingClient: UnpaidClientSummary?
    @State private var operation = BusinessOperation()

    private var readError: Error? {
        let errors: [Error?] = [
            _clients.fetchError, _entries.fetchError, _sessions.fetchError, _participants.fetchError,
            _blocks.fetchError, _expenses.fetchError, _packages.fetchError,
            _courses.fetchError, _courseParticipants.fetchError
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
        .sheet(item: $payingClient) { client in
            SettleUnpaidView(
                clientName: client.clientName,
                unpaid: BusinessReports.unpaidCompletedSessions(
                    clientID: client.clientID, sessions: sessions, participants: participants),
                onConfirm: { ids in settleSessions(ids, clientID: client.clientID) }
            )
        }
        .businessError($operation)
    }

    private func settleSessions(_ ids: [UUID], clientID: UUID) {
        do { try BusinessRepository(context: context).setSessionsPaid(ids, clientID: clientID, true) }
        catch { operation.capture(error) }
    }

    @ViewBuilder
    private func dashboard(at now: Date) -> some View {
        switch Result(catching: {
            try OverviewSummary(entries: entries, sessions: sessions, participants: participants,
                                expenses: expenses, packages: packages,
                                courses: courses, courseParticipants: courseParticipants, now: now)
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
            sectionTitle("Spese attività")
            // Incassi, Spese ed EBIT affiancati, con la stessa altezza.
            HStack(alignment: .top, spacing: 12) {
                metricGroup("Incassi", symbol: "arrow.down.circle.fill", tint: .green, rows: [
                    ("Settimana", Money.format(summary.income.weeklyCents), "overview.income.week"),
                    ("Mese", Money.format(summary.income.monthlyCents), "overview.income.month"),
                    ("Anno", Money.format(summary.income.annualCents), "overview.income.year"),
                    ("Futuri previsti", Money.format(summary.forecastCents), "overview.income.future")
                ])
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                metricGroup("Spese", symbol: "arrow.up.circle.fill", tint: .orange, rows: [
                    ("Settimana", Money.format(summary.income.weeklyExpensesCents), "overview.expenses.week"),
                    ("Mese", Money.format(summary.income.monthlyExpensesCents), "overview.expenses.month"),
                    ("Anno", Money.format(summary.income.annualExpensesCents), "overview.expenses.year"),
                    ("Futuri previsti", Money.format(summary.income.futureExpensesCents), "overview.expenses.future")
                ])
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                metricGroup("EBIT", symbol: "chart.line.uptrend.xyaxis", tint: .blue, rows: [
                    ("Mese", Money.format(summary.income.monthlyEbitCents), "overview.ebit.month"),
                    ("Anno", Money.format(summary.income.annualEbitCents), "overview.ebit.year")
                ])
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .fixedSize(horizontal: false, vertical: true)
            // Netto a tutta larghezza.
            netGroup(summary)

            // Spese personali: bilancio personale = Netto − spese personali.
            sectionTitle("Spese personali")
            personalBalanceGroup(summary)
            unpaidGroup(summary.unpaidByClient)

        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("overview.metrics")
    }

    /// Titolo di sezione nella colonna metriche.
    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.title3.weight(.semibold))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
    }

    /// Riquadro "Bilancio personale": Netto − spese personali, mese e anno, stesso
    /// stile e regole degli altri riquadri economici.
    private func personalBalanceGroup(_ summary: OverviewSummary) -> some View {
        metricGroup("Bilancio personale", symbol: "person.crop.circle.badge.checkmark", tint: .pink, rows: [
            ("Mese", Money.format(summary.income.monthlyPersonalBalanceCents), "overview.personalBalance.month"),
            ("Anno", Money.format(summary.income.annualPersonalBalanceCents), "overview.personalBalance.year")
        ])
    }

    /// Gruppo "Netto" a tutta larghezza: neri, bianchi, INPS, imposte in colonne strette
    /// e la colonna finale Netto grande (come i contatori) così risalta. Righe mese/anno.
    private func netGroup(_ summary: OverviewSummary) -> some View {
        // Colonne "minori" (strette), poi la colonna Netto evidenziata a parte.
        let minorColumns: [(String, KeyPath<TaxBreakdown, Int64>)] = [
            ("Neri", \.blackCents), ("Bianchi", \.whiteCents),
            ("INPS", \.inpsCents), ("Imposte", \.taxCents)
        ]
        return GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Label("Netto", systemImage: "building.columns.fill")
                    .font(.headline).foregroundStyle(.purple)
                    .frame(maxWidth: .infinity, alignment: .leading)
                netRow(label: "", minor: minorColumns.map(\.0), net: "Netto", isHeader: true)
                netRow(label: "Mese",
                       minor: minorColumns.map { euroLabel(summary.income.monthlyTax[keyPath: $0.1]) },
                       net: Money.format(summary.income.monthlyTax.netCents))
                    .accessibilityIdentifier("overview.net.month")
                netRow(label: "Anno",
                       minor: minorColumns.map { euroLabel(summary.income.annualTax[keyPath: $0.1]) },
                       net: Money.format(summary.income.annualTax.netCents))
                    .accessibilityIdentifier("overview.net.year")
            }
            .padding(.vertical, 6)
        }
        .backgroundStyle(Color.purple.opacity(0.08))
        .accessibilityIdentifier("overview.net")
    }

    /// Una riga della tabella Netto: etichetta + colonne minori strette + colonna Netto
    /// grande (evidenziata). La colonna Netto usa un font maggiore, come i contatori.
    private func netRow(label: String, minor: [String], net: String, isHeader: Bool = false) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                .frame(width: 34, alignment: .leading)
            ForEach(Array(minor.enumerated()), id: \.offset) { _, value in
                Text(value)
                    .font(isHeader ? .caption2.weight(.semibold) : .caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            // Colonna Netto: larga e in risalto.
            Text(net)
                .font(isHeader ? .subheadline.weight(.semibold) : .title3.weight(.semibold))
                .foregroundStyle(isHeader ? Color.secondary : Color.purple)
                .monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.5)
                .frame(width: 150, alignment: .trailing)
        }
    }

    /// Gruppo "Da incassare": clienti con lezioni completate non pagate e residuo.
    @ViewBuilder
    private func unpaidGroup(_ clients: [UnpaidClientSummary]) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Label("Da incassare", systemImage: "exclamationmark.circle.fill")
                    .font(.headline).foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if clients.isEmpty {
                    Text("Nessuna lezione completata da incassare.")
                        .font(.callout).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(clients) { client in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(client.clientName.isEmpty ? "Cliente" : client.clientName).font(.body)
                                Text("\(client.sessionCount) \(client.sessionCount == 1 ? "lezione" : "lezioni")")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(Money.format(client.residualCents))
                                .font(.title3.weight(.semibold)).monospacedDigit()
                                .foregroundStyle(.red)
                                .lineLimit(1).minimumScaleFactor(0.6)
                            Button {
                                payingClient = client
                            } label: {
                                Label("Salda", systemImage: "eurosign.circle.fill")
                            }
                            .labelStyle(.titleAndIcon)
                            .buttonStyle(.borderless)
                            .tint(.green)
                            .help("Segna come pagate tutte le lezioni di \(client.clientName)")
                            .accessibilityIdentifier("overview.unpaid.settle.\(client.clientID.uuidString)")
                        }
                        .accessibilityIdentifier("overview.unpaid.\(client.clientID.uuidString)")
                    }
                }
            }
            .padding(.vertical, 6)
        }
        .backgroundStyle(Color.red.opacity(0.08))
        .accessibilityIdentifier("overview.unpaid")
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
            ForEach(day.items) { item in
                switch item {
                case .session(let session):
                    NavigationLink(value: AppRoute.session(session.id)) {
                        upcomingRow(session)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("overview.appointment.\(session.id.uuidString)")
                case .course(let occurrence):
                    NavigationLink(value: AppRoute.course(occurrence.course.id)) {
                        upcomingCourseRow(occurrence)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("overview.course.\(occurrence.course.id.uuidString)")
                }
            }
        }
    }

    /// Riga compatta di un'occorrenza di corso: orario, titolo, partecipanti, icona corso
    /// in basso a destra (coerente con l'agenda).
    private func upcomingCourseRow(_ occurrence: CourseOccurrence) -> some View {
        HStack(alignment: .bottom, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(SchedulingSuggestions.hourLabel(occurrence.start))
                    .font(.caption.weight(.semibold)).monospacedDigit().foregroundStyle(.secondary)
                Text(occurrence.course.title.isEmpty ? "Corso" : occurrence.course.title)
                    .font(.subheadline)
                if !occurrence.participantNames.isEmpty {
                    Text(occurrence.participantNames.joined(separator: ", "))
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.subheadline.weight(.semibold)).foregroundStyle(.purple)
                .accessibilityLabel("Corso")
        }
        .padding(.vertical, 6).padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.purple.opacity(0.10)))
        .accessibilityElement(children: .combine)
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

/// Conferma per saldare in blocco le lezioni completate non pagate di un cliente.
/// Mostra l'elenco delle lezioni che verranno impostate come pagate e il totale.
private struct SettleUnpaidView: View {
    @Environment(\.dismiss) private var dismiss
    let clientName: String
    let unpaid: [UnpaidSession]
    let onConfirm: ([UUID]) -> Void

    private var totalCents: Int64 { unpaid.reduce(0) { $0 + $1.residualCents } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(unpaid) { session in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.serviceName.isEmpty ? "Appuntamento" : session.serviceName)
                                Text(BusinessFormatting.day(session.date))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(Money.format(session.residualCents)).monospacedDigit()
                        }
                    }
                    LabeledContent("Totale") {
                        Text(Money.format(totalCents)).monospacedDigit().font(.headline)
                            .foregroundStyle(.orange)
                    }
                } header: {
                    Text("Lezioni da segnare come pagate")
                } footer: {
                    Text("Le seguenti lezioni completate di \(clientName) verranno impostate come pagate, azzerando l'importo da incassare.")
                }
            }
            .navigationTitle("Segna come pagate")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }.keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Conferma") {
                        onConfirm(unpaid.map(\.sessionID))
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(unpaid.isEmpty)
                    .accessibilityIdentifier("overview.unpaid.settle.confirm")
                }
            }
        }
        .businessEditorSize()
    }
}
