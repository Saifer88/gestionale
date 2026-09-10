import PaolaCore
import SwiftData
import SwiftUI

struct ClientEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \TrainingService.name) private var services: [TrainingService]
    @Query private var rates: [ServiceRate]
    private let client: Client?
    @State private var draft: ClientDraft
    @State private var formError: FormError?
    @State private var confirmingDuplicate = false
    @State private var savedButRefreshFailed = false

    init(client: Client? = nil) {
        self.client = client
        _draft = State(initialValue: client.map(ClientDraft.init(client:)) ?? ClientDraft())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nome", text: $draft.firstName)
                        .textContentType(.givenName)
                        .accessibilityIdentifier("client.firstName")
                    TextField("Cognome", text: $draft.lastName)
                        .textContentType(.familyName)
                        .accessibilityIdentifier("client.lastName")
                } header: {
                    Text("Anagrafica")
                } footer: {
                    Text("Nome e cognome sono obbligatori.")
                }

                preferenceSection

                Section("Recapiti facoltativi") {
                    TextField("Telefono", text: $draft.phone)
                        .textContentType(.telephoneNumber)
                        .accessibilityIdentifier("client.phone")
                        #if os(iOS)
                        .keyboardType(.phonePad)
                        #endif
                    TextField("Email", text: $draft.email)
                        .textContentType(.emailAddress)
                        .accessibilityIdentifier("client.email")
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        #endif
                }

                Section {
                    TextField("Codice fiscale", text: $draft.taxCode)
                        .accessibilityIdentifier("client.taxCode")
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.characters)
                        #endif
                    TextField("Indirizzo di fatturazione", text: $draft.billingAddress, axis: .vertical)
                        .lineLimit(2...4)
                        .accessibilityIdentifier("client.billingAddress")
                } header: {
                    Text("Dati di fatturazione")
                } footer: {
                    Text("Facoltativi. Il codice fiscale viene salvato in maiuscolo. Non compaiono negli estratti, che restano documenti non fiscali.")
                }

                Section("Rapporto professionale") {
                    DatePicker("Cliente dal", selection: $draft.joinedOn, displayedComponents: .date)
                }

                Section {
                    TextEditor(text: $draft.notes)
                        .frame(minHeight: 110)
                        .accessibilityLabel("Note organizzative")
                        .accessibilityIdentifier("client.notes")
                } header: {
                    Text("Note organizzative")
                } footer: {
                    Text("Solo informazioni utili all'organizzazione. Non inserire dati sanitari.")
                }

                Section {
                    TextEditor(text: $draft.anamnesis)
                        .frame(minHeight: 110)
                        .accessibilityLabel("Anamnesi")
                        .accessibilityIdentifier("client.anamnesis")
                } header: {
                    Text("Anamnesi")
                } footer: {
                    Text("Campo facoltativo e riservato. Registra soltanto le informazioni necessarie, nel rispetto della base giuridica e dell'informativa applicabili.")
                }

                Section {
                    TextEditor(text: $draft.physicalAnalysis)
                        .frame(minHeight: 110)
                        .accessibilityLabel("Analisi fisica")
                        .accessibilityIdentifier("client.physicalAnalysis")
                } header: {
                    Text("Analisi fisica")
                } footer: {
                    Text("Questi campi sono inclusi nel backup cifrato, non negli estratti economici o nei promemoria.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle(client == nil ? "Nuovo cliente" : "Modifica cliente")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") { save() }
                        .disabled(savedButRefreshFailed || _services.fetchError != nil || _rates.fetchError != nil)
                        .keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier("client.save")
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 510, idealWidth: 570, minHeight: 580, idealHeight: 640)
        #endif
        .interactiveDismissDisabled()
        .confirmationDialog("Possibile cliente duplicato", isPresented: $confirmingDuplicate,
                            titleVisibility: .visible) {
            Button("Salva comunque") { save(allowDuplicate: true) }
            Button("Torna alla scheda", role: .cancel) {}
        } message: {
            Text("Esiste gia' un cliente con lo stesso nome o recapito. Verifica prima di proseguire.")
        }
        .alert(savedButRefreshFailed ? "Dati salvati" : "Impossibile salvare", isPresented: Binding(
            get: { formError != nil },
            set: { if !$0 { formError = nil } }
        )) {
            Button("OK", role: .cancel) {
                formError = nil
                if savedButRefreshFailed {
                    dismiss()
                }
            }
        } message: {
            Text(formError?.message ?? "")
        }
    }

    private var preferredService: TrainingService? {
        services.first { $0.id == draft.preferredServiceID }
    }

    private var availableRates: [ServiceRateDraft] {
        preferredService.map { ServiceTariffs.options(for: $0, rates: rates) } ?? []
    }

    private var preferenceSection: some View {
        Section {
            if let error = _services.fetchError ?? _rates.fetchError {
                Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            } else {
                Picker("Servizio preferito", selection: Binding(
                    get: { draft.preferredServiceID },
                    set: { id in
                        draft.preferredServiceID = id
                        draft.preferredRateID = nil
                    }
                )) {
                    Text("Nessuno · usa le ultime scelte").tag(nil as UUID?)
                    ForEach(services.filter { $0.isActive || $0.id == draft.preferredServiceID }) { service in
                        Text(service.name + (service.isActive ? "" : " · disattivato"))
                            .tag(Optional(service.id))
                    }
                    if let id = draft.preferredServiceID, preferredService == nil {
                        Text("Servizio non disponibile").tag(Optional(id))
                    }
                }
                .accessibilityIdentifier("client.preferredService")
                if draft.preferredServiceID != nil {
                    Picker("Tariffa preferita", selection: $draft.preferredRateID) {
                        Text("Predefinita del servizio").tag(nil as UUID?)
                        ForEach(availableRates) { rate in
                            Text("\(rate.name) · \(Money.format(rate.priceCents))").tag(Optional(rate.id))
                        }
                        if let id = draft.preferredRateID, !availableRates.contains(where: { $0.id == id }) {
                            Text("Tariffa non disponibile").tag(Optional(id))
                        }
                    }
                    .accessibilityIdentifier("client.preferredRate")
                }
                if services.allSatisfy({ !$0.isActive }) {
                    Text("Puoi creare servizi e tariffe nelle Impostazioni e impostare la preferenza anche in seguito.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Preferenze appuntamenti")
        } footer: {
            Text("Facoltative. Queste scelte hanno precedenza sullo storico nei nuovi appuntamenti. Una tariffa diversa usata in una singola lezione non modifica le preferenze del cliente.")
        }
    }

    private func save(allowDuplicate: Bool = false) {
        do {
            _ = try ClientRepository(context: context).save(
                draft, updating: client, allowDuplicate: allowDuplicate
            )
            dismiss()
        } catch ClientValidationError.possibleDuplicate {
            confirmingDuplicate = true
        } catch let error as ClientPersistenceError {
            savedButRefreshFailed = true
            formError = FormError(error)
        } catch {
            formError = FormError(error)
        }
    }
}
