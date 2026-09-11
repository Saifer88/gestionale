import Foundation
import PaolaCore
import SwiftUI

struct BusinessOperation {
    var error: FormError?
    var committed = false

    mutating func capture(_ error: Error) {
        self.error = FormError(error)
        committed = error is ClientPersistenceError
    }
}

private struct BusinessErrorModifier: ViewModifier {
    @Binding var operation: BusinessOperation
    var onCommitted: () -> Void

    func body(content: Content) -> some View {
        content.alert(operation.committed ? "Dati già salvati" : "Operazione non riuscita",
                      isPresented: Binding(
                        get: { operation.error != nil },
                        set: { if !$0 { operation.error = nil } }
                      )) {
            Button("OK", role: .cancel) {
                operation.error = nil
                if operation.committed { onCommitted() }
            }
        } message: {
            Text(operation.error?.message ?? "")
        }
    }
}

extension View {
    func businessError(_ operation: Binding<BusinessOperation>,
                       onCommitted: @escaping () -> Void = {}) -> some View {
        modifier(BusinessErrorModifier(operation: operation, onCommitted: onCommitted))
    }

    func businessEditorSize() -> some View {
        #if os(macOS)
        frame(minWidth: 540, idealWidth: 620, minHeight: 540, idealHeight: 720)
        #else
        self
        #endif
    }
}

struct MoneyField: View {
    let title: String
    @Binding var text: String

    var body: some View {
        TextField(title, text: $text)
            .autocorrectionDisabled()
            #if os(iOS)
            .keyboardType(.decimalPad)
            #endif
    }
}

struct BalanceLabel: View {
    let cents: Int64

    var body: some View {
        LabeledContent(BusinessFormatting.balanceTitle(cents)) {
            Text(BusinessFormatting.balanceAmount(cents))
                .monospacedDigit()
                .foregroundStyle(cents > 0 ? Color.orange : cents < 0 ? .teal : .secondary)
        }
    }
}

struct SessionStatusLabel: View {
    let status: SessionStatus

    var body: some View {
        Label(status.title, systemImage: icon)
            .font(.caption)
            .foregroundStyle(color)
    }

    private var color: Color {
        switch status {
        case .provisional: return .orange
        case .planned: return .blue
        case .completed: return .teal
        case .cancelled, .noShow: return .secondary
        }
    }

    private var icon: String {
        switch status {
        case .provisional: return "calendar.badge.clock"
        case .planned: return "calendar"
        case .completed: return "checkmark.circle.fill"
        case .cancelled: return "xmark.circle"
        case .noShow: return "person.crop.circle.badge.xmark"
        }
    }
}

struct BusinessClientPicker: View {
    let title: String
    let clients: [Client]
    @Binding var selection: UUID?
    var allowsAll = false

    var body: some View {
        Picker(title, selection: $selection) {
            Text(allowsAll ? "Tutti i clienti" : "Seleziona cliente").tag(nil as UUID?)
            ForEach(clients.sorted {
                $0.fullName.localizedStandardCompare($1.fullName) == .orderedAscending
            }) { client in
                Text(client.fullName + (client.isArchived ? " · archiviato" : ""))
                    .tag(Optional(client.id))
            }
        }
    }
}

struct BusinessPeriodPicker: View {
    @Binding var from: Date
    @Binding var through: Date
    var identifierPrefix = "period"

    var body: some View {
        DatePicker("Dal", selection: $from, displayedComponents: .date)
            .accessibilityIdentifier("\(identifierPrefix).from")
        DatePicker("Al (compreso)", selection: $through, displayedComponents: .date)
            .accessibilityIdentifier("\(identifierPrefix).through")
        if Calendar.current.startOfDay(for: through) < Calendar.current.startOfDay(for: from) {
            Label("La data finale deve essere successiva o uguale a quella iniziale.",
                  systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        }
    }
}

enum BusinessDates {
    static var monthStart: Date {
        Calendar.current.dateInterval(of: .month, for: Date())?.start
            ?? Calendar.current.startOfDay(for: Date())
    }

    static func exclusiveEnd(_ inclusiveDate: Date) -> Date {
        let start = Calendar.current.startOfDay(for: inclusiveDate)
        return Calendar.current.date(byAdding: .day, value: 1, to: start)
            ?? start.addingTimeInterval(86400)
    }

    static func overlaps(_ start: Date, _ end: Date, _ otherStart: Date, _ otherEnd: Date) -> Bool {
        start < otherEnd && otherStart < end
    }

    static func conflicts(for session: TrainingSession, sessions: [TrainingSession],
                          blocks: [Unavailability]) -> [String] {
        guard session.status == .planned || session.status == .completed else { return [] }
        let otherSessions = sessions.filter {
            $0.id != session.id && ($0.status == .planned || $0.status == .completed)
                && overlaps(session.startDate, session.endDate, $0.startDate, $0.endDate)
        }.map { "\($0.serviceName) · \(BusinessFormatting.dateTime($0.startDate))" }
        let otherBlocks = blocks.filter {
            overlaps(session.startDate, session.endDate, $0.startDate, $0.endDate)
        }.map { "Indisponibilità: \($0.title)" }
        return otherSessions + otherBlocks
    }
}

struct SessionSummaryRow: View {
    let session: TrainingSession
    let participants: [SessionParticipant]
    var conflict = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(session.startDate, format: .dateTime.hour().minute())
                    .monospacedDigit()
                Text(session.serviceName).font(.headline)
                Spacer()
                Text("\(session.durationMinutes) min")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(participants.filter { $0.sessionID == session.id }.map(\.clientName).joined(separator: " + "))
            HStack {
                SessionStatusLabel(status: session.status)
            }
            if conflict {
                Label("Sovrapposizione da verificare", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 4)
    }
}
