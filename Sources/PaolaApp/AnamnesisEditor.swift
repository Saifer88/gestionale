import PaolaCore
import SwiftData
import SwiftUI

/// Editor di una singola versione della scheda anamnesi (dato riservato). Le versioni
/// precedenti restano nello storico; salvando si aggiorna o si aggiunge questa versione.
/// Mostra in sola lettura gli "elementi non più attivi": voci salvate in passato ma non
/// più previste dal codice, conservate per non perdere dati.
struct AnamnesisEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let client: Client

    @State private var version: Anamnesis
    @State private var formError: FormError?
    @State private var confirmingDelete = false

    /// True se la versione è già presente nello storico (quindi eliminabile). Una versione
    /// appena creata e non ancora salvata non compare finché non si salva.
    private var existsInHistory: Bool {
        AnamnesisHistory.parse(client.anamnesis).versions.contains { $0.id == version.id }
    }

    /// `version` è la versione da modificare (o una nuova, appena creata).
    init(client: Client, version: Anamnesis) {
        self.client = client
        _version = State(initialValue: version)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Versione") {
                    DatePicker("Data", selection: $version.date, displayedComponents: .date)
                    TextField("Titolo (facoltativo)", text: $version.title)
                }
                ForEach(Anamnesis.Field.allCases, id: \.self) { field in
                    fieldEditor(field)
                }
                if !version.legacyNote.isEmpty {
                    Section("Nota precedente (testo libero)") {
                        Text(version.legacyNote).textSelection(.enabled).foregroundStyle(.secondary)
                    }
                }
                let inactive = version.inactiveEntries
                if !inactive.isEmpty {
                    Section {
                        ForEach(inactive, id: \.key) { entry in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.key).font(.caption).foregroundStyle(.secondary)
                                Text(entry.value).textSelection(.enabled)
                            }
                        }
                    } header: {
                        Text("Elementi non più attivi")
                    } footer: {
                        Text("Voci registrate in passato e non più previste dalla scheda. Conservate per non perdere dati; non più modificabili qui.")
                    }
                }
                if existsInHistory {
                    Section {
                        Button("Elimina questa anamnesi", systemImage: "trash", role: .destructive) {
                            confirmingDelete = true
                        }
                        .accessibilityIdentifier("anamnesis.delete")
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Anamnesi")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }.keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") { save() }.keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier("anamnesis.save")
                }
            }
            .alert("Salvataggio non riuscito", isPresented: Binding(
                get: { formError != nil }, set: { if !$0 { formError = nil } }
            )) {
                Button("OK", role: .cancel) { formError = nil }
            } message: {
                Text(formError?.message ?? "")
            }
            .confirmationDialog("Eliminare questa anamnesi?", isPresented: $confirmingDelete,
                                titleVisibility: .visible) {
                Button("Elimina", role: .destructive) { delete() }
                Button("Annulla", role: .cancel) {}
            } message: {
                Text("La versione verrà rimossa. Le altre restano invariate. L'azione non è reversibile.")
            }
        }
        .frame(minWidth: 520, minHeight: 640)
    }

    @ViewBuilder
    private func fieldEditor(_ field: Anamnesis.Field) -> some View {
        switch field.kind {
        case .date:
            DatePicker(field.label, selection: dateBinding(field), displayedComponents: .date)
        case .boolean:
            Toggle(field.label, isOn: boolBinding(field))
        case .integer:
            VStack(alignment: .leading, spacing: 4) {
                Text(field.label).font(.subheadline)
                TextField("", text: textBinding(field))
                    .textFieldStyle(.roundedBorder)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
            }
        case .shortText:
            VStack(alignment: .leading, spacing: 4) {
                Text(field.label).font(.subheadline)
                TextField("", text: textBinding(field)).textFieldStyle(.roundedBorder)
            }
        case .longText:
            VStack(alignment: .leading, spacing: 4) {
                Text(field.label).font(.subheadline)
                TextField("", text: textBinding(field), axis: .vertical)
                    .lineLimit(2...6).textFieldStyle(.roundedBorder)
            }
        }
    }

    // MARK: - Binding per tipo

    private func textBinding(_ field: Anamnesis.Field) -> Binding<String> {
        Binding(get: { version.value(field) }, set: { version.set(field, $0) })
    }
    private func boolBinding(_ field: Anamnesis.Field) -> Binding<Bool> {
        Binding(get: { version.value(field) == "true" },
                set: { version.set(field, $0 ? "true" : "") })
    }
    private func dateBinding(_ field: Anamnesis.Field) -> Binding<Date> {
        Binding(
            get: {
                let raw = version.value(field)
                if let interval = Double(raw) { return Date(timeIntervalSinceReferenceDate: interval) }
                return Date()
            },
            set: { version.set(field, String($0.timeIntervalSinceReferenceDate)) }
        )
    }

    private func save() {
        var history = AnamnesisHistory.parse(client.anamnesis)
        history.upsert(version)
        persist(history)
    }

    private func delete() {
        var history = AnamnesisHistory.parse(client.anamnesis)
        history.remove(version.id)
        persist(history)
    }

    private func persist(_ history: AnamnesisHistory) {
        var draft = ClientDraft(client: client)
        draft.anamnesis = history.serialized()
        do {
            _ = try ClientRepository(context: context).save(draft, updating: client)
            dismiss()
        } catch {
            formError = FormError(error)
        }
    }
}
