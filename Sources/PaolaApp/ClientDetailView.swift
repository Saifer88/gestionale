import PaolaCore
import SwiftData
import SwiftUI

struct ClientDetailView: View {
    @Environment(\.modelContext) private var context
    let client: Client
    @Query private var services: [TrainingService]
    @Query private var rates: [ServiceRate]
    @State private var showingEditor = false
    @State private var confirmingArchive = false
    @State private var formError: FormError?
    @State private var savedButRefreshFailed = false

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    ClientAvatar(client: client, size: 64)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(client.fullName)
                            .font(.title2.bold())
                            .textSelection(.enabled)
                        Label(client.isArchived ? "Cliente archiviato" : "Cliente attivo",
                              systemImage: client.isArchived ? "archivebox" : "checkmark.circle")
                            .font(.subheadline)
                            .foregroundStyle(client.isArchived ? Color.secondary : .teal)
                    }
                }
                .padding(.vertical, 8)
            }

            Section("Recapiti") {
                LabeledContent("Telefono", value: client.phone.isEmpty ? "Non inserito" : client.phone)
                LabeledContent("Email", value: client.email.isEmpty ? "Non inserita" : client.email)
            }
            .textSelection(.enabled)

            Section("Preferenze appuntamenti") {
                if let error = _services.fetchError ?? _rates.fetchError {
                    Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                } else if let serviceID = client.preferredServiceID {
                    let service = services.first { $0.id == serviceID }
                    LabeledContent("Servizio preferito", value: service.map {
                        $0.name + ($0.isActive ? "" : " · disattivato")
                    } ?? "Non disponibile")
                    let choices = service.map { ServiceTariffs.options(for: $0, rates: rates) } ?? []
                    let preferred = choices.first { $0.id == client.preferredRateID }
                    LabeledContent("Tariffa preferita", value: client.preferredRateID == nil
                        ? "Predefinita del servizio"
                        : preferred.map { "\($0.name) · \(Money.format($0.priceCents))" } ?? "Non disponibile")
                } else {
                    Text("Nessuna preferenza: si riprendono le ultime scelte disponibili.")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Rapporto professionale") {
                LabeledContent("Cliente dal") {
                    Text(client.joinedOn, format: .dateTime.day().month(.wide).year())
                }
                LabeledContent("Scheda creata") {
                    Text(client.createdAt, format: .dateTime.day().month().year())
                }
                LabeledContent("Ultima modifica") {
                    Text(client.updatedAt, format: .dateTime.day().month().year().hour().minute())
                }
            }

            Section("Note organizzative") {
                Text(client.notes.isEmpty ? "Nessuna nota inserita." : client.notes)
                    .foregroundStyle(client.notes.isEmpty ? Color.secondary : .primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Section("Informazioni riservate") {
                DisclosureGroup("Anamnesi") {
                    Text(client.anamnesis.isEmpty ? "Nessuna anamnesi inserita." : client.anamnesis)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .accessibilityIdentifier("client.anamnesis.detail")
                DisclosureGroup("Analisi fisica") {
                    Text(client.physicalAnalysis.isEmpty ? "Nessuna analisi fisica inserita." : client.physicalAnalysis)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .accessibilityIdentifier("client.physicalAnalysis.detail")
            }

            ClientBusinessSection(client: client)

            Section {
                Button {
                    confirmingArchive = true
                } label: {
                    Label(client.isArchived ? "Riattiva cliente" : "Archivia cliente",
                          systemImage: client.isArchived ? "arrow.uturn.backward" : "archivebox")
                }
                .accessibilityIdentifier("client.archive")
            } footer: {
                Text("L'archiviazione conserva tutti i dati. Puoi riattivare il cliente in qualsiasi momento.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle(client.fullName)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Modifica") { showingEditor = true }
            }
        }
        .sheet(isPresented: $showingEditor) {
            ClientEditor(client: client)
        }
        .confirmationDialog(
            client.isArchived ? "Riattivare il cliente?" : "Archiviare il cliente?",
            isPresented: $confirmingArchive,
            titleVisibility: .visible
        ) {
            Button(client.isArchived ? "Riattiva" : "Archivia", action: toggleArchive)
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("I dati e le note vengono conservati.")
        }
        .alert(savedButRefreshFailed ? "Dati salvati" : "Operazione non riuscita", isPresented: Binding(
            get: { formError != nil },
            set: { if !$0 { formError = nil } }
        )) {
            Button("OK", role: .cancel) { formError = nil }
        } message: {
            Text(formError?.message ?? "")
        }
    }

    private func toggleArchive() {
        savedButRefreshFailed = false
        do {
            try ClientRepository(context: context).setArchived(!client.isArchived, for: client)
        } catch let error as ClientPersistenceError {
            savedButRefreshFailed = true
            formError = FormError(error)
        } catch {
            formError = FormError(error)
        }
    }
}
