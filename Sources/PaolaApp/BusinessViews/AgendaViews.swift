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

private enum AgendaItem: Identifiable {
    case session(TrainingSession)

    var id: String {
        switch self {
        case .session(let session): return "session-\(session.id)"
        }
    }

    var startDate: Date {
        switch self {
        case .session(let session): return session.startDate
        }
    }
}

struct AgendaView: View {
    @Query(sort: \TrainingSession.startDate) private var sessions: [TrainingSession]
    @Query private var participants: [SessionParticipant]
    @Query private var clients: [Client]
    @State private var period: AgendaPeriod = .week
    @State private var selectedDate = Date()
    @State private var status: SessionStatus?
    @State private var search = ""
    @State private var creatingSession = false

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
            return !isWeekend || !items(on: day).isEmpty
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
    }

    private var agenda: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Vista agenda", selection: $period) {
                    ForEach(AgendaPeriod.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("agenda.period")
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
            }
            .padding()
            Divider()
            if period == .week {
                weekColumns
            } else {
                List {
                    if visibleSessions.isEmpty {
                        ContentUnavailableView("Agenda libera", systemImage: "calendar",
                                               description: Text("Nessun appuntamento corrisponde al periodo e ai filtri."))
                    }
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

    private var weekColumns: some View {
        GeometryReader { geometry in
            let columns = weekDays
            let count = max(1, columns.count)
            let width = max(180, (geometry.size.width - 32 - CGFloat(count - 1) * 12) / CGFloat(count))
            ScrollView([.horizontal, .vertical]) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(columns, id: \.self) { day in
                        VStack(alignment: .leading, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(SchedulingSuggestions.dayLabel(day)).font(.headline)
                                if SchedulingSuggestions.calendar.isDateInToday(day) {
                                    Text("Oggi").font(.caption.bold()).foregroundStyle(.teal)
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 46, alignment: .topLeading)
                            Divider()
                            if items(on: day).isEmpty {
                                Text("Nessun impegno").font(.caption).foregroundStyle(.secondary)
                            }
                            ForEach(items(on: day)) { item in
                                itemRow(item)
                                    .buttonStyle(.plain)
                                    .padding(10)
                                    .background(.background, in: RoundedRectangle(cornerRadius: 10))
                            }
                            Spacer(minLength: 16)
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

    private func items(on day: Date) -> [AgendaItem] {
        let dayEnd = BusinessDates.exclusiveEnd(day)
        let daySessions = visibleSessions.filter {
            BusinessDates.overlaps(day, dayEnd, $0.startDate, $0.endDate)
        }
        return daySessions.map { AgendaItem.session($0) }.sorted { left, right in
            if left.startDate == right.startDate { return left.id < right.id }
            return left.startDate < right.startDate
        }
    }

    @ViewBuilder private func daySection(_ day: Date) -> some View {
        let dayItems = items(on: day)
        if !dayItems.isEmpty {
            Section(BusinessFormatting.day(day)) {
                ForEach(dayItems) { item in itemRow(item) }
            }
        }
    }

    @ViewBuilder private func itemRow(_ item: AgendaItem) -> some View {
        switch item {
        case .session(let session):
            NavigationLink {
                SessionDetailView(session: session)
            } label: {
                CalendarSessionRow(
                    session: session, participants: participants, clients: clients,
                    conflict: !BusinessDates.conflicts(for: session, sessions: sessions, blocks: []).isEmpty
                )
            }
            .accessibilityIdentifier("agenda.appointment.\(session.id.uuidString)")
        }
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
