import PaolaCore
import SwiftData
import SwiftUI

struct PackagesView: View {
    @Query(sort: \LessonPackage.purchasedOn, order: .reverse) private var packages: [LessonPackage]
    @Query private var uses: [PackageUse]
    @Query private var clients: [Client]
    private let clientID: UUID?
    @State private var selectedClientID: UUID?
    @State private var onlyAvailable = false
    @State private var creating = false

    init(clientID: UUID? = nil) {
        self.clientID = clientID
        _selectedClientID = State(initialValue: clientID)
    }

    private var visiblePackages: [LessonPackage] {
        packages.filter {
            (selectedClientID == nil || $0.clientID == selectedClientID)
                && (!onlyAvailable || (BusinessReports.remaining(package: $0, uses: uses) > 0
                    && ($0.expiresOn.map { BusinessDates.exclusiveEnd($0) > Date() } ?? true)))
        }
    }

    var body: some View {
        Group {
            if let error = _packages.fetchError ?? _uses.fetchError ?? _clients.fetchError {
                ArchiveReadErrorView(error: error)
            } else {
                List {
                    Section {
                        if clientID == nil {
                            BusinessClientPicker(title: "Cliente", clients: clients,
                                                 selection: $selectedClientID, allowsAll: true)
                        }
                        Toggle("Solo pacchetti con lezioni disponibili", isOn: $onlyAvailable)
                    } footer: {
                        Text("Pacchetti con numero di lezioni configurabile, personali e senza rinnovo automatico. Il saldo economico è separato dal numero di lezioni residue.")
                    }
                    if visiblePackages.isEmpty {
                        ContentUnavailableView("Nessun pacchetto", systemImage: "square.stack.3d.up",
                                               description: Text("Assegna un pacchetto oppure modifica il filtro per consultare lo storico."))
                    }
                    ForEach(visiblePackages) { package in
                        NavigationLink {
                            PackageDetailView(package: package)
                        } label: {
                            PackageSummaryRow(package: package, uses: uses)
                        }
                    }
                }
            }
        }
        .sectionTitle(.packages)
        .accessibilityIdentifier("packages.screen")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { creating = true } label: { Label("Assegna pacchetto", systemImage: "plus") }
                    .accessibilityIdentifier("packages.new")
            }
        }
        .sheet(isPresented: $creating) { PackageEditor(clientID: selectedClientID) }
    }
}

struct PackageSummaryRow: View {
    let package: LessonPackage
    let uses: [PackageUse]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(package.clientName).font(.headline)
                Spacer()
                Text("\(BusinessReports.remaining(package: package, uses: uses))/\(package.capacity) residue")
                    .monospacedDigit().foregroundStyle(.teal)
            }
            Text("Acquisto \(BusinessFormatting.day(package.purchasedOn)) · \(Money.format(package.priceCents))")
                .font(.caption).foregroundStyle(.secondary)
            if let expiry = package.expiresOn {
                Text("Scadenza: \(BusinessFormatting.day(expiry)) (compresa)")
                    .font(.caption)
                    .foregroundStyle(BusinessDates.exclusiveEnd(expiry) <= Date() ? Color.orange : .secondary)
            } else {
                Text("Senza scadenza").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct PackageEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var clients: [Client]
    @Query private var uses: [PackageUse]
    private let package: LessonPackage?
    @State private var selectedClientID: UUID?
    @State private var purchasedOn = Date()
    @State private var price = ""
    @State private var capacity = 10
    @State private var hasExpiry = false
    @State private var expiry = Date()
    @State private var notes = ""
    @State private var operation = BusinessOperation()
    @State private var confirmingIncome = false
    @State private var confirmingDelete = false

    private var isEditing: Bool { package != nil }
    private var usedLessons: Int {
        guard let package else { return 0 }
        return BusinessReports.used(package: package, uses: uses)
    }

    init(clientID: UUID? = nil) {
        self.package = nil
        _selectedClientID = State(initialValue: clientID)
    }

    init(package: LessonPackage) {
        self.package = package
        _selectedClientID = State(initialValue: package.clientID)
        _purchasedOn = State(initialValue: package.purchasedOn)
        _price = State(initialValue: BusinessFormatting.editableMoney(package.priceCents))
        _capacity = State(initialValue: package.capacity)
        _hasExpiry = State(initialValue: package.expiresOn != nil)
        _expiry = State(initialValue: package.expiresOn ?? Date())
        _notes = State(initialValue: package.notes)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let error = _clients.fetchError {
                    ArchiveReadErrorView(error: error)
                } else {
                    Form {
                        Section("Pacchetto personale") {
                            if isEditing {
                                LabeledContent("Cliente", value: package?.clientName ?? "")
                            } else {
                                BusinessClientPicker(title: "Cliente attivo", clients: clients.filter { !$0.isArchived },
                                                     selection: $selectedClientID)
                                    .accessibilityIdentifier("package.client")
                                if clients.allSatisfy(\.isArchived) {
                                    Text("Aggiungi o riattiva un cliente nell'anagrafica per assegnare un pacchetto.")
                                        .font(.caption).foregroundStyle(.orange)
                                }
                            }
                            Stepper("Lezioni incluse: \(capacity)", value: $capacity, in: max(1, usedLessons)...1000)
                                .accessibilityIdentifier("package.capacity")
                            if isEditing && usedLessons > 0 {
                                Text("Sono già state utilizzate \(usedLessons) lezioni: il minimo non può scendere sotto questo valore.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            HStack {
                                Text("Selezione rapida")
                                Spacer()
                                ForEach([5, 10], id: \.self) { count in
                                    Button("\(count)") { capacity = count }
                                        .buttonStyle(.bordered)
                                        .accessibilityIdentifier("package.capacity.\(count)")
                                }
                            }
                            MoneyField(title: "Prezzo totale del pacchetto (€)", text: $price)
                                .accessibilityIdentifier("package.price")
                            DatePicker("Data di acquisto", selection: $purchasedOn, displayedComponents: .date)
                                .accessibilityIdentifier("package.purchasedOn")
                            Toggle("Prevede una scadenza", isOn: $hasExpiry)
                                .accessibilityIdentifier("package.hasExpiry")
                            if hasExpiry {
                                DatePicker("Ultimo giorno utilizzabile", selection: $expiry, displayedComponents: .date)
                                    .accessibilityIdentifier("package.expiry")
                            }
                            TextField("Note (facoltative)", text: $notes, axis: .vertical).lineLimit(3...6)
                        }
                        Section {
                            if isEditing {
                                Text("Le modifiche a prezzo e data aggiornano anche l'incasso registrato all'acquisto. Le lezioni già utilizzate restano invariate.")
                            } else {
                                Text("La registrazione contabilizza subito il prezzo totale come incasso alla data di acquisto. Verifica importo e data prima di confermare.")
                                Text("Le lezioni sono scalate al completamento degli appuntamenti, senza ulteriori incassi. Nessun rinnovo automatico.")
                            }
                        }
                        .font(.caption).foregroundStyle(.secondary)
                        if isEditing {
                            Section {
                                Button("Elimina pacchetto", systemImage: "trash", role: .destructive) {
                                    confirmingDelete = true
                                }
                                .disabled(operation.committed || usedLessons > 0)
                                .accessibilityIdentifier("package.delete")
                            } footer: {
                                Text(usedLessons > 0
                                     ? "Non eliminabile: ha lezioni già utilizzate. L'eliminazione altererebbe lo storico delle sedute completate."
                                     : "L'eliminazione rimuove il pacchetto e l'incasso registrato all'acquisto. Operazione consentita solo senza lezioni utilizzate.")
                            }
                        }
                    }
                    .formStyle(.grouped)
                }
            }
            .navigationTitle(isEditing ? "Modifica pacchetto" : "Assegna pacchetto")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }.keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Salva" : "Registra") {
                        if isEditing { save() } else { validateForConfirmation() }
                    }
                        .keyboardShortcut(.defaultAction)
                        .disabled(operation.committed || _clients.fetchError != nil)
                        .accessibilityIdentifier("package.save")
                }
            }
        }
        .businessEditorSize()
        .interactiveDismissDisabled()
        .onAppear {
            if !isEditing, let selectedClientID,
               !clients.contains(where: { $0.id == selectedClientID && !$0.isArchived }) {
                self.selectedClientID = nil
            }
        }
        .businessError($operation, onCommitted: { dismiss() })
        .confirmationDialog("Registrare pacchetto e incasso?", isPresented: $confirmingIncome, titleVisibility: .visible) {
            Button("Conferma pacchetto e incasso", action: save)
                .accessibilityIdentifier("package.confirmIncome")
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("Verrà registrato un incasso di \(price) € alla data di acquisto. Non è un trasferimento di denaro.")
        }
        .confirmationDialog("Eliminare il pacchetto?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Elimina pacchetto", role: .destructive, action: delete)
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("Verranno rimossi il pacchetto e l'incasso registrato all'acquisto. L'operazione non può essere annullata.")
        }
    }

    private func validateForConfirmation() {
        do {
            guard selectedClientID != nil else { throw BusinessInputError(message: "Seleziona un cliente attivo.") }
            guard (1...1000).contains(capacity) else {
                throw BusinessInputError(message: "Il numero di lezioni deve essere compreso tra 1 e 1000.")
            }
            _ = try Money.parse(price)
            confirmingIncome = true
        } catch { operation.capture(error) }
    }

    private func save() {
        do {
            var draft = PackageDraft()
            if let package {
                draft.id = package.id
                draft.clientID = package.clientID
            } else {
                guard let selectedClientID else { throw BusinessInputError(message: "Seleziona un cliente attivo.") }
                draft.clientID = selectedClientID
            }
            draft.priceCents = try Money.parse(price)
            draft.capacity = capacity
            draft.purchasedOn = Calendar.current.startOfDay(for: purchasedOn)
            draft.expiresOn = hasExpiry ? Calendar.current.startOfDay(for: expiry) : nil
            draft.notes = notes
            _ = try BusinessRepository(context: context).savePackage(draft)
            dismiss()
        } catch { operation.capture(error) }
    }

    private func delete() {
        guard let package else { return }
        do {
            try BusinessRepository(context: context).deletePackage(package.id)
            dismiss()
        } catch { operation.capture(error) }
    }
}

struct PackageDetailView: View {
    let package: LessonPackage
    @Query private var uses: [PackageUse]
    @Query private var sessions: [TrainingSession]
    @Query private var participants: [SessionParticipant]
    @State private var editing = false

    private var packageUses: [PackageUse] {
        var seen = Set<UUID>()
        return uses.filter { $0.packageID == package.id }.sorted { $0.createdAt < $1.createdAt }
            .filter { seen.insert($0.sessionID).inserted }
    }

    var body: some View {
        Group {
            if let error = _uses.fetchError ?? _sessions.fetchError ?? _participants.fetchError {
                ArchiveReadErrorView(error: error)
            } else {
                Form {
                    Section("Pacchetto da \(package.capacity) lezioni") {
                        PackageSummaryRow(package: package, uses: uses)
                        ProgressView(value: Double(package.capacity - BusinessReports.remaining(package: package, uses: uses)),
                                     total: Double(max(1, package.capacity)))
                            .accessibilityLabel("Lezioni utilizzate")
                        LabeledContent("Lezioni utilizzate", value: "\(packageUses.count)")
                        if !package.notes.isEmpty { Text(package.notes).textSelection(.enabled) }
                    }
                    Section {
                        NavigationLink("Movimenti e saldo cliente") { PaymentsView(clientID: package.clientID) }
                    } footer: {
                        Text("I nuovi pacchetti registrano l'incasso all'acquisto. Per i pacchetti precedenti all'aggiornamento rimangono i movimenti storici, senza incassi retroattivi. Nessun rinnovo automatico.")
                    }
                    Section("Storico utilizzi") {
                        if packageUses.isEmpty {
                            Text("Nessuna lezione utilizzata. Le prenotazioni non riducono le lezioni residue.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(packageUses) { use in
                            if let session = sessions.first(where: { $0.id == use.sessionID }) {
                                NavigationLink {
                                    SessionDetailView(session: session)
                                } label: {
                                    VStack(alignment: .leading) {
                                        Text(BusinessFormatting.day(session.startDate)).font(.caption)
                                        SessionSummaryRow(session: session, participants: participants)
                                    }
                                }
                            } else {
                                VStack(alignment: .leading) {
                                    Text("Utilizzo registrato il \(BusinessFormatting.day(use.createdAt))")
                                    Text("Appuntamento non disponibile nell'archivio.")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .formStyle(.grouped)
            }
        }
        .navigationTitle("Pacchetto · \(package.clientName)")
        .accessibilityIdentifier("package.detail")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Modifica") { editing = true }
                    .accessibilityIdentifier("package.edit")
            }
        }
        .sheet(isPresented: $editing) { PackageEditor(package: package) }
    }
}
