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
    @State private var editing: ExpenseEditTarget?
    @State private var operation = BusinessOperation()

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

    var body: some View {
        Group {
            if let error = _expenses.fetchError {
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
                LabeledContent("Totale mese") {
                    Text(Money.format(monthlyCents)).monospacedDigit().font(.headline)
                }
                .accessibilityIdentifier("expenses.total.month")
                LabeledContent("Totale anno") {
                    Text(Money.format(annualCents)).monospacedDigit().font(.headline)
                }
                .accessibilityIdentifier("expenses.total.year")
            } footer: {
                Text("Le spese ricorrenti mensili sono considerate il primo giorno di ogni mese.")
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

    @ViewBuilder private func row(_ expense: Expense, showsDate: Bool) -> some View {
        Button {
            editing = ExpenseEditTarget(draft: ExpenseDraft(expense))
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(expense.name).font(.body)
                    if showsDate {
                        Text(BusinessFormatting.day(expense.date))
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Dal \(BusinessFormatting.day(expense.date))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(Money.format(expense.amountCents)).monospacedDigit()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions {
            Button("Elimina", role: .destructive) { delete(expense) }
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
    @State private var operation = BusinessOperation()

    init(draft: ExpenseDraft) {
        id = draft.id
        _name = State(initialValue: draft.name)
        _amount = State(initialValue: BusinessFormatting.editableMoney(draft.amountCents))
        _kind = State(initialValue: draft.kind)
        _date = State(initialValue: draft.date)
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
                } footer: {
                    Text(kind == .monthlyRecurring
                         ? "Sarà considerata il primo giorno di ogni mese, a partire dal mese indicato."
                         : "Spesa singola registrata nella data indicata.")
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
            _ = try BusinessRepository(context: context).saveExpense(draft)
            dismiss()
        } catch { operation.capture(error) }
    }
}
