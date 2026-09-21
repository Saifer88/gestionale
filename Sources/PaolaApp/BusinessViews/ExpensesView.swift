import PaolaCore
import SwiftData
import SwiftUI

/// Pagina Spese: elenco delle spese una tantum e ricorrenti mensili, con i totali
/// mensile e annuale del periodo corrente in alto a destra.
/// Wrapper identificabile per presentare l'editor (ExpenseDraft non è Identifiable).
private struct ExpenseEditTarget: Identifiable {
    let id = UUID()
    let draft: ExpenseDraft
}

struct ExpensesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @Query private var sessions: [TrainingSession]
    @State private var editing: ExpenseEditTarget?
    @State private var operation = BusinessOperation()

    private func session(for expense: Expense) -> TrainingSession? {
        guard let id = expense.feeSessionID else { return nil }
        return sessions.first { $0.id == id }
    }

    private var oneTime: [Expense] { expenses.filter { $0.kind == .oneTime } }
    private var recurring: [Expense] { expenses.filter { $0.kind == .monthlyRecurring } }

    private var monthlyCents: Int64 {
        let calendar = SchedulingSuggestions.calendar
        guard let month = calendar.dateInterval(of: .month, for: Date()) else { return 0 }
        return ExpenseReports.total(expenses, from: month.start, to: month.end, calendar: calendar)
    }
    private var annualCents: Int64 {
        let calendar = SchedulingSuggestions.calendar
        // Somma solo i mesi passati e quello corrente, non i futuri: il totale annuale
        // si ferma alla fine del mese corrente.
        guard let year = calendar.dateInterval(of: .year, for: Date()),
              let month = calendar.dateInterval(of: .month, for: Date()) else { return 0 }
        return ExpenseReports.total(expenses, from: year.start, to: min(year.end, month.end), calendar: calendar)
    }
    private var monthlyPersonalCents: Int64 {
        let calendar = SchedulingSuggestions.calendar
        guard let month = calendar.dateInterval(of: .month, for: Date()) else { return 0 }
        return ExpenseReports.totalPersonal(expenses, from: month.start, to: month.end, calendar: calendar)
    }
    private var annualPersonalCents: Int64 {
        let calendar = SchedulingSuggestions.calendar
        guard let year = calendar.dateInterval(of: .year, for: Date()),
              let month = calendar.dateInterval(of: .month, for: Date()) else { return 0 }
        return ExpenseReports.totalPersonal(expenses, from: year.start, to: min(year.end, month.end), calendar: calendar)
    }

    var body: some View {
        Group {
            if let error = _expenses.fetchError ?? _sessions.fetchError {
                ArchiveReadErrorView(error: error)
            } else {
                content
            }
        }
        .sectionTitle(.expenses)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editing = ExpenseEditTarget(draft: ExpenseDraft())
                } label: {
                    Label("Nuova spesa", systemImage: "plus")
                }
                .accessibilityIdentifier("expenses.add")
            }
        }
        .sheet(item: $editing) { target in
            ExpenseEditor(draft: target.draft)
        }
        .businessError($operation)
    }

    private var content: some View {
        List {
            Section {
                HStack(alignment: .top, spacing: 12) {
                    totalsColumn(title: "Spese attività",
                                 month: monthlyCents, year: annualCents,
                                 tint: .orange, idPrefix: "expenses.total")
                    totalsColumn(title: "Spese personali",
                                 month: monthlyPersonalCents, year: annualPersonalCents,
                                 tint: .pink, idPrefix: "expenses.personal.total")
                }
            } footer: {
                Text("Le spese ricorrenti mensili sono considerate il primo giorno di ogni mese. Le spese personali sono escluse dai riepiloghi economici.")
            }
            if recurring.isEmpty && oneTime.isEmpty {
                ContentUnavailableView("Nessuna spesa", systemImage: "banknote",
                                       description: Text("Aggiungi una spesa con il pulsante in alto."))
            }
            if !recurring.isEmpty {
                Section("Ricorrenti mensili") {
                    ForEach(recurring) { expense in row(expense, showsDate: false) }
                }
            }
            if !oneTime.isEmpty {
                Section("Una tantum") {
                    ForEach(oneTime) { expense in row(expense, showsDate: true) }
                }
            }
        }
    }

    /// Colonna di totali (mese/anno) per il recap in alto: usata sia per le spese
    /// attività sia per le spese personali, stesso stile.
    private func totalsColumn(title: String, month: Int64, year: Int64,
                              tint: Color, idPrefix: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(tint)
            LabeledContent("Mese") {
                Text(Money.format(month)).monospacedDigit().font(.headline)
            }
            .accessibilityIdentifier("\(idPrefix).month")
            LabeledContent("Anno") {
                Text(Money.format(year)).monospacedDigit().font(.headline)
            }
            .accessibilityIdentifier("\(idPrefix).year")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func row(_ expense: Expense, showsDate: Bool) -> some View {
        if expense.isAutomaticFee {
            automaticFeeRow(expense)
        } else {
            manualRow(expense, showsDate: showsDate)
        }
    }

    /// Riga di una spesa manuale: modificabile (tap sul contenuto) ed eliminabile
    /// con il pulsante cestino a destra (oltre a swipe e menu contestuale).
    private func manualRow(_ expense: Expense, showsDate: Bool) -> some View {
        HStack {
            Button {
                editing = ExpenseEditTarget(draft: ExpenseDraft(expense))
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(expense.name).font(.body)
                            if expense.isPersonal {
                                Image(systemName: "person.fill")
                                    .font(.caption2).foregroundStyle(.orange)
                            }
                        }
                        Text(showsDate ? BusinessFormatting.day(expense.date)
                                       : "Dal \(BusinessFormatting.day(expense.date))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(Money.format(expense.amountCents)).monospacedDigit()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(role: .destructive) {
                delete(expense)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.red)
            .help("Elimina spesa")
            .accessibilityIdentifier("expenses.delete.\(expense.id.uuidString)")
        }
        .swipeActions {
            Button("Elimina", role: .destructive) { delete(expense) }
        }
        .contextMenu {
            Button("Modifica") { editing = ExpenseEditTarget(draft: ExpenseDraft(expense)) }
            Button("Elimina", role: .destructive) { delete(expense) }
        }
        .accessibilityIdentifier("expenses.row.\(expense.id.uuidString)")
    }

    /// Riga di una commissione automatica (Stripe/carta): non modificabile né
    /// eliminabile a mano. Mostra una nota e, se collega un appuntamento, un link rapido.
    @ViewBuilder private func automaticFeeRow(_ expense: Expense) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(expense.name).font(.body)
                    Text(BusinessFormatting.day(expense.date))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(Money.format(expense.amountCents)).monospacedDigit()
            }
            if let session = session(for: expense) {
                NavigationLink(value: AppRoute.session(session.id)) {
                    Label("Relativa a un appuntamento — modifica o elimina l'appuntamento per rimuoverla",
                          systemImage: "link")
                        .font(.caption)
                }
                .accessibilityIdentifier("expenses.fee.link.\(expense.id.uuidString)")
            } else {
                Label("Commissione automatica: si rimuove modificando o eliminando l'incasso collegato.",
                      systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("expenses.row.\(expense.id.uuidString)")
    }

    private func delete(_ expense: Expense) {
        do { try BusinessRepository(context: context).deleteExpense(expense.id) }
        catch { operation.capture(error) }
    }
}

/// Editor di una spesa: nome, importo, tipo (una tantum / ricorrente mensile) e data.
struct ExpenseEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    private let id: UUID?
    @State private var name: String
    @State private var amount: String
    @State private var kind: ExpenseKind
    @State private var date: Date
    @State private var isPersonal: Bool
    @State private var operation = BusinessOperation()

    init(draft: ExpenseDraft) {
        id = draft.id
        _name = State(initialValue: draft.name)
        _amount = State(initialValue: BusinessFormatting.editableMoney(draft.amountCents))
        _kind = State(initialValue: draft.kind)
        _date = State(initialValue: draft.date)
        _isPersonal = State(initialValue: draft.isPersonal)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nome della spesa", text: $name)
                        .accessibilityIdentifier("expense.name")
                    MoneyField(title: "Importo (€)", text: $amount)
                        .accessibilityIdentifier("expense.amount")
                    Picker("Tipo", selection: $kind) {
                        ForEach(ExpenseKind.allCases) { Text($0.title).tag($0) }
                    }
                    .accessibilityIdentifier("expense.kind")
                    DatePicker(kind == .monthlyRecurring ? "Attiva dal" : "Data spesa",
                               selection: $date, displayedComponents: .date)
                        .accessibilityIdentifier("expense.date")
                    Toggle("Spesa personale", isOn: $isPersonal)
                        .accessibilityIdentifier("expense.isPersonal")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(kind == .monthlyRecurring
                             ? "Sarà considerata il primo giorno di ogni mese, a partire dal mese indicato."
                             : "Spesa singola registrata nella data indicata.")
                        if isPersonal {
                            Text("Le spese personali sono escluse dai riepiloghi economici (spese, EBIT, netto).")
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(id == nil ? "Nuova spesa" : "Spesa")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }.keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") { save() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(operation.committed)
                        .accessibilityIdentifier("expense.save")
                }
            }
        }
        .businessEditorSize()
        .interactiveDismissDisabled()
        .businessError($operation, onCommitted: { dismiss() })
    }

    private func save() {
        guard !operation.committed else { return }
        do {
            var draft = ExpenseDraft()
            draft.id = id
            draft.name = name
            draft.amountCents = try Money.parse(amount)
            draft.kind = kind
            draft.date = date
            draft.isPersonal = isPersonal
            _ = try BusinessRepository(context: context).saveExpense(draft)
            dismiss()
        } catch { operation.capture(error) }
    }
}
