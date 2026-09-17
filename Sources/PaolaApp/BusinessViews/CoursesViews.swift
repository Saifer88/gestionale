import PaolaCore
import SwiftData
import SwiftUI

/// Elenco dei corsi ricorrenti. Da qui si creano, si aprono (per modifica/gestione
/// partecipanti) ed è possibile eliminarli.
struct CoursesView: View {
    @Query(sort: \Course.title) private var courses: [Course]
    @Query private var participants: [CourseParticipant]
    @State private var creating = false

    var body: some View {
        Group {
            if let error = _courses.fetchError ?? _participants.fetchError {
                ArchiveReadErrorView(error: error)
            } else {
                List {
                    if courses.isEmpty {
                        ContentUnavailableView("Nessun corso", systemImage: "figure.strengthtraining.traditional",
                                               description: Text("Crea un corso ricorrente con giorni, orario e partecipanti."))
                    }
                    ForEach(courses) { course in
                        NavigationLink(value: AppRoute.course(course.id)) {
                            courseRow(course)
                        }
                    }
                }
            }
        }
        .sectionTitle(.courses)
        .accessibilityIdentifier("courses.screen")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { creating = true } label: { Label("Nuovo corso", systemImage: "plus") }
                    .accessibilityIdentifier("courses.new")
            }
        }
        .sheet(isPresented: $creating) { CourseEditor() }
    }

    private func courseRow(_ course: Course) -> some View {
        let count = participants.filter { $0.courseID == course.id }.count
        return VStack(alignment: .leading, spacing: 4) {
            Text(course.title.isEmpty ? "Corso" : course.title).font(.headline)
            Text("\(CourseFormatting.weekdays(course.weekdays)) · \(CourseFormatting.time(course))")
                .font(.caption).foregroundStyle(.secondary)
            Text("\(count) \(count == 1 ? "partecipante" : "partecipanti")")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

/// Dettaglio corso: apre l'editor per modifica/partecipanti ed espone l'eliminazione.
struct CourseDetailView: View {
    @Environment(\.modelContext) private var context
    let course: Course
    @Query private var participants: [CourseParticipant]
    @Query private var clients: [Client]
    @State private var editing = false
    @State private var confirmingDelete = false
    @State private var operation = BusinessOperation()

    private var people: [CourseParticipant] { participants.filter { $0.courseID == course.id } }

    var body: some View {
        Form {
            Section("Corso") {
                LabeledContent("Titolo", value: course.title)
                LabeledContent("Giorni", value: CourseFormatting.weekdays(course.weekdays))
                LabeledContent("Orario", value: CourseFormatting.time(course))
                LabeledContent("Durata", value: "\(course.durationMinutes) minuti")
            }
            Section {
                if people.isEmpty {
                    Text("Nessun partecipante.").foregroundStyle(.secondary)
                }
                ForEach(people) { person in
                    Text(clients.first(where: { $0.id == person.clientID })?.fullName ?? person.clientName)
                }
            } header: {
                Text("Partecipanti")
            } footer: {
                Text("I partecipanti compaiono in agenda fino alla scadenza del loro pacchetto a tempo.")
            }
            Section {
                Button("Elimina corso", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                    .accessibilityIdentifier("course.delete")
            }
        }
        .formStyle(.grouped)
        .navigationTitle(course.title.isEmpty ? "Corso" : course.title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Modifica") { editing = true }
            }
        }
        .sheet(isPresented: $editing) { CourseEditor(course: course) }
        .confirmationDialog("Eliminare il corso?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Elimina", role: .destructive) { delete() }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("Il corso e i suoi partecipanti verranno rimossi. Le occorrenze in agenda spariranno. L'azione non è reversibile.")
        }
        .businessError($operation)
    }

    private func delete() {
        do {
            try BusinessRepository(context: context).deleteCourse(course.id)
        } catch { operation.capture(error) }
    }
}

/// Formattazione condivisa per giorni e orario di un corso.
enum CourseFormatting {
    static func weekdays(_ days: Set<Int>) -> String {
        let symbols = SchedulingSuggestions.calendar.shortWeekdaySymbols // indice 0 = domenica
        let ordered = [2, 3, 4, 5, 6, 7, 1] // lun→dom
        let names = ordered.filter { days.contains($0) }.map { symbols[$0 - 1].capitalized }
        return names.isEmpty ? "—" : names.joined(separator: ", ")
    }
    static func time(_ course: Course) -> String {
        String(format: "%02d:%02d", course.startHour, course.startMinute)
    }
}
