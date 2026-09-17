import PaolaCore
import SwiftData
import SwiftUI

/// Editor di un corso ricorrente: titolo, giorni della settimana, orario, durata e
/// partecipanti. I partecipanti possono essere solo clienti con un pacchetto a tempo
/// attivo; a ciascuno viene associato il relativo pacchetto a tempo.
struct CourseEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var clients: [Client]
    @Query private var packages: [LessonPackage]
    @Query private var courseParticipants: [CourseParticipant]

    private let course: Course?
    @State private var title: String
    @State private var weekdays: Set<Int>
    @State private var startTime: Date
    @State private var durationMinutes: Int
    @State private var participants: [CourseParticipantDraft]
    @State private var operation = BusinessOperation()

    private var isEditing: Bool { course != nil }

    init(course: Course? = nil) {
        self.course = course
        _title = State(initialValue: course?.title ?? "")
        _weekdays = State(initialValue: course?.weekdays ?? [])
        let hour = course?.startHour ?? 9
        let minute = course?.startMinute ?? 0
        _startTime = State(initialValue: Calendar.current.date(bySettingHour: hour, minute: minute,
                                                               second: 0, of: Date()) ?? Date())
        _durationMinutes = State(initialValue: course?.durationMinutes ?? 60)
        _participants = State(initialValue: [])
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Corso") {
                    TextField("Titolo del corso", text: $title)
                        .accessibilityIdentifier("course.title")
                    DatePicker("Ora di inizio", selection: $startTime, displayedComponents: .hourAndMinute)
                        .accessibilityIdentifier("course.startTime")
                    Stepper("Durata: \(durationMinutes) minuti", value: $durationMinutes, in: 15...480, step: 15)
                        .accessibilityIdentifier("course.duration")
                }
                Section("Giorni della settimana") {
                    ForEach(orderedWeekdays, id: \.self) { weekday in
                        Toggle(weekdayName(weekday), isOn: Binding(
                            get: { weekdays.contains(weekday) },
                            set: { on in if on { weekdays.insert(weekday) } else { weekdays.remove(weekday) } }
                        ))
                        .accessibilityIdentifier("course.weekday.\(weekday)")
                    }
                }
                Section {
                    ForEach($participants) { $person in
                        participantRow($person)
                    }
                    Button("Aggiungi partecipante", systemImage: "person.badge.plus") {
                        participants.append(CourseParticipantDraft())
                    }
                    .accessibilityIdentifier("course.addParticipant")
                } header: {
                    Text("Partecipanti")
                } footer: {
                    Text("Solo clienti con un pacchetto a tempo attivo. Il nome resta in agenda fino alla scadenza del pacchetto.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isEditing ? "Modifica corso" : "Nuovo corso")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }.keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") { save() }.keyboardShortcut(.defaultAction)
                        .disabled(operation.committed)
                        .accessibilityIdentifier("course.save")
                }
            }
            .task { loadParticipants() }
        }
        .businessEditorSize()
        .interactiveDismissDisabled()
        .businessError($operation, onCommitted: { dismiss() })
    }

    // Lunedì → domenica.
    private var orderedWeekdays: [Int] { [2, 3, 4, 5, 6, 7, 1] }
    private func weekdayName(_ weekday: Int) -> String {
        SchedulingSuggestions.calendar.weekdaySymbols[weekday - 1].capitalized
    }

    /// Clienti che hanno almeno un pacchetto a tempo attivo (non scaduto oggi).
    private func timedPackages(for clientID: UUID) -> [LessonPackage] {
        packages.filter {
            $0.clientID == clientID && $0.kind == .timed
                && ($0.expiresOn.map { BusinessDates.exclusiveEnd($0) > Date() } ?? true)
        }
    }
    private var eligibleClients: [Client] {
        clients.filter { !$0.isArchived && !timedPackages(for: $0.id).isEmpty }
    }

    @ViewBuilder
    private func participantRow(_ person: Binding<CourseParticipantDraft>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Cliente", selection: person.clientID) {
                Text("Seleziona").tag(nil as UUID?)
                ForEach(eligibleClients) { client in
                    Text(client.fullName).tag(Optional(client.id))
                }
            }
            .onChange(of: person.clientID.wrappedValue) { _, newValue in
                // Preseleziona il primo pacchetto a tempo attivo del cliente scelto.
                person.packageID.wrappedValue = newValue.flatMap { timedPackages(for: $0).first?.id }
            }
            if let clientID = person.clientID.wrappedValue {
                let options = timedPackages(for: clientID)
                Picker("Pacchetto a tempo", selection: person.packageID) {
                    Text("Nessuno").tag(nil as UUID?)
                    ForEach(options) { package in
                        Text(packageLabel(package)).tag(Optional(package.id))
                    }
                }
            }
            Button("Rimuovi", role: .destructive) {
                participants.removeAll { $0.id == person.wrappedValue.id }
            }
            .font(.caption)
        }
    }

    private func packageLabel(_ package: LessonPackage) -> String {
        let expiry = package.expiresOn.map { " · fino al " + $0.formatted(.dateTime.day().month().year()) } ?? ""
        return "A tempo\(expiry)"
    }

    private func loadParticipants() {
        guard participants.isEmpty, let course else { return }
        participants = courseParticipants.filter { $0.courseID == course.id }.map {
            CourseParticipantDraft(clientID: $0.clientID, packageID: $0.packageID)
        }
    }

    private func save() {
        guard !operation.committed else { return }
        var draft = CourseDraft()
        draft.id = course?.id
        draft.title = title
        draft.weekdays = weekdays
        let comps = SchedulingSuggestions.calendar.dateComponents([.hour, .minute], from: startTime)
        draft.startHour = comps.hour ?? 9
        draft.startMinute = comps.minute ?? 0
        draft.durationMinutes = durationMinutes
        draft.participants = participants.filter { $0.clientID != nil }
        do {
            _ = try BusinessRepository(context: context).saveCourse(draft)
            dismiss()
        } catch { operation.capture(error) }
    }
}
