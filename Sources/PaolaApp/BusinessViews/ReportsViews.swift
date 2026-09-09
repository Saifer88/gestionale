import PaolaCore
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct ReportsView: View {
    @Query private var entries: [LedgerEntry]
    @Query private var clients: [Client]
    @Query private var sessions: [TrainingSession]
    @Query private var participants: [SessionParticipant]
    @Query private var packages: [LessonPackage]
    @Query private var uses: [PackageUse]
    @State private var selectedClientID: UUID?
    @State private var from = BusinessDates.monthStart
    @State private var through = Date()
    @State private var preview: BusinessReportSnapshot?
    @State private var exportDocument: BusinessExportDocument?
    @State private var exportType = UTType.commaSeparatedText
    @State private var exportFilename = "Estratto-conto"
    @State private var exporting = false
    @State private var preparingExport = false
    @State private var exportMessage = ""
    @State private var operation = BusinessOperation()

    init(clientID: UUID? = nil) {
        _selectedClientID = State(initialValue: clientID)
    }

    private var start: Date { Calendar.current.startOfDay(for: from) }
    private var end: Date { BusinessDates.exclusiveEnd(through) }
    private var validPeriod: Bool { start < end }
    private var readError: Error? {
        _entries.fetchError ?? _clients.fetchError ?? _sessions.fetchError ?? _participants.fetchError
            ?? _packages.fetchError ?? _uses.fetchError
    }
    private var reportWarnings: [String] {
        BusinessReports.integrityWarnings(entries: entries, packages: packages, uses: uses)
    }
    private var statement: AccountStatement {
        BusinessReports.statement(clientID: selectedClientID, from: start, to: end, entries: entries)
    }
    private var filteredSessions: [TrainingSession] {
        guard let selectedClientID else { return sessions }
        let ids = Set(participants.filter { $0.clientID == selectedClientID }.map(\.sessionID))
        return sessions.filter { ids.contains($0.id) }
    }
    private var statistics: BusinessStatistics {
        BusinessReports.statistics(from: start, to: end, sessions: filteredSessions,
                                   entries: entries.filter { selectedClientID == nil || $0.clientID == selectedClientID })
    }
    private var unpaid: [BusinessReportSnapshot.Unpaid] {
        let closingEntries = entries.filter { $0.date < end }
        let ids = Set(closingEntries.map(\.clientID)).filter { selectedClientID == nil || $0 == selectedClientID }
        return ids.compactMap { id in
            let balance = BusinessReports.balance(clientID: id, entries: closingEntries)
            guard balance > 0 else { return nil }
            let client = clients.first { $0.id == id }
            return BusinessReportSnapshot.Unpaid(id: id,
                                                 name: client?.fullName ?? closingEntries.first { $0.clientID == id }?.clientName ?? "Cliente storico",
                                                 balance: balance, archived: client?.isArchived ?? false)
        }.sorted {
            $0.balance == $1.balance ? $0.name.localizedStandardCompare($1.name) == .orderedAscending : $0.balance > $1.balance
        }
    }

    var body: some View {
        Group {
            if let error = readError {
                ArchiveReadErrorView(error: error)
            } else {
                reportList
            }
        }
        .navigationTitle("Report ed estratto conto")
        .accessibilityIdentifier("reports.screen")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Anteprima", systemImage: "doc.text.magnifyingglass") { preview = snapshot() }
                        .accessibilityIdentifier("reports.preview")
                    Button("Esporta CSV", systemImage: "tablecells") { export(.commaSeparatedText) }
                        .accessibilityIdentifier("reports.export.csv")
                    Button("Esporta PDF", systemImage: "doc.richtext") { export(.pdf) }
                        .accessibilityIdentifier("reports.export.pdf")
                } label: {
                    Label("Documento", systemImage: "square.and.arrow.up")
                }
                .accessibilityIdentifier("reports.document")
                .disabled(!validPeriod || readError != nil || preparingExport)
            }
        }
        .overlay {
            if preparingExport {
                ProgressView("Preparazione del documento…")
                    .padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .sheet(item: $preview) { ReportPreviewView(report: $0) }
        .fileExporter(isPresented: $exporting, document: exportDocument, contentType: exportType,
                      defaultFilename: exportFilename) { result in
            switch result {
            case .success:
                exportMessage = "Documento esportato nella destinazione scelta."
            case .failure(let error):
                operation.capture(error)
            }
        }
        .businessError($operation)
    }

    private var reportList: some View {
        List {
            Section("Periodo e cliente") {
                BusinessPeriodPicker(from: $from, through: $through, identifierPrefix: "reports")
                BusinessClientPicker(title: "Cliente", clients: clients,
                                     selection: $selectedClientID, allowsAll: true)
                    .accessibilityIdentifier("reports.client")
            }
            .disabled(preparingExport)
            if validPeriod {
                if !reportWarnings.isEmpty {
                    Section("Dati da verificare") {
                        ForEach(reportWarnings, id: \.self) { warning in
                            Label(warning, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                        }
                    }
                }
                balanceSection
                activitySection
                unpaidSection
                Section("Movimenti del periodo · \(statement.entries.count)") {
                    if statement.entries.isEmpty {
                        Text("Nessun movimento nel periodo selezionato. Il saldo iniziale può includere movimenti precedenti.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(statement.entries) { entry in
                        NavigationLink { LedgerEntryDetailView(entry: entry) } label: { LedgerEntryRow(entry: entry) }
                    }
                }
                Section {
                    Button("Anteprima del documento", systemImage: "doc.text.magnifyingglass") { preview = snapshot() }
                        .accessibilityIdentifier("reports.preview.inline")
                    Button("Esporta CSV", systemImage: "tablecells") { export(.commaSeparatedText) }
                        .accessibilityIdentifier("reports.export.csv.inline")
                    Button("Esporta PDF", systemImage: "doc.richtext") { export(.pdf) }
                        .accessibilityIdentifier("reports.export.pdf.inline")
                    if !exportMessage.isEmpty {
                        Label(exportMessage, systemImage: "checkmark.circle").foregroundStyle(.teal)
                    }
                } header: {
                    Text("DOCUMENTO NON FISCALE")
                } footer: {
                    Text("Prospetto organizzativo, non è una fattura né una ricevuta fiscale. CSV e PDF includono tutti i movimenti del periodo. Scegli esplicitamente la destinazione; i documenti non vengono condivisi automaticamente.")
                }
                .disabled(preparingExport)
            }
        }
    }

    private var balanceSection: some View {
        Section("Riepilogo economico") {
            LabeledContent("Saldo iniziale", value: Money.format(statement.openingBalance))
            LabeledContent("Addebiti nel periodo", value: Money.format(statement.chargedCents))
            LabeledContent("Incassi registrati", value: Money.format(statement.paidCents))
            LabeledContent("Rimborsi", value: Money.format(statement.refundedCents))
            LabeledContent("Note di credito", value: Money.format(statement.creditedCents))
            LabeledContent("Saldo finale", value: Money.format(statement.closingBalance))
                .fontWeight(.semibold)
            Text("Saldo positivo: importo da saldare. Saldo negativo: credito del cliente. Il saldo iniziale include i movimenti precedenti al primo giorno; quello finale include tutto l'ultimo giorno.")
                .font(.caption).foregroundStyle(.secondary)
            if selectedClientID == nil {
                Text("Il saldo complessivo compensa crediti e debiti di clienti diversi. Consulta anche l'elenco degli importi da saldare.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var activitySection: some View {
        Section("Attività svolta") {
            LabeledContent("Lezioni completate", value: "\(statistics.completedSessions)")
            LabeledContent("Ore lavorate") {
                Text(statistics.workedMinutes / 60, format: .number.precision(.fractionLength(2)))
            }
            LabeledContent("Incasso netto per ora") {
                if let ratio = statistics.hourlyIncomeCents {
                    Text(ratio / 100, format: .currency(code: "EUR"))
                } else {
                    Text("Non calcolabile").foregroundStyle(.secondary)
                }
            }
            Label("Gli anticipi influenzano il rapporto orario", systemImage: "info.circle")
                .font(.subheadline).foregroundStyle(.orange)
            Text("Il rapporto è (incassi − rimborsi) / ore svolte. I pacchetti sono incassati alla registrazione, le lezioni singole al completamento; le lezioni coperte da pacchetto non generano un secondo incasso. Gli orari sovrapposti non raddoppiano le ore.")
                .font(.caption).foregroundStyle(.secondary)
            if statistics.popularHours.isEmpty {
                Text("Nessun orario frequente: non ci sono lezioni completate nel periodo.")
                    .foregroundStyle(.secondary)
            } else {
                Text("Orari più frequenti · inizio lezioni completate").font(.subheadline.bold())
                ForEach(statistics.popularHours.keys.sorted(), id: \.self) { hour in
                    HStack {
                        Text(String(format: "%02d:00", hour)).monospacedDigit().frame(width: 52, alignment: .leading)
                        ProgressView(value: Double(statistics.popularHours[hour] ?? 0),
                                     total: Double(max(1, statistics.popularHours.values.max() ?? 1)))
                        Text("\(statistics.popularHours[hour] ?? 0)").monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private var unpaidSection: some View {
        Section("Importi da saldare alla data finale · \(unpaid.count) clienti") {
            if unpaid.isEmpty {
                Label("Nessun importo da saldare", systemImage: "checkmark.circle").foregroundStyle(.teal)
            }
            ForEach(unpaid) { client in
                NavigationLink {
                    PaymentsView(clientID: client.id)
                } label: {
                    LabeledContent(client.name + (client.archived ? " · archiviato" : ""),
                                   value: Money.format(client.balance))
                }
            }
        }
    }

    private func snapshot() -> BusinessReportSnapshot {
        let account = statement
        let stats = statistics
        let client = clients.first { $0.id == selectedClientID }
        let label = selectedClientID == nil ? "Tutti i clienti" :
            (client?.fullName ?? account.entries.first?.clientName ?? "Cliente storico")
                + (client?.isArchived == true ? " · archiviato" : "")
        return BusinessReportSnapshot(
            clientLabel: label, from: start, through: Calendar.current.startOfDay(for: through), generatedAt: Date(),
            openingBalance: account.openingBalance, closingBalance: account.closingBalance,
            chargedCents: account.chargedCents, paidCents: account.paidCents,
            refundedCents: account.refundedCents, creditedCents: account.creditedCents,
            workedMinutes: stats.workedMinutes, completedSessions: stats.completedSessions,
            popularHours: stats.popularHours, hourlyIncomeCents: stats.hourlyIncomeCents,
            movements: account.entries.map {
                BusinessReportSnapshot.Movement(id: $0.id, date: $0.date, client: $0.clientName,
                                                kind: $0.kind.title, amountCents: $0.amountCents,
                                                method: $0.kind == .payment || $0.kind == .refund ? $0.method.title : "",
                                                notes: $0.notes, originalID: $0.originalEntryID)
            },
            unpaid: unpaid, warnings: reportWarnings
        )
    }

    private func export(_ type: UTType) {
        guard validPeriod, readError == nil, !preparingExport else { return }
        let report = snapshot()
        exportFilename = "Estratto-conto-\(filenameDate(report.from))-\(filenameDate(report.through))"
        preparingExport = true
        exportMessage = ""
        Task { @MainActor in
            do {
                let data = try await Task.detached(priority: .userInitiated) {
                    if type == .pdf { return try BusinessExport.pdf(report) }
                    return BusinessExport.csv(report)
                }.value
                exportDocument = BusinessExportDocument(data: data)
                exportType = type
                preparingExport = false
                exporting = true
            } catch {
                preparingExport = false
                operation.capture(error)
            }
        }
    }

    private func filenameDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

struct ReportPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    let report: BusinessReportSnapshot

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(report.plainText)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(24)
            }
            .navigationTitle("Anteprima · non fiscale")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Chiudi") { dismiss() }.keyboardShortcut(.cancelAction)
                        .accessibilityIdentifier("reports.preview.close")
                }
            }
        }
        .businessEditorSize()
    }
}
