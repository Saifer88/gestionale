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
    @State private var conversionInput = ""
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
                    //.frame(maxWidth: 1200)
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
            let fraction: CGFloat = 1.0 / 3.0
            let upcomingWidth = available * fraction
            HStack(alignment: .top, spacing: spacing) {
                metricsColumn(summary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                upcomingColumn(summary)
                    .frame(width: upcomingWidth, alignment: .leading)
            }
        }
    }

    // MARK: - Conversioni

    /// Importi lordi fissi (centesimi): 600, 450, 60, 40 €.
    private let conversionGrossRows: [Int64] = [60000, 45000, 6000, 4000]

    /// Tabella "Conversioni": per ogni lordo, incremento del netto per metodo d'incasso
    /// (contanti=nero, bianco, carta, Stripe). Mostrata per prima ed evidenziata.
    private var conversionsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Conversioni").font(.title3.weight(.semibold))
            VStack(spacing: 0) {
                conversionHeaderRow
                Divider()
                ForEach(Array(conversionGrossRows.enumerated()), id: \.offset) { _, gross in
                    conversionValueRow(grossCents: gross)
                    Divider()
                }
                conversionInputRow
            }
            .padding(12)
            .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.accentColor.opacity(0.35), lineWidth: 1))
        }
        .accessibilityIdentifier("overview.conversions.table")
    }

    /// Cella conversione: testo + tooltip (operazioni) opzionale.
    private struct ConvCell { let text: String; let help: String? }

    private func conversionRow(label: String, values: [ConvCell], isHeader: Bool) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(isHeader ? .caption.weight(.semibold) : .body.monospacedDigit())
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(Array(values.enumerated()), id: \.offset) { _, cell in
                Text(cell.text)
                    .font(isHeader ? .caption.weight(.semibold) : .body.monospacedDigit())
                    .foregroundStyle(isHeader ? Color.secondary : Color.primary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .contentShape(Rectangle())
                    .modifier(HoverTooltip(text: cell.help))
            }
        }
        .padding(.vertical, 4)
    }

    /// Intestazione conversioni: Contanti senza formula; Bianco/Carta/Stripe con formule.
    private var conversionHeaderRow: some View {
        conversionRow(label: "Lordo", values: [
            ConvCell(text: "Contanti", help: nil),
            ConvCell(text: "Bianco", help: ConversionRates.whiteFormula),
            ConvCell(text: "Carta", help: ConversionRates.cardFormula),
            ConvCell(text: "Stripe", help: ConversionRates.stripeFormula)
        ], isHeader: true)
    }

    private func conversionValueRow(grossCents: Int64) -> some View {
        conversionRow(
            label: Money.format(grossCents),
            values: [
                ConvCell(text: Money.format(ConversionRates.cash(grossCents)), help: nil),
                ConvCell(text: Money.format(ConversionRates.white(grossCents)), help: ConversionRates.whiteSteps(grossCents)),
                ConvCell(text: Money.format(ConversionRates.card(grossCents)), help: ConversionRates.cardSteps(grossCents)),
                ConvCell(text: Money.format(ConversionRates.stripe(grossCents)), help: ConversionRates.stripeSteps(grossCents))
            ],
            isHeader: false
        )
    }

    private var conversionInputRow: some View {
        let gross = (try? Money.parse(conversionInput)) ?? 0
        let hasValue = !conversionInput.trimmingCharacters(in: .whitespaces).isEmpty && gross > 0
        return HStack(spacing: 8) {
            TextField("Inserisci", text: $conversionInput)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("overview.conversions.input")
            cell(hasValue ? Money.format(ConversionRates.cash(gross)) : "—", help: nil, active: hasValue)
            cell(hasValue ? Money.format(ConversionRates.white(gross)) : "—",
                 help: hasValue ? ConversionRates.whiteSteps(gross) : nil, active: hasValue)
            cell(hasValue ? Money.format(ConversionRates.card(gross)) : "—",
                 help: hasValue ? ConversionRates.cardSteps(gross) : nil, active: hasValue)
            cell(hasValue ? Money.format(ConversionRates.stripe(gross)) : "—",
                 help: hasValue ? ConversionRates.stripeSteps(gross) : nil, active: hasValue)
        }
        .padding(.vertical, 4)
    }

    /// Cella valore della riga di input.
    private func cell(_ text: String, help: String?, active: Bool) -> some View {
        Text(text)
            .font(.body.monospacedDigit())
            .foregroundStyle(active ? Color.primary : Color.secondary)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .contentShape(Rectangle())
            .modifier(HoverTooltip(text: help))
    }

    // MARK: - Colonna sinistra: contatori compatti

    private func metricsColumn(_ summary: OverviewSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Spese attività a sinistra, tabella Conversioni affiancata a destra.
            HStack(alignment: .top, spacing: 12) {
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
                       /* metricGroup("EBIT", symbol: "chart.line.uptrend.xyaxis", tint: .blue, rows: [
                            ("Mese", Money.format(summary.income.monthlyEbitCents), "overview.ebit.month"),
                            ("Anno", Money.format(summary.income.annualEbitCents), "overview.ebit.year")
                        ])
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)*/
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                conversionsCard
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }

            // Netto affiancato a Bilancio personale.
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    sectionTitle("Netto")
                    netGroup(summary)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                VStack(alignment: .leading, spacing: 8) {
                    sectionTitle("Spese personali")
                    personalBalanceGroup(summary)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .fixedSize(horizontal: false, vertical: true)
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
        // Tooltip di intestazione (formule generiche) per Neri/Bianchi/INPS/Imposte.
        let headerHelp: [String?] = [nil, nil, TaxBreakdown.inpsFormula, TaxBreakdown.taxFormula]
        return GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                netRow(label: "", minor: minorColumns.map { NetCell(text: $0.0, help: nil) },
                       net: NetCell(text: "Netto", help: nil), isHeader: true,
                       headerHelp: headerHelp, netHeaderHelp: TaxBreakdown.netFormula)
                netRow(label: "Mese", minor: netCells(summary.income.monthlyTax, minorColumns),
                       net: NetCell(text: Money.format(summary.income.monthlyTax.netCents),
                                    help: summary.income.monthlyTax.netSteps))
                    .accessibilityIdentifier("overview.net.month")
                netRow(label: "Anno", minor: netCells(summary.income.annualTax, minorColumns),
                       net: NetCell(text: Money.format(summary.income.annualTax.netCents),
                                    help: summary.income.annualTax.netSteps))
                    .accessibilityIdentifier("overview.net.year")
            }
            .padding(.vertical, 6)
        }
        .backgroundStyle(Color.purple.opacity(0.08))
        .accessibilityIdentifier("overview.net")
    }

    /// Cella della tabella Netto: testo mostrato e tooltip (operazioni) opzionale.
    private struct NetCell { let text: String; let help: String? }

    /// Celle valore di una riga (Mese/Anno) con i tooltip delle operazioni reali su
    /// INPS e Imposte (Neri/Bianchi non hanno operazioni: sono somme dirette).
    private func netCells(_ tax: TaxBreakdown,
                          _ columns: [(String, KeyPath<TaxBreakdown, Int64>)]) -> [NetCell] {
        columns.map { title, keyPath in
            let help: String?
            switch title {
            case "INPS": help = tax.inpsSteps
            case "Imposte": help = tax.taxSteps
            default: help = nil
            }
            return NetCell(text: euroLabel(tax[keyPath: keyPath]), help: help)
        }
    }

    /// Una riga della tabella Netto: etichetta + colonne minori strette + colonna Netto
    /// grande (evidenziata). La colonna Netto usa un font maggiore, come i contatori.
    /// I tooltip (operazioni in colonna) compaiono al passaggio del mouse.
    private func netRow(label: String, minor: [NetCell], net: NetCell, isHeader: Bool = false,
                        headerHelp: [String?] = [], netHeaderHelp: String? = nil) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                .frame(width: 34, alignment: .leading)
            ForEach(Array(minor.enumerated()), id: \.offset) { index, cell in
                let tip = isHeader ? (index < headerHelp.count ? headerHelp[index] : nil) : cell.help
                Text(cell.text)
                    .font(isHeader ? .caption2.weight(.semibold) : .caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .contentShape(Rectangle())
                    .modifier(HoverTooltip(text: tip))
            }
            // Colonna Netto: larga e in risalto.
            Text(net.text)
                .font(isHeader ? .subheadline.weight(.semibold) : .title3.weight(.semibold))
                .foregroundStyle(isHeader ? Color.secondary : Color.purple)
                .monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.5)
                .frame(width: 150, alignment: .trailing)
                .contentShape(Rectangle())
                .modifier(HoverTooltip(text: isHeader ? netHeaderHelp : net.help))
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
                compactCounter("Netto paga oraria", netHourlyLabel(summary.netHourlyCents),
                               "clock.badge.checkmark", tint: .green)
                    .accessibilityIdentifier("overview.week.netHourly")
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

    /// Netto orario formattato in €/h (es. "42 €/h"), oppure "—" se non calcolabile.
    private func netHourlyLabel(_ cents: Double?) -> String {
        guard let cents, cents > 0 else { return "—" }
        return "\(Int((cents / 100).rounded())) €"
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

/// Mostra un tooltip (operazioni in colonna) al passaggio del mouse tramite `popover`,
/// più affidabile di `.help` dentro liste/gruppi. Le righe sono separate da "\n".
private struct HoverTooltip: ViewModifier {
    let text: String?
    @State private var hovering = false
    func body(content: Content) -> some View {
        if let text, !text.isEmpty {
            content
                .onHover { hovering = $0 }
                .popover(isPresented: $hovering, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(text.split(separator: "\n", omittingEmptySubsequences: false).enumerated()), id: \.offset) { _, line in
                            // Ogni riga: "operatore\tdescrizione\tvalore". Operatore e
                            // descrizione a sinistra, valore/formula a destra. Riga con
                            // operatore "=" è il totale (in grassetto).
                            let cols = line.components(separatedBy: "\t")
                            let op = cols.count > 0 ? cols[0] : ""
                            let desc = cols.count > 1 ? cols[1] : ""
                            let value = cols.count > 2 ? cols[2] : ""
                            let isTotal = op == "="
                            HStack(spacing: 8) {
                                Text(op)
                                    .font(.caption.monospacedDigit())
                                    .frame(width: 14, alignment: .leading)
                                Text(desc)
                                    .font(isTotal ? .caption.weight(.bold) : .caption)
                                Spacer(minLength: 16)
                                Text(value)
                                    .font(isTotal ? .caption.weight(.bold).monospacedDigit() : .caption.monospacedDigit())
                            }
                        }
                    }
                    .padding(10)
                    .frame(minWidth: 220)
                }
        } else {
            content
        }
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
