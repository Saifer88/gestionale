import PaolaCore
import SwiftData
import SwiftUI

struct ClientEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
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
                        .disabled(savedButRefreshFailed)
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
