import PaolaCore
import SwiftData
import SwiftUI

/// Titolo con icona per la sezione Pagamenti; titolo semplice per il conto di un cliente.
private struct PaymentsTitleModifier: ViewModifier {
    let clientID: UUID?
    func body(content: Content) -> some View {
        if clientID == nil {
            content.sectionTitle(.payments)
        } else {
            content.navigationTitle("Conto cliente")
        }
    }
}

struct PaymentsView: View {
    @Query(sort: \LedgerEntry.date, order: .reverse) private var entries: [LedgerEntry]
    @Query private var clients: [Client]
    private let clientID: UUID?
    @State private var selectedClientID: UUID?
    @State private var method: PaymentMethod?
    @State private var kind: LedgerKind?
    @State private var from = BusinessDates.monthStart
    @State private var through = Date()
    @State private var entireHistory: Bool

    init(clientID: UUID? = nil) {
        self.clientID = clientID
        _selectedClientID = State(initialValue: clientID)
        _entireHistory = State(initialValue: clientID != nil)
    }

    private var validPeriod: Bool {
        entireHistory || Calendar.current.startOfDay(for: from) <= Calendar.current.startOfDay(for: through)
    }
    private var statement: AccountStatement {
        BusinessReports.statement(clientID: selectedClientID,
                                  from: entireHistory ? .distantPast : Calendar.current.startOfDay(for: from),
                                  to: entireHistory ? .distantFuture : BusinessDates.exclusiveEnd(through),
                                  entries: entries)
    }
    private var filteredEntries: [LedgerEntry] {
        guard validPeriod else { return [] }
        return statement.entries.filter {
            (kind == nil || $0.kind == kind)
                && (method == nil || (($0.kind == .payment || $0.kind == .refund) && $0.method == method))
        }.sorted {
            $0.date == $1.date ? $0.createdAt > $1.createdAt : $0.date > $1.date
        }
    }

    var body: some View {
        Group {
            if let error = _entries.fetchError ?? _clients.fetchError {
                ArchiveReadErrorView(error: error)
            } else {
                List {
                    filterSection
                    if validPeriod {
                        Section("Conto del periodo · tutti i tipi e metodi") {
                            LabeledContent("Addebiti", value: Money.format(statement.chargedCents))
                            LabeledContent("Incassi registrati", value: Money.format(statement.paidCents))
                            LabeledContent("Rimborsi", value: Money.format(statement.refundedCents))
                            LabeledContent("Note di credito", value: Money.format(statement.creditedCents))
                            BalanceLabel(cents: statement.closingBalance)
                            Text("Saldo alla fine del periodo, inclusi i movimenti precedenti. Positivo: da saldare. Negativo: credito del cliente.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if let selectedClientID {
                            Section {
                                NavigationLink("Ripartizione dei pagamenti") {
                                    ClientAllocationsView(clientID: selectedClientID)
                                }
                                NavigationLink("Estratto conto ed esportazione") {
                                    ReportsView(clientID: selectedClientID)
                                }
                            }
                        }
                    }
                    Section("Movimenti · \(filteredEntries.count)") {
                        if filteredEntries.isEmpty {
                            ContentUnavailableView("Nessun movimento", systemImage: "eurosign.circle",
                                                   description: Text("Gli incassi compaiono registrando un pacchetto o completando una lezione senza pacchetto."))
                        }
                        ForEach(filteredEntries) { entry in
                            NavigationLink {
                                LedgerEntryDetailView(entry: entry)
                            } label: {
                                LedgerEntryRow(entry: entry)
                            }
                        }
                    }
                    Section {
                        Text("Gli incassi sono automatici: pacchetti alla registrazione, lezioni singole al completamento. I movimenti precedenti restano nello storico. Errori e restituzioni si correggono con note di credito o rimborsi.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .modifier(PaymentsTitleModifier(clientID: clientID))
        .accessibilityIdentifier("payments.screen")
    }

    private var filterSection: some View {
        Section("Filtri") {
            if clientID == nil {
                BusinessClientPicker(title: "Cliente", clients: clients,
                                     selection: $selectedClientID, allowsAll: true)
            }
            Toggle("Tutto lo storico", isOn: $entireHistory)
            if !entireHistory {
                BusinessPeriodPicker(from: $from, through: $through, identifierPrefix: "payments")
            }
            Picker("Tipo di movimento", selection: $kind) {
                Text("Tutti").tag(nil as LedgerKind?)
                ForEach(LedgerKind.allCases) { Text($0.title).tag(Optional($0)) }
            }
            Picker("Metodo incassi / rimborsi", selection: $method) {
                Text("Tutti i metodi").tag(nil as PaymentMethod?)
                ForEach(PaymentMethod.allCases) { Text($0.title).tag(Optional($0)) }
            }
            if method != nil {
                Text("Con un metodo selezionato sono mostrati solo pagamenti e rimborsi.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct LedgerEntryRow: View {
    let entry: LedgerEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.kind.title).font(.headline)
                Spacer()
                Text(Money.format(entry.amountCents))
                    .monospacedDigit()
                    .foregroundStyle(entry.kind == .payment || entry.kind == .credit ? Color.teal : .primary)
            }
            Text(entry.clientName)
            HStack {
                Text(BusinessFormatting.day(entry.date))
                if entry.kind == .payment || entry.kind == .refund {
                    Text("· \(entry.method.title)")
                }
            }
            .font(.caption).foregroundStyle(.secondary)
            if !entry.notes.isEmpty {
                Text(entry.notes).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            if entry.kind == .unknown {
                Label("Tipo non riconosciuto: importo escluso dai totali. Verifica l'archivio.",
                      systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 4)
    }
}

struct LedgerEntryDetailView: View {
    let entry: LedgerEntry
    @Query private var entries: [LedgerEntry]
    @State private var correcting = false

    private var canonicalEntries: [LedgerEntry] {
        BusinessReports.statement(clientID: entry.clientID, from: .distantPast, to: .distantFuture,
                                  entries: entries).entries
    }
    private var corrections: [LedgerEntry] {
        canonicalEntries.filter { $0.originalEntryID == entry.id }
    }
    private var correctableAmount: Int64 {
        corrections.reduce(max(0, entry.amountCents)) { max(0, $0 - min($0, max(0, $1.amountCents))) }
    }

    var body: some View {
        Group {
            if let error = _entries.fetchError {
                ArchiveReadErrorView(error: error)
            } else {
                Form {
                    Section("Movimento permanente") {
                        LedgerEntryRow(entry: entry)
                        LabeledContent("Registrato il", value: BusinessFormatting.dateTime(entry.createdAt))
                        if !entry.notes.isEmpty { Text(entry.notes).textSelection(.enabled) }
                        Text("DOCUMENTO NON FISCALE").font(.caption.bold()).foregroundStyle(.secondary)
                    }
                    if entry.kind == .payment || entry.kind == .charge {
                        Section(entry.kind == .payment ? "Restituzione di denaro" : "Rettifica dell'addebito") {
                            LabeledContent(entry.kind == .payment ? "Ancora rimborsabile" : "Ancora accreditabile",
                                           value: Money.format(correctableAmount))
                            Button(entry.kind == .payment ? "Registra rimborso parziale o totale" : "Registra nota di credito parziale o totale") {
                                correcting = true
                            }
                            .disabled(correctableAmount <= 0)
                            Text(entry.kind == .payment
                                 ? "Registra solo denaro già restituito. Il pagamento originale resta visibile."
                                 : "La nota di credito riduce l'importo dovuto, ma non restituisce denaro e non ripristina lezioni nel pacchetto.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if let originalID = entry.originalEntryID,
                       let original = canonicalEntries.first(where: { $0.id == originalID }) {
                        Section("Movimento originale") {
                            NavigationLink { LedgerEntryDetailView(entry: original) } label: {
                                LedgerEntryRow(entry: original)
                            }
                        }
                    }
                    if !corrections.isEmpty {
                        Section("Rettifiche collegate") {
                            ForEach(corrections) { correction in
                                NavigationLink { LedgerEntryDetailView(entry: correction) } label: {
                                    LedgerEntryRow(entry: correction)
                                }
                            }
                        }
                    }
                    Section {
                        NavigationLink("Saldo e tutti i movimenti") { PaymentsView(clientID: entry.clientID) }
                        NavigationLink("Ripartizione dei pagamenti") { ClientAllocationsView(clientID: entry.clientID) }
                    }
                }
                .formStyle(.grouped)
            }
        }
        .navigationTitle(entry.kind.title)
        .sheet(isPresented: $correcting) {
            LedgerCorrectionEditor(entry: entry, maximum: correctableAmount)
        }
    }
}

struct LedgerCorrectionEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let entry: LedgerEntry
    let maximum: Int64
    @State private var amount: String
    @State private var date = Date()
    @State private var notes = ""
    @State private var confirming = false
    @State private var operation = BusinessOperation()

    init(entry: LedgerEntry, maximum: Int64) {
        self.entry = entry
        self.maximum = maximum
        _amount = State(initialValue: BusinessFormatting.editableMoney(maximum))
    }

    private var isRefund: Bool { entry.kind == .payment }

    var body: some View {
        NavigationStack {
            Form {
                Section(isRefund ? "Denaro restituito" : "Riduzione dell'importo dovuto") {
                    Text(entry.clientName).font(.headline)
                    LabeledContent("Movimento originale", value: Money.format(entry.amountCents))
                    LabeledContent("Massimo disponibile", value: Money.format(maximum))
                    MoneyField(title: "Importo parziale o totale (€)", text: $amount)
                    DatePicker("Data", selection: $date, displayedComponents: .date)
                    TextField("Motivo della rettifica", text: $notes, axis: .vertical).lineLimit(3...6)
                }
                Section {
                    Text(isRefund
                         ? "Registra un rimborso effettivamente eseguito. Questa funzione non trasferisce denaro. Il saldo e la ripartizione dei pagamenti saranno ricalcolati."
                         : "La nota di credito riduce l'addebito originale. Non è un rimborso di denaro e non annulla una lezione completata.")
                    Text("La rettifica sarà permanente e collegata al movimento originale.")
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
            .navigationTitle(isRefund ? "Registra rimborso" : "Nota di credito")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }.keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Registra", action: validate)
                        .keyboardShortcut(.defaultAction).disabled(operation.committed)
                }
            }
        }
        .businessEditorSize()
        .interactiveDismissDisabled()
        .confirmationDialog("Confermare la rettifica permanente?", isPresented: $confirming,
                            titleVisibility: .visible) {
            Button("Registra rettifica", action: save)
            Button("Torna alla rettifica", role: .cancel) {}
        } message: {
            Text("\(isRefund ? "Rimborso" : "Nota di credito") di \(amount) € per \(entry.clientName).")
        }
        .businessError($operation, onCommitted: { dismiss() })
    }

    private func validate() {
        do {
            let cents = try Money.parse(amount)
            guard cents > 0 && cents <= maximum else {
                throw BusinessInputError(message: "Inserisci un importo maggiore di zero e non superiore a \(Money.format(maximum)).")
            }
            guard !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw BusinessInputError(message: "Indica il motivo della rettifica.")
            }
            confirming = true
        } catch { operation.capture(error) }
    }

    private func save() {
        do {
            let repository = BusinessRepository(context: context)
            if isRefund {
                _ = try repository.recordRefund(paymentID: entry.id, amountCents: Money.parse(amount),
                                                 date: date, notes: notes)
            } else {
                _ = try repository.recordCredit(chargeID: entry.id, amountCents: Money.parse(amount),
                                                 date: date, notes: notes)
            }
            dismiss()
        } catch { operation.capture(error) }
    }
}

struct ClientAllocationsView: View {
    let clientID: UUID
    @Query private var entries: [LedgerEntry]

    private var statement: AccountStatement {
        BusinessReports.statement(clientID: clientID, from: .distantPast, to: .distantFuture, entries: entries)
    }
    private var allocations: [PaymentAllocation] {
        BusinessReports.allocations(clientID: clientID, entries: entries)
    }

    var body: some View {
        Group {
            if let error = _entries.fetchError {
                ArchiveReadErrorView(error: error)
            } else {
                List {
                    Section {
                        BalanceLabel(cents: statement.closingBalance)
                        Text("Ripartizione automatica dal più vecchio addebito al più recente (FIFO), ricalcolata considerando rimborsi e note di credito. Un anticipo può coprire addebiti successivi.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if statement.entries.allSatisfy({ $0.kind != .payment }) {
                        ContentUnavailableView("Nessun pagamento registrato", systemImage: "eurosign.circle")
                    }
                    ForEach(statement.entries.filter { $0.kind == .payment }) { payment in
                        allocationSection(payment)
                    }
                }
            }
        }
        .navigationTitle("Ripartizione pagamenti")
    }

    private func allocationSection(_ payment: LedgerEntry) -> some View {
        let paymentAllocations = allocations.filter { $0.paymentID == payment.id }
        let afterRefunds = statement.entries.filter { $0.originalEntryID == payment.id && $0.kind == .refund }
            .reduce(max(0, payment.amountCents)) { max(0, $0 - min($0, max(0, $1.amountCents))) }
        let unallocated = paymentAllocations.reduce(afterRefunds) { max(0, $0 - min($0, $1.amountCents)) }
        return Section("Pagamento del \(BusinessFormatting.day(payment.date))") {
            NavigationLink { LedgerEntryDetailView(entry: payment) } label: { LedgerEntryRow(entry: payment) }
            ForEach(Array(paymentAllocations.enumerated()), id: \.offset) { _, allocation in
                if let charge = statement.entries.first(where: { $0.id == allocation.chargeID }) {
                    NavigationLink { LedgerEntryDetailView(entry: charge) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            LabeledContent("Addebito del \(BusinessFormatting.day(charge.date))",
                                           value: Money.format(allocation.amountCents))
                            if !charge.notes.isEmpty {
                                Text(charge.notes).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            LabeledContent("Non ancora assegnato (anticipo)", value: Money.format(unallocated))
        }
    }
}
