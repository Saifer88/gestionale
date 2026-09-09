import PaolaCore
import SwiftData
import SwiftUI

struct ServicesView: View {
    @Query(sort: \TrainingService.name) private var services: [TrainingService]
    @Query private var rates: [ServiceRate]
    @State private var showInactive = false
    @State private var search = ""
    @State private var creating = false
    @State private var editing: TrainingService?

    private var visibleServices: [TrainingService] {
        services.filter {
            (showInactive || $0.isActive) && (search.isEmpty || $0.name.localizedStandardContains(search))
        }
    }

    var body: some View {
        Group {
            if let error = _services.fetchError ?? _rates.fetchError {
                ArchiveReadErrorView(error: error)
            } else {
                List {
                    Section {
                        Toggle("Mostra anche i servizi disattivati", isOn: $showInactive)
                    } footer: {
                        Text("Ogni servizio può avere più tariffe per persona. La prima è quella predefinita. Le modifiche non cambiano i prezzi degli appuntamenti già salvati.")
                    }
                    if visibleServices.isEmpty {
                        ContentUnavailableView("Nessun servizio", systemImage: "figure.strengthtraining.traditional",
                                               description: Text("Crea un servizio e le sue tariffe."))
                    }
                    ForEach(visibleServices) { service in
                        Button { editing = service } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(service.name).font(.headline)
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                                }
                                Text("\(service.durationMinutes) minuti · tariffe per persona")
                                    .font(.caption).foregroundStyle(.secondary)
                                ForEach(ServiceTariffs.options(for: service, rates: rates)) { rate in
                                    HStack {
                                        Text(rate.name)
                                        Spacer()
                                        Text(Money.format(rate.priceCents)).monospacedDigit()
                                    }
                                    .font(.subheadline)
                                }
                                if !service.isActive {
                                    Label("Disattivato", systemImage: "pause.circle")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationTitle("Servizi e tariffe")
        .accessibilityIdentifier("services.screen")
        .searchable(text: $search, prompt: "Nome del servizio")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { creating = true } label: { Label("Nuovo servizio", systemImage: "plus") }
                    .accessibilityIdentifier("services.new")
            }
        }
        .sheet(isPresented: $creating) { ServiceEditor() }
        .sheet(item: $editing) { ServiceEditor(service: $0) }
    }
}

private struct EditableServiceRate: Identifiable {
    let id: UUID
    var name: String
    var price: String

    init(_ rate: ServiceRateDraft = ServiceRateDraft()) {
        id = rate.id
        name = rate.name
        price = BusinessFormatting.editableMoney(rate.priceCents)
    }
}

struct ServiceEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var rates: [ServiceRate]
    private let service: TrainingService?
    @State private var draft: ServiceDraft
    @State private var editedRates = [EditableServiceRate()]
    @State private var loaded = false
    @State private var operation = BusinessOperation()

    init(service: TrainingService? = nil) {
        self.service = service
        var value = ServiceDraft()
        if let service {
            value.id = service.id
            value.name = service.name
            value.durationMinutes = service.durationMinutes
            value.priceCents = service.priceCents
            value.isActive = service.isActive
        }
        _draft = State(initialValue: value)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let error = _rates.fetchError {
                    ArchiveReadErrorView(error: error)
                } else {
                    Form {
                        Section("Servizio") {
                            TextField("Nome", text: $draft.name).accessibilityIdentifier("service.name")
                            Stepper("Durata: \(draft.durationMinutes) minuti",
                                    value: $draft.durationMinutes, in: 5...480, step: 5)
                                .accessibilityIdentifier("service.duration")
                        }
                        Section {
                            ForEach($editedRates) { $rate in
                                rateFields($rate)
                            }
                            Button("Aggiungi tariffa", systemImage: "plus") {
                                editedRates.append(EditableServiceRate(
                                    ServiceRateDraft(name: "")
                                ))
                            }
                            .accessibilityIdentifier("service.addRate")
                        } header: {
                            Text("Tariffe per persona")
                        } footer: {
                            Text("Inserisci almeno una tariffa con nome e prezzo. Viene riproposta l'ultima usata dal cliente, oppure la prima se non ha uno storico.")
                        }
                        Section {
                            Toggle("Attivo per nuovi appuntamenti", isOn: $draft.isActive)
                                .accessibilityIdentifier("service.active")
                        } footer: {
                            Text("Disattivare un servizio conserva lo storico. Il prezzo si riferisce al cliente della lezione.")
                        }
                    }
                    .formStyle(.grouped)
                }
            }
            .navigationTitle(draft.id == nil ? "Nuovo servizio" : "Modifica servizio")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }.keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva", action: save)
                        .disabled(operation.committed || _rates.fetchError != nil)
                        .keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier("service.save")
                }
            }
        }
        .businessEditorSize()
        .interactiveDismissDisabled()
        .onAppear {
            guard !loaded else { return }
            if let service {
                editedRates = ServiceTariffs.options(for: service, rates: rates).map(EditableServiceRate.init)
            }
            loaded = true
        }
        .businessError($operation, onCommitted: { dismiss() })
    }

    private func rateFields(_ rate: Binding<EditableServiceRate>) -> some View {
        let index = editedRates.firstIndex(where: { $0.id == rate.wrappedValue.id }) ?? 0
        return VStack(alignment: .leading, spacing: 10) {
            if index == 0 { Text("Predefinita").font(.caption.bold()).foregroundStyle(.teal) }
            TextField("Nome tariffa", text: rate.name)
                .accessibilityIdentifier("service.rateName.\(index)")
            MoneyField(title: "Prezzo per persona (€)", text: rate.price)
                .accessibilityIdentifier(index == 0 ? "service.price" : "service.ratePrice.\(index)")
            if editedRates.count > 1 {
                Button("Rimuovi tariffa", systemImage: "minus.circle", role: .destructive) {
                    editedRates.removeAll { $0.id == rate.wrappedValue.id }
                }
                .accessibilityIdentifier("service.removeRate.\(index)")
            }
        }
        .padding(.vertical, 6)
    }

    private func save() {
        do {
            guard !editedRates.isEmpty else { throw BusinessInputError(message: "Inserisci almeno una tariffa.") }
            draft.tariffs = try editedRates.map {
                ServiceRateDraft(id: $0.id, name: $0.name, priceCents: try Money.parse($0.price))
            }
            draft.priceCents = draft.tariffs[0].priceCents
            _ = try BusinessRepository(context: context).saveService(draft)
            dismiss()
        } catch { operation.capture(error) }
    }
}
