import PaolaCore
import SwiftData
import SwiftUI

struct SessionEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var clients: [Client]
    @Query(sort: \TrainingService.name) private var services: [TrainingService]
    @Query private var rates: [ServiceRate]
    @Query private var participants: [SessionParticipant]
    @Query private var packages: [LessonPackage]
    @Query private var uses: [PackageUse]
    @Query private var sessions: [TrainingSession]
    @Query private var blocks: [Unavailability]
    @Query private var preferences: [ClientAppointmentPreference]
    private let session: TrainingSession?
    @State private var draft: SessionDraft
    @State private var clientID: UUID?
    @State private var packageID: UUID?
    @State private var price = "0,00"
    @State private var rateID: UUID?
    @State private var loaded = false
    @State private var confirmingOverlap = false
    @State private var notices: [String] = []
    @State private var operation = BusinessOperation()

    init(session: TrainingSession? = nil, clientID: UUID? = nil) {
        self.session = session
        var value = SessionDraft()
        if let session {
            value.id = session.id
            value.startDate = session.startDate
            value.durationMinutes = session.durationMinutes
            value.serviceID = session.serviceID
            value.serviceName = session.serviceName
            value.location = session.location
            value.notes = session.notes
        }
        _draft = State(initialValue: value)
        _clientID = State(initialValue: clientID)
    }

    private var originalParticipants: [SessionParticipant] {
        participants.filter { $0.sessionID == session?.id }.sorted { $0.id.uuidString < $1.id.uuidString }
    }
    private var readOnly: Bool { session?.status == .completed || originalParticipants.count > 1 }
    private var readError: Error? {
        let errors: [Error?] = [
            _clients.fetchError, _services.fetchError, _participants.fetchError, _packages.fetchError,
            _uses.fetchError, _sessions.fetchError, _blocks.fetchError, _rates.fetchError, _preferences.fetchError
        ]
        return errors.compactMap { $0 }.first
    }
    private var selectableClients: [Client] {
        clients.filter { client in
            !client.isArchived || originalParticipants.contains(where: { $0.clientID == client.id })
        }
    }
    private var selectableServices: [TrainingService] {
        services.filter { $0.isActive || $0.id == session?.serviceID }
    }
    private var tariffOptions: [ServiceRateDraft] {
        guard let service = services.first(where: { $0.id == draft.serviceID }) else { return [] }
        return ServiceTariffs.options(for: service, rates: rates)
    }
    private var conflicts: [String] {
        let end = draft.startDate.addingTimeInterval(Double(draft.durationMinutes) * 60)
        return sessions.filter {
            $0.id != draft.id && ($0.status == .planned || $0.status == .completed)
                && BusinessDates.overlaps(draft.startDate, end, $0.startDate, $0.endDate)
        }.map { "\($0.serviceName) · \(BusinessFormatting.dateTime($0.startDate))" }
        + blocks.filter {
            BusinessDates.overlaps(draft.startDate, end, $0.startDate, $0.endDate)
        }.map { "Indisponibilità: \($0.title)" }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let error = readError {
                    ArchiveReadErrorView(error: error)
                } else {
                    editorForm
                }
            }
            .navigationTitle(session == nil ? "Nuovo appuntamento" : "Appuntamento")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(readOnly ? "Chiudi" : "Annulla") { dismiss() }.keyboardShortcut(.cancelAction)
                }
                if !readOnly {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Salva") { save() }
                            .keyboardShortcut(.defaultAction)
                            .disabled(readError != nil || operation.committed || clientID == nil || draft.serviceID == nil)
                            .accessibilityIdentifier("session.save")
                    }
                }
            }
        }
        .businessEditorSize()
        .interactiveDismissDisabled()
        .onAppear(perform: load)
        .onChange(of: price) { _, text in
            if let rate = tariffOptions.first(where: { $0.id == rateID }),
               text != BusinessFormatting.editableMoney(rate.priceCents) {
                rateID = nil
            }
        }
        .confirmationDialog("Salvare la sovrapposizione?", isPresented: $confirmingOverlap, titleVisibility: .visible) {
            Button("Salva comunque") { save(allowOverlap: true) }
            Button("Torna all'appuntamento", role: .cancel) {}
        } message: {
            Text("L'orario scelto manualmente coincide con un appuntamento o un'indisponibilità. La sovrapposizione resterà segnalata.")
        }
        .businessError($operation, onCommitted: { dismiss() })
    }

    private var editorForm: some View {
        Form {
            Section {
                BusinessClientPicker(title: "Cliente", clients: selectableClients, selection: Binding(
                    get: { clientID },
                    set: { value in
                        let changed = value != clientID
                        clientID = value
                        if session == nil { applyPreferences() }
                        else if changed {
                            packageID = nil
                            notices = ["Cliente cambiato: verifica tariffa e pacchetto prima di salvare."]
                        }
                    }
                ))
                .accessibilityIdentifier("session.client1")
                .disabled(readOnly)
            } header: {
                Text("Prima scegli il cliente")
            } footer: {
                Text("Il servizio e la tariffa preferiti della scheda cliente hanno precedenza. In assenza di preferenze si riprendono le ultime scelte; orario e pacchetto restano quelli usati di recente.")
            }
            if clientID == nil {
                Text("Seleziona un cliente per continuare.")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("session.selectClientFirst")
            } else {
                if readOnly {
                    Label("Appuntamento storico: orario e partecipanti non modificabili.", systemImage: "lock")
                    if originalParticipants.count > 1 {
                        ForEach(originalParticipants) { Text($0.clientName) }
                    }
                }
                if !notices.isEmpty {
                    Section("Scelte proposte") {
                        ForEach(notices, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                    }
                }
                Group {
                    scheduleSection
                    billingSection
                    if session == nil {
                        Section("Selezione rapida") {
                            AppointmentQuickChoices(startDate: $draft.startDate, durationMinutes: draft.durationMinutes,
                                                    sessions: sessions, blocks: blocks, excludingSessionID: draft.id)
                        }
                    }
                    Section("Note") {
                        TextField("Note organizzative (facoltative)", text: $draft.notes, axis: .vertical)
                            .lineLimit(3...8).accessibilityIdentifier("session.notes")
                    }
                }
                .disabled(readOnly)
                if !conflicts.isEmpty {
                    Section("Sovrapposizioni rilevate") {
                        ForEach(Array(conflicts.enumerated()), id: \.offset) { _, warning in
                            Label(warning, systemImage: "exclamationmark.triangle")
                                .font(.caption).foregroundStyle(.orange)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var scheduleSection: some View {
        Section("Appuntamento") {
            Picker("Servizio", selection: Binding(get: { draft.serviceID }, set: selectService)) {
                Text("Seleziona servizio").tag(nil as UUID?)
                ForEach(selectableServices) { service in
                    Text(serviceLabel(service)).tag(Optional(service.id))
                }
            }
            .accessibilityIdentifier("session.service")
            if selectableServices.isEmpty {
                Text("Crea un servizio in Servizi e tariffe.").font(.caption).foregroundStyle(.orange)
            }
            DatePicker("Inizio (scelta manuale)", selection: $draft.startDate).accessibilityIdentifier("session.startDate")
            LabeledContent("Orario selezionato", value: SchedulingSuggestions.hourLabel(draft.startDate))
                .accessibilityIdentifier("session.selectedTime")
            Stepper("Durata: \(draft.durationMinutes) minuti", value: $draft.durationMinutes, in: 5...480, step: 5)
                .accessibilityIdentifier("session.duration")
            LabeledContent("Fine", value: BusinessFormatting.dateTime(
                draft.startDate.addingTimeInterval(Double(draft.durationMinutes) * 60)
            ))
        }
    }

    private var billingSection: some View {
        Section("Tariffa e pacchetto") {
            Picker("Pacchetto in uso", selection: $packageID) {
                Text("No").tag(nil as UUID?)
                ForEach(availablePackages) { package in
                    Text(packageLabel(package)).tag(Optional(package.id))
                }
            }
            .accessibilityIdentifier("session.package1")
            if !tariffOptions.isEmpty && packageID == nil {
                Picker("Tariffa", selection: Binding(get: { rateID }, set: selectRate)) {
                    Text("Prezzo personalizzato").tag(nil as UUID?)
                    ForEach(tariffOptions) { rate in
                        Text("\(rate.name) · \(Money.format(rate.priceCents))").tag(Optional(rate.id))
                    }
                }
                .accessibilityIdentifier("session.tariff1")
            }
            MoneyField(title: "Prezzo concordato (€)", text: $price)
                .disabled(packageID != nil).accessibilityIdentifier("session.price1")
            Text(packageID == nil
                 ? "L'incasso viene registrato automaticamente quando segni la lezione come completata."
                 : "Il completamento scala una lezione. Il pacchetto è già stato conteggiato alla registrazione, senza un secondo incasso.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var availablePackages: [LessonPackage] {
        packages.filter { package in
            package.clientID == clientID && (package.id == packageID ||
                (package.purchasedOn <= draft.startDate &&
                 (package.expiresOn.map { BusinessDates.exclusiveEnd($0) > draft.startDate } ?? true) &&
                 BusinessReports.remaining(package: package, uses: uses) > 0))
        }.sorted { $0.purchasedOn < $1.purchasedOn }
    }

    private func packageLabel(_ package: LessonPackage) -> String {
        let remaining = BusinessReports.remaining(package: package, uses: uses)
        return "Pacchetto del \(BusinessFormatting.day(package.purchasedOn)) · \(remaining)/10 residue"
            + (package.expiresOn.map { " · scade \(BusinessFormatting.day($0))" } ?? " · senza scadenza")
    }

    private func load() {
        guard !loaded, readError == nil else { return }
        if let person = originalParticipants.first {
            clientID = person.clientID
            price = BusinessFormatting.editableMoney(person.priceCents)
            packageID = person.packageID
            rateID = tariffOptions.first { $0.priceCents == person.priceCents }?.id
        } else if session == nil, clientID != nil {
            applyPreferences()
        }
        loaded = true
    }

    private func applyPreferences() {
        draft.serviceID = nil
        draft.serviceName = ""
        draft.notes = ""
        rateID = nil
        packageID = nil
        price = "0,00"
        notices = []
        guard let clientID else { return }
        do {
            let selected = try AppointmentSelection.propose(
                clientID: clientID, services: services, rates: rates, sessions: sessions,
                participants: participants, blocks: blocks, packages: packages, uses: uses, preferences: preferences,
                preferredServiceID: clients.first(where: { $0.id == clientID })?.preferredServiceID,
                preferredRateID: clients.first(where: { $0.id == clientID })?.preferredRateID
            )
            draft.serviceID = selected.serviceID
            draft.serviceName = services.first { $0.id == selected.serviceID }?.name ?? ""
            draft.durationMinutes = selected.durationMinutes
            draft.startDate = selected.startDate
            rateID = selected.rateID
            price = BusinessFormatting.editableMoney(selected.priceCents)
            packageID = selected.packageID
            notices = selected.notices
        } catch { operation.capture(error) }
    }

    private func selectService(_ id: UUID?) {
        draft.serviceID = id
        guard let service = services.first(where: { $0.id == id }) else { return }
        draft.serviceName = service.name
        draft.durationMinutes = service.durationMinutes
        let rate = ServiceTariffs.options(for: service, rates: rates).first
        rateID = rate?.id
        price = BusinessFormatting.editableMoney(rate?.priceCents ?? service.priceCents)
    }

    private func selectRate(_ id: UUID?) {
        rateID = id
        if let rate = tariffOptions.first(where: { $0.id == id }) {
            price = BusinessFormatting.editableMoney(rate.priceCents)
        }
    }

    private func serviceLabel(_ service: TrainingService) -> String {
        let prices = ServiceTariffs.options(for: service, rates: rates).map(\.priceCents)
        let low = prices.min() ?? service.priceCents
        let high = prices.max() ?? low
        return "\(service.name) · " + (low == high ? Money.format(low) : "\(Money.format(low)) – \(Money.format(high))")
            + (service.isActive ? "" : " · disattivato")
    }

    private func save(allowOverlap: Bool = false) {
        guard !readOnly, !operation.committed else { return }
        do {
            guard let clientID, let serviceID = draft.serviceID,
                  let service = selectableServices.first(where: { $0.id == serviceID }) else {
                throw BusinessInputError(message: "Seleziona un cliente e un servizio.")
            }
            if session?.serviceID != serviceID || session == nil { draft.serviceName = service.name }
            draft.participants = [ParticipantDraft(
                clientID: clientID, priceCents: try Money.parse(price), packageID: packageID, tariffID: rateID
            )]
            _ = try BusinessRepository(context: context).saveSession(draft, allowOverlap: allowOverlap)
            dismiss()
        } catch BusinessError.overlap {
            confirmingOverlap = true
        } catch { operation.capture(error) }
    }
}
