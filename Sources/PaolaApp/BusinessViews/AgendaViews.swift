import PaolaCore
import SwiftData
import SwiftUI

private enum AgendaPeriod: String, CaseIterable, Identifiable {
    case day = "Giorno", week = "Settimana", month = "Mese"
    var id: String { rawValue }
    var component: Calendar.Component {
        switch self {
        case .day: return .day
        case .week: return .weekOfYear
        case .month: return .month
        }
    }
}

struct AgendaView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \TrainingSession.startDate) private var sessions: [TrainingSession]
    @Query private var participants: [SessionParticipant]
    @Query private var clients: [Client]
    @Query private var blocks: [Unavailability]
    @Query private var packages: [LessonPackage]
    @State private var period: AgendaPeriod = .week
    @State private var selectedDate = Date()
    @State private var status: SessionStatus?
    @State private var search = ""
    @State private var creatingSession = false
    @State private var operation = BusinessOperation()
    @State private var draggingSessionID: UUID?
    /// Fascia oraria scelta per creare un appuntamento da una casella del calendario.
    @State private var creationSlot: AgendaCreationSlot?

    private var interval: DateInterval {
        SchedulingSuggestions.calendar.dateInterval(of: period.component, for: selectedDate)
            ?? DateInterval(start: SchedulingSuggestions.calendar.startOfDay(for: selectedDate),
                            end: BusinessDates.exclusiveEnd(selectedDate))
    }
    private var visibleSessions: [TrainingSession] {
        let matchingPeople = Set(participants.filter {
            $0.clientName.localizedStandardContains(search)
        }.map(\.sessionID))
        return CalendarAppointments.visible(sessions, in: interval).filter {
            (status == nil || $0.status == status)
                && (search.isEmpty || $0.serviceName.localizedStandardContains(search) || matchingPeople.contains($0.id))
        }
    }
    private var days: [Date] {
        var result: [Date] = []
        var cursor = interval.start
        while cursor < interval.end {
            result.append(cursor)
            cursor = BusinessDates.exclusiveEnd(cursor)
        }
        return result
    }
    /// Giorni mostrati nella vista settimana: sabato e domenica compaiono solo se
    /// hanno almeno un appuntamento visibile.
    private var weekDays: [Date] {
        let calendar = SchedulingSuggestions.calendar
        return days.filter { day in
            let weekday = calendar.component(.weekday, from: day)
            let isWeekend = (weekday == 7 || weekday == 1) // 7 = sabato, 1 = domenica
            return !isWeekend || hasSessions(on: day)
        }
    }

    /// Vero se il giorno ha almeno un appuntamento visibile (usato per mostrare o
    /// nascondere le colonne del weekend nella vista settimana).
    private func hasSessions(on day: Date) -> Bool {
        let dayEnd = BusinessDates.exclusiveEnd(day)
        return visibleSessions.contains {
            BusinessDates.overlaps(day, dayEnd, $0.startDate, $0.endDate)
        }
    }

    var body: some View {
        Group {
            if let error = _sessions.fetchError ?? _participants.fetchError ?? _clients.fetchError {
                ArchiveReadErrorView(error: error)
            } else {
                agenda
            }
        }
        .sectionTitle(.agenda)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("agenda.screen")
        .searchable(text: $search, prompt: "Cliente o servizio")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    creatingSession = true
                } label: {
                    Label("Nuovo appuntamento", systemImage: "plus")
                }
                .accessibilityIdentifier("agenda.add")
            }
        }
        .sheet(isPresented: $creatingSession) { SessionEditor() }
        .sheet(item: $creationSlot) { slot in
            SessionEditor(startDate: slot.date)
        }
        .businessError($operation)
    }

    private var agenda: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Picker("Vista agenda", selection: $period) {
                        ForEach(AgendaPeriod.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("agenda.period")
                    Spacer(minLength: 12)
                    // Riepilogo del periodo in alto a destra: Totale, Bianco, Nero e barra.
                    totalsSummary
                }
                HStack {
                    Button { move(-1) } label: { Image(systemName: "chevron.left") }
                        .accessibilityLabel("Periodo precedente")
                    DatePicker("Data", selection: $selectedDate, displayedComponents: .date)
                    Button { move(1) } label: { Image(systemName: "chevron.right") }
                        .accessibilityLabel("Periodo successivo")
                    Button("Oggi") { selectedDate = Date() }
                }
                Text("\(BusinessFormatting.day(interval.start)) – \(BusinessFormatting.day(interval.end.addingTimeInterval(-1)))")
                    .font(.subheadline).foregroundStyle(.secondary)
                ViewThatFits(in: .horizontal) {
                    HStack { filters }
                    VStack(alignment: .leading) { filters }
                }
                Text("\(visibleSessions.count) appuntamenti · \(scheduledMinutes / 60) h \(scheduledMinutes % 60) min")
                    .font(.caption).foregroundStyle(.secondary)
                if draggingSessionID != nil {
                    HStack(spacing: 8) {
                        Image(systemName: "hand.draw")
                        Text("Spostamento in corso: rilascia su un orario evidenziato.")
                            .font(.caption)
                        Spacer()
                        Button("Annulla") { draggingSessionID = nil }
                            .buttonStyle(.borderless)
                            .accessibilityIdentifier("agenda.cancelDrag")
                    }
                    .padding(8)
                    .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
                }
            }
            .padding()
            Divider()
            if period == .week {
                weekColumns
            } else {
                List {
                    ForEach(days, id: \.self) { day in daySection(day) }
                }
            }
        }
    }

    @ViewBuilder
    private var filters: some View {
        Picker("Stato", selection: $status) {
            Text("Tutti gli stati").tag(nil as SessionStatus?)
            ForEach(SessionStatus.allCases.filter { $0 != .cancelled }) { Text($0.title).tag(Optional($0)) }
        }
    }

    private var scheduledMinutes: Int {
        visibleSessions.filter { $0.status == .planned || $0.status == .completed }
            .reduce(0) { $0 + $1.durationMinutes }
    }

    /// Somma in centesimi dei prezzi concordati dei partecipanti agli appuntamenti
    /// visibili nel periodo (giorno/settimana/mese). Esclude gli annullati e le assenze.
    /// Ripartizione del totale del periodo in bianco e nero. `bianco + nero == totale`.
    private struct AccountingTotals {
        var white: Int64 = 0
        var black: Int64 = 0
        var total: Int64 { white + black }
        mutating func add(_ cents: Int64, black isBlack: Bool) {
            if isBlack { black += cents } else { white += cents }
        }
    }

    /// Totale del periodo suddiviso in bianco/nero:
    /// - partecipanti agli appuntamenti visibili, ESCLUSI quelli coperti da un pacchetto
    ///   (già pagati con l'acquisto), attribuiti al colore dell'appuntamento;
    /// - pacchetti acquistati nel periodo, attribuiti al proprio colore.
    private var accountingTotals: AccountingTotals {
        var totals = AccountingTotals()
        let byID = Dictionary(uniqueKeysWithValues:
            visibleSessions.filter { $0.status != .cancelled && $0.status != .noShow }.map { ($0.id, $0) })
        for participant in participants where participant.packageID == nil {
            if let session = byID[participant.sessionID] {
                totals.add(participant.priceCents, black: session.isBlack)
            }
        }
        for package in packages where interval.start <= package.purchasedOn && package.purchasedOn < interval.end {
            totals.add(package.priceCents, black: package.isBlack)
        }
        return totals
    }

    private var totalCents: Int64 { accountingTotals.total }

    /// Riepilogo in alto a destra: Totale, Bianco e Nero (stessa dimensione del nome
    /// del giorno) con una barra che mostra le percentuali di bianco/nero sul totale.
    @ViewBuilder private var totalsSummary: some View {
        let totals = accountingTotals
        VStack(alignment: .trailing, spacing: 2) {
            LabeledContent {
                Text(Money.format(totals.total)).font(.headline).monospacedDigit()
            } label: {
                Text("Totale").font(.headline)
            }
            .accessibilityIdentifier("agenda.periodTotal")
            LabeledContent {
                Text(Money.format(totals.white)).font(.subheadline).monospacedDigit()
            } label: {
                Label("Bianco", systemImage: "circle.fill").font(.subheadline)
            }
            .accessibilityIdentifier("agenda.periodWhite")
            LabeledContent {
                Text(Money.format(totals.black)).font(.subheadline).monospacedDigit()
            } label: {
                Label("Nero", systemImage: "circle").font(.subheadline)
            }
            .accessibilityIdentifier("agenda.periodBlack")
            percentageBar(totals)
                .frame(width: 160)
                .padding(.top, 2)
        }
        .frame(maxWidth: 220)
    }

    /// Barra proporzionale bianco/nero sul totale. Se il totale è zero è vuota.
    @ViewBuilder private func percentageBar(_ totals: AccountingTotals) -> some View {
        let total = max(totals.total, 0)
        let whiteFraction = total > 0 ? Double(totals.white) / Double(total) : 0
        let whitePercent = Int((whiteFraction * 100).rounded())
        GeometryReader { geo in
            HStack(spacing: 0) {
                Rectangle().fill(Color.white)
                    .frame(width: geo.size.width * whiteFraction)
                Rectangle().fill(Color.black)
            }
        }
        .frame(height: 8)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.secondary.opacity(0.4), lineWidth: 1))
        .accessibilityLabel("Ripartizione: \(whitePercent) percento bianco, \(100 - whitePercent) percento nero")
        .accessibilityIdentifier("agenda.percentageBar")
    }

    private var weekColumns: some View {
        GeometryReader { geometry in
            let columns = weekDays
            let count = max(1, columns.count)
            let width = max(180, (geometry.size.width - 32 - CGFloat(count - 1) * 12) / CGFloat(count))
            ScrollView([.horizontal, .vertical]) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(columns, id: \.self) { day in
                        VStack(alignment: .leading, spacing: 8) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(SchedulingSuggestions.dayLabel(day)).font(.headline)
                                if SchedulingSuggestions.calendar.isDateInToday(day) {
                                    Text("Oggi").font(.caption.bold()).foregroundStyle(.teal)
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 46, alignment: .topLeading)
                            Divider()
                            ForEach(hourRows(on: day)) { row in
                                hourCell(row, compact: true)
                            }
                            Spacer(minLength: 8)
                        }
                        .padding(12)
                        .frame(width: width, alignment: .topLeading)
                        .frame(minHeight: max(160, geometry.size.height - 32), alignment: .topLeading)
                        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("agenda.weekColumn.\(SchedulingSuggestions.calendar.component(.weekday, from: day))")
                    }
                }
                .padding(16)
            }
            .accessibilityIdentifier("agenda.weekColumns")
        }
    }

    @ViewBuilder private func daySection(_ day: Date) -> some View {
        Section(BusinessFormatting.day(day)) {
            ForEach(hourRows(on: day)) { row in
                hourCell(row, compact: false)
                    .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
            }
        }
    }

    @ViewBuilder private func itemRow(_ session: TrainingSession) -> some View {
        // Il pulsante di conferma resta FUORI dal NavigationLink: dentro l'etichetta
        // di un NavigationLink un tocco aprirebbe comunque il dettaglio. Così invece
        // conferma direttamente (provvisorio -> programmato) senza altre schermate.
        // I controlli restano FUORI dal NavigationLink: dentro l'etichetta di un
        // NavigationLink un tocco aprirebbe comunque il dettaglio. Il pallino bianco/nero
        // sta in alto a destra; gli altri controlli (conferma, pagato) sotto di esso.
        HStack(alignment: .top, spacing: 8) {
            if session.status != .completed {
                // Maniglia di trascinamento: il drag parte da qui, così toccare il
                // resto della card apre il dettaglio senza spostare l'appuntamento.
                dragHandle(for: session)
                    .padding(.top, 2)
            }
            NavigationLink {
                SessionDetailView(session: session)
            } label: {
                CalendarSessionRow(
                    session: session, participants: participants, clients: clients,
                    conflict: !BusinessDates.conflicts(for: session, sessions: sessions, blocks: []).isEmpty
                )
            }
            .accessibilityIdentifier("agenda.appointment.\(session.id.uuidString)")
            VStack(alignment: .trailing, spacing: 8) {
                accountingDot(for: session)
                if session.status == .provisional {
                    // L'icona arancione (badge provvisorio) conferma l'appuntamento
                    // rendendolo programmato, direttamente e senza altre schermate.
                    Button {
                        confirmProvisional(session)
                    } label: {
                        Image(systemName: "calendar.badge.clock")
                            .font(.callout)
                            .foregroundStyle(.orange)
                            .padding(4)
                            .background(Color.orange.opacity(0.18), in: Circle())
                    }
                    .buttonStyle(.borderless)
                    .help("Conferma l'appuntamento provvisorio (lo rende programmato).")
                    .accessibilityLabel("Conferma appuntamento provvisorio")
                    .accessibilityIdentifier("session.confirmProvisional")
                }
                paidToggle(for: session)
            }
        }
    }

    /// Pallino "bianco/nero" in alto a destra del badge: un tocco commuta la
    /// ripartizione contabile dell'appuntamento (bianco ↔ nero), senza altre schermate.
    @ViewBuilder private func accountingDot(for session: TrainingSession) -> some View {
        Button {
            toggleAccounting(session)
        } label: {
            Circle()
                .fill(session.isBlack ? Color.black : Color.white)
                .frame(width: 16, height: 16)
                .overlay(Circle().stroke(Color.secondary, lineWidth: 1))
        }
        .buttonStyle(.borderless)
        .help(session.isBlack ? "Nero. Tocca per passare a bianco." : "Bianco. Tocca per passare a nero.")
        .accessibilityLabel(session.isBlack ? "Contabilità: nero" : "Contabilità: bianco")
        .accessibilityIdentifier("session.accountingDot")
    }

    /// Interruttore "pagato" a icona: attiva/disattiva il contrassegno di pagamento
    /// dell'appuntamento, senza aprire altre schermate e senza toccare i movimenti.
    @ViewBuilder private func paidToggle(for session: TrainingSession) -> some View {
        Button {
            togglePaid(session)
        } label: {
            Image(systemName: session.isPaid ? "eurosign.circle.fill" : "eurosign.circle")
                .font(.callout)
                .foregroundStyle(session.isPaid ? Color.green : Color.secondary)
                .padding(4)
                .background((session.isPaid ? Color.green : Color.secondary).opacity(0.15), in: Circle())
        }
        .buttonStyle(.borderless)
        .help(session.isPaid ? "Segnato come pagato. Tocca per annullare." : "Segna come pagato.")
        .accessibilityLabel(session.isPaid ? "Pagato" : "Non pagato")
        .accessibilityIdentifier("session.paidToggle")
    }

    /// Maniglia di ancoraggio per il trascinamento di un appuntamento. È l'unico
    /// elemento trascinabile della riga: prendendola si sposta l'appuntamento nel
    /// calendario, mentre il resto della card resta dedicato all'apertura del dettaglio.
    @ViewBuilder private func dragHandle(for session: TrainingSession) -> some View {
        Image(systemName: "line.3.horizontal")
            .font(.title3)
            .foregroundStyle(.secondary)
            .frame(width: 32, height: 32)
            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
            // onDrag con NSItemProvider è più affidabile di .draggable dentro le liste
            // e le viste con scorrimento. All'avvio segnala l'inizio del trascinamento.
            .onDrag {
                draggingSessionID = session.id
                return AgendaDragPayload.provider(for: session.id)
            }
            .help("Trascina per spostare l'appuntamento")
            .accessibilityLabel("Sposta appuntamento")
            .accessibilityIdentifier("agenda.dragHandle.\(session.id.uuidString)")
    }

    /// Conferma un appuntamento provvisorio rendendolo programmato.
    private func confirmProvisional(_ session: TrainingSession) {
        guard session.status == .provisional else { return }
        do { try BusinessRepository(context: context).setSessionStatus(session.id, to: .planned) }
        catch { operation.capture(error) }
    }

    /// Attiva/disattiva il contrassegno "pagato" dell'appuntamento.
    private func togglePaid(_ session: TrainingSession) {
        do { try BusinessRepository(context: context).setSessionPaid(session.id, !session.isPaid) }
        catch { operation.capture(error) }
    }

    /// Commuta la ripartizione contabile bianco/nero dell'appuntamento.
    private func toggleAccounting(_ session: TrainingSession) {
        do { try BusinessRepository(context: context).setSessionBlack(session.id, !session.isBlack) }
        catch { operation.capture(error) }
    }

    // MARK: - Drag & drop

    private func session(_ id: UUID) -> TrainingSession? { sessions.first { $0.id == id } }

    /// Righe orarie (7–21) di un giorno per la griglia del calendario. Applica il
    /// filtro stato/ricerca corrente agli appuntamenti mostrati.
    private func hourRows(on day: Date) -> [AgendaHourRow] {
        let dragged = draggingSessionID.flatMap { session($0) }
        return AgendaScheduling.hourRows(
            on: day,
            draggedSessionID: draggingSessionID,
            draggedDurationMinutes: dragged?.durationMinutes ?? 60,
            sessions: visibleSessions,
            blocks: blocks)
    }

    /// Casella di una fascia oraria: mostra l'orario, gli appuntamenti che iniziano
    /// in quell'ora (trascinabili) e, se vuota, un pulsante "+" per creare un nuovo
    /// appuntamento con data e ora già impostate. Durante il trascinamento diventa
    /// bersaglio di rilascio nella propria posizione oraria.
    @ViewBuilder private func hourCell(_ row: AgendaHourRow, compact: Bool) -> some View {
        let dragging = draggingSessionID != nil
        HStack(alignment: .top, spacing: 10) {
            Text(row.hourLabel)
                .font(.caption.weight(.semibold)).monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(row.sessions) { session in
                    itemRow(session)
                        .buttonStyle(.plain)
                        .padding(10)
                        .background(.background, in: RoundedRectangle(cornerRadius: 10))
                }
                if row.isEmpty {
                    emptyHourContent(row, dragging: dragging)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
        .modifier(HourDropModifier(row: row, dragging: dragging, onDrop: { drop(sessionID: $0, on: row) }))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("agenda.hourCell.\(SchedulingSuggestions.calendar.component(.weekday, from: row.start)).\(row.hour)")
    }

    /// Contenuto della fascia vuota: durante il drag mostra un bersaglio di rilascio,
    /// altrimenti il pulsante "+" per creare un appuntamento a quell'ora.
    @ViewBuilder private func emptyHourContent(_ row: AgendaHourRow, dragging: Bool) -> some View {
        if dragging {
            let occupied = row.occupantID != nil
            // Solo icona, nessun testo: frecce opposte per "sposta qui", scambio per
            // una fascia occupata, lucchetto per una non disponibile.
            Image(systemName: occupied ? "arrow.left.arrow.right" : (row.isFree ? "arrow.up.arrow.down" : "lock"))
                .font(.callout.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 30)
                .background(dropColor(row), in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(occupied ? Color.orange : (row.isFree ? Color.green : Color.secondary))
                .accessibilityLabel(occupied ? "Scambia con l'appuntamento a quest'ora"
                                    : (row.isFree ? "Sposta a quest'ora" : "Fascia non disponibile"))
        } else {
            Button {
                creationSlot = AgendaCreationSlot(date: row.start)
            } label: {
                Label("Aggiungi", systemImage: "plus")
                    .font(.caption)
                    .labelStyle(.iconOnly)
                    .frame(maxWidth: .infinity, minHeight: 30)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Nuovo appuntamento alle \(row.hourLabel)")
            .accessibilityLabel("Nuovo appuntamento alle \(row.hourLabel)")
            .accessibilityIdentifier("agenda.addAt.\(SchedulingSuggestions.calendar.component(.weekday, from: row.start)).\(row.hour)")
        }
    }

    private func dropColor(_ row: AgendaHourRow) -> Color {
        if row.occupantID != nil { return Color.orange.opacity(0.16) }
        return row.isFree ? Color.green.opacity(0.16) : Color.secondary.opacity(0.10)
    }

    /// Rilascio dell'appuntamento su una fascia oraria: sposta all'ora scelta oppure,
    /// se la fascia è occupata da un altro appuntamento, ne scambia gli orari.
    private func drop(sessionID: UUID, on row: AgendaHourRow) {
        draggingSessionID = nil
        guard let dragged = session(sessionID) else { return }
        if dragged.startDate == row.start { return }
        let repository = BusinessRepository(context: context)
        do {
            if let occupantID = row.occupantID, occupantID != sessionID,
               let occupant = session(occupantID) {
                // Scambio di posto: i due appuntamenti si scambiano l'orario di inizio.
                let draggedStart = dragged.startDate
                let occupantStart = occupant.startDate
                try repository.rescheduleSession(sessionID, to: occupantStart, allowOverlap: true)
                try repository.rescheduleSession(occupantID, to: draggedStart, allowOverlap: true)
            } else {
                // Spostamento su fascia libera. Gli overlap residui non bloccano lo
                // spostamento manuale (le fasce occupate portano allo scambio).
                try repository.rescheduleSession(sessionID, to: row.start, allowOverlap: true)
            }
        } catch { operation.capture(error) }
    }

    private func move(_ direction: Int) {
        if let next = SchedulingSuggestions.calendar.date(byAdding: period.component, value: direction, to: interval.start) {
            selectedDate = next
        }
    }
}

struct SessionDetailView: View {
    @Environment(\.modelContext) private var context
    let session: TrainingSession
    @Query private var participants: [SessionParticipant]
    @Query private var clients: [Client]
    @Query private var sessions: [TrainingSession]
    @State private var editing = false
    @State private var pendingStatus: SessionStatus?
    @State private var operation = BusinessOperation()

    private var people: [SessionParticipant] { participants.filter { $0.sessionID == session.id } }
    /// Partecipanti fatturabili: senza pacchetto, con metodo ammesso e importo positivo.
    private var invoiceableParticipants: [SessionParticipant] {
        people.filter {
            $0.packageID == nil
                && BusinessRepository.invoiceableMethods.contains($0.paymentMethod)
                && $0.priceCents > 0
        }
    }
    private var conflicts: [String] {
        BusinessDates.conflicts(for: session, sessions: sessions, blocks: [])
    }

    var body: some View {
        Group {
            if let error = _participants.fetchError ?? _clients.fetchError ?? _sessions.fetchError {
                ArchiveReadErrorView(error: error)
            } else {
                detail
            }
        }
        .navigationTitle(session.serviceName)
        .accessibilityIdentifier("session.detail")
        .toolbar {
            if session.status != .completed {
                ToolbarItem(placement: .primaryAction) {
                    Button("Modifica") { editing = true }.disabled(operation.committed)
                }
            }
        }
        .sheet(isPresented: $editing) { SessionEditor(session: session) }
        .confirmationDialog(confirmationTitle, isPresented: Binding(
            get: { pendingStatus != nil }, set: { if !$0 { pendingStatus = nil } }
        ), titleVisibility: .visible) {
            if let pendingStatus {
                Button(pendingStatus == .completed ? "Completa lezione" : pendingStatus.title,
                       role: pendingStatus == .cancelled || pendingStatus == .noShow ? .destructive : nil) {
                    updateStatus(pendingStatus)
                }
                .accessibilityIdentifier("session.confirmStatus")
            }
            Button("Torna alla lezione", role: .cancel) { pendingStatus = nil }
        } message: {
            Text(pendingStatus == .completed
                 ? "La lezione diventerà non modificabile. Senza pacchetto verrà registrato anche l'incasso del prezzo concordato; con pacchetto verrà scalata una lezione senza un secondo incasso. Conferma solo una lezione realmente svolta."
                 : "Annullamento e assenza non applicano penali e non consumano lezioni dei pacchetti. Lo storico resta disponibile.")
        }
        .businessError($operation)
    }

    private var detail: some View {
        Form {
            Section("Appuntamento") {
                SessionStatusLabel(status: session.status)
                    .accessibilityIdentifier("session.status")
                LabeledContent("Inizio", value: BusinessFormatting.dateTime(session.startDate))
                LabeledContent("Fine", value: BusinessFormatting.dateTime(session.endDate))
                LabeledContent("Durata", value: "\(session.durationMinutes) minuti")
            }
            Section(people.count > 1 ? "Partecipanti" : "Cliente") {
                ForEach(people) { person in
                    VStack(alignment: .leading, spacing: 5) {
                        if let client = clients.first(where: { $0.id == person.clientID }) {
                            NavigationLink {
                                ClientDetailView(client: client)
                            } label: {
                                Label(client.fullName + (client.isArchived ? " · archiviato" : ""), systemImage: "person")
                            }
                        } else {
                            Text(person.clientName).font(.headline)
                        }
                        if person.packageID != nil {
                            NavigationLink {
                                PackagesView(clientID: person.clientID)
                            } label: {
                                Text("1 lezione da pacchetto · nessun addebito singolo")
                                    .font(.subheadline)
                            }
                        } else {
                            LabeledContent("Prezzo concordato", value: Money.format(person.priceCents))
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            ForEach(invoiceableParticipants) { person in
                SessionInvoiceSection(
                    session: session,
                    participant: person,
                    client: clients.first(where: { $0.id == person.clientID }),
                    showsName: invoiceableParticipants.count > 1
                )
            }
            if !session.notes.isEmpty {
                Section("Note organizzative") { Text(session.notes).textSelection(.enabled) }
            }
            if !conflicts.isEmpty {
                Section("Sovrapposizioni da verificare") {
                    ForEach(Array(conflicts.enumerated()), id: \.offset) { _, conflict in
                        Label(conflict, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    }
                    Text("Segnalazione aggiornata in base ai dati presenti nell'archivio, anche dopo aggiornamenti da altri dispositivi.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if session.status == .planned {
                Section {
                    Button("Segna come completata", systemImage: "checkmark.circle") { pendingStatus = .completed }
                        .accessibilityIdentifier("session.complete")
                    Button("Annulla appuntamento", role: .destructive) { pendingStatus = .cancelled }
                    Button("Segna assenza", role: .destructive) { pendingStatus = .noShow }
                } footer: {
                    Text("Nessuna penale per annullamento o assenza. Completa la lezione solo dopo averla svolta.")
                }
                .disabled(operation.committed)
            } else if session.status == .completed {
                Section {
                    Label("Lezione completata: orario, partecipanti e addebiti sono bloccati.",
                          systemImage: "lock")
                    Text("Le rettifiche economiche si registrano come note di credito nei movimenti del cliente.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Section {
                    Text("Nessun addebito e nessuna lezione scalata dal pacchetto.")
                    Button("Riporta a programmata") { pendingStatus = .planned }
                        .disabled(operation.committed)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var confirmationTitle: String {
        switch pendingStatus {
        case .completed: return "Confermi che la lezione è stata svolta?"
        case .cancelled: return "Annullare l'appuntamento?"
        case .noShow: return "Registrare l'assenza?"
        default: return "Ripristinare l'appuntamento?"
        }
    }

    private func updateStatus(_ status: SessionStatus) {
        pendingStatus = nil
        do { try BusinessRepository(context: context).setSessionStatus(session.id, to: status) }
        catch { operation.capture(error) }
    }
}

struct ClientSessionsView: View {
    let clientID: UUID
    @Query(sort: \TrainingSession.startDate, order: .reverse) private var sessions: [TrainingSession]
    @Query private var participants: [SessionParticipant]
    @State private var status: SessionStatus?

    private var visibleSessions: [TrainingSession] {
        let ids = Set(participants.filter { $0.clientID == clientID }.map(\.sessionID))
        return sessions.filter { ids.contains($0.id) && (status == nil || $0.status == status) }
    }

    var body: some View {
        Group {
            if let error = _sessions.fetchError ?? _participants.fetchError {
                ArchiveReadErrorView(error: error)
            } else {
                List {
                    Picker("Stato", selection: $status) {
                        Text("Tutti gli stati").tag(nil as SessionStatus?)
                        ForEach(SessionStatus.allCases) { Text($0.title).tag(Optional($0)) }
                    }
                    if visibleSessions.isEmpty {
                        ContentUnavailableView("Nessun appuntamento", systemImage: "calendar")
                    }
                    ForEach(visibleSessions) { session in
                        NavigationLink {
                            SessionDetailView(session: session)
                        } label: {
                            VStack(alignment: .leading) {
                                Text(BusinessFormatting.day(session.startDate)).font(.caption).foregroundStyle(.secondary)
                                SessionSummaryRow(
                                    session: session, participants: participants,
                                    conflict: !BusinessDates.conflicts(for: session, sessions: sessions, blocks: []).isEmpty
                                )
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Storico appuntamenti")
    }
}

/// Sezione "Fattura elettronica" per un partecipante fatturabile di una lezione completata.
struct SessionInvoiceSection: View {
    @Environment(\.modelContext) private var context
    let session: TrainingSession
    let participant: SessionParticipant
    let client: Client?
    let showsName: Bool

    @Query private var invoices: [Invoice]
    @StateObject private var sender = InvoiceSender()
    @State private var issueDate: Date
    @State private var confirming = false

    init(session: TrainingSession, participant: SessionParticipant, client: Client?, showsName: Bool) {
        self.session = session
        self.participant = participant
        self.client = client
        self.showsName = showsName
        _issueDate = State(initialValue: session.invoiceDate ?? Date())
    }

    private var sourceKey: String {
        Invoice.sessionSourceKey(sessionID: session.id, clientID: participant.clientID)
    }
    private var existingInvoice: Invoice? {
        let key = sourceKey.lowercased()
        return invoices.first { $0.sourceKey.lowercased() == key }
    }
    private var breakdown: ForfettarioBreakdown? {
        try? ForfettarioBreakdown.from(totalCents: participant.priceCents)
    }
    private var lineDescription: String {
        session.serviceName.trimmingCharacters(in: .whitespaces).isEmpty ? "Lezione" : session.serviceName
    }
    private var fiscalIssues: [String] {
        InvoiceFiscalReadiness.issues(client: client)
    }
    private var alreadySent: Bool {
        guard let status = existingInvoice?.status else { return false }
        return status == .transmitted || status == .delivered
    }
    private var sectionTitle: String {
        showsName ? "Fattura elettronica · \(participant.clientName)" : "Fattura elettronica"
    }

    var body: some View {
        Section(sectionTitle) {
            if let breakdown {
                LabeledContent("Imponibile", value: Money.format(breakdown.taxableCents))
                LabeledContent("Rivalsa INPS (4%)", value: Money.format(breakdown.contributionCents))
                LabeledContent("Totale", value: Money.format(breakdown.totalCents))
                Text(ForfettarioTax.riferimentoNormativo)
                    .font(.caption).foregroundStyle(.secondary)
            }
            DatePicker("Data di fatturazione", selection: $issueDate, displayedComponents: .date)
                .accessibilityIdentifier("session.invoiceDate")
                .disabled(alreadySent || sender.isBusy)

            InvoiceStatusRow(invoice: existingInvoice)

            if !fiscalIssues.isEmpty {
                ForEach(fiscalIssues, id: \.self) { issue in
                    Label(issue, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).font(.caption)
                }
            }

            InvoicePhaseRow(phase: sender.phase)

            Button("Invia fattura elettronica", systemImage: "paperplane") {
                confirming = true
            }
            .accessibilityIdentifier("session.sendInvoice")
            .disabled(alreadySent || sender.isBusy || !fiscalIssues.isEmpty || breakdown == nil)
        }
        .confirmationDialog("Inviare la fattura elettronica?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Invia fattura") {
                let client = client
                Task {
                    guard let client else { return }
                    await sender.sendSessionInvoice(
                        context: context, sessionID: session.id, clientID: participant.clientID,
                        client: client, issueDate: issueDate, lineDescription: lineDescription
                    )
                }
            }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("La fattura verrà trasmessa al servizio di fatturazione elettronica. Verifica la data e i dati del cliente.")
        }
    }
}

/// Mostra lo stato di un'eventuale fattura già esistente.
struct InvoiceStatusRow: View {
    let invoice: Invoice?

    var body: some View {
        if let invoice {
            LabeledContent("Stato fattura", value: invoice.status.title)
            if let error = invoice.errorMessage, !error.isEmpty {
                Text(error).font(.caption).foregroundStyle(.orange)
            }
        }
    }
}

/// Mostra la fase corrente dell'invio (progresso o esito).
struct InvoicePhaseRow: View {
    let phase: InvoiceSender.Phase

    var body: some View {
        switch phase {
        case .idle:
            EmptyView()
        case .creating:
            ProgressView("Creazione fattura…")
        case .sending:
            ProgressView("Invio in corso…")
        case .done:
            Label("Fattura trasmessa.", systemImage: "checkmark.circle").foregroundStyle(.green).font(.caption)
        case .failed(let message):
            Label(message, systemImage: "xmark.circle").foregroundStyle(.red).font(.caption)
        }
    }
}

/// Verifica dei dati fiscali (cedente, credenziali, cliente) per abilitare l'invio.
enum InvoiceFiscalReadiness {
    static func issues(client: Client?) -> [String] {
        var issues: [String] = []
        let profile = SellerProfileStore().load()
        if !profile.isComplete {
            issues.append("Completa i dati fiscali nella sezione Credenziali.")
        }
        let credentials = ArubaCredentialsStore(secrets: KeychainSecretStore()).load()
        if !credentials.isComplete {
            issues.append("Inserisci le credenziali Aruba nella sezione Credenziali.")
        }
        guard let client else {
            issues.append("Cliente non disponibile.")
            return issues
        }
        if client.taxCode.trimmingCharacters(in: .whitespaces).isEmpty {
            issues.append("Il cliente non ha un codice fiscale nell'anagrafica.")
        }
        if client.billingAddress.trimmingCharacters(in: .whitespaces).isEmpty {
            issues.append("Il cliente non ha un indirizzo di fatturazione nell'anagrafica.")
        }
        return issues
    }
}
