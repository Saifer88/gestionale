import PaolaCore
import SwiftUI

struct CalendarSessionRow: View {
    let session: TrainingSession
    let participants: [SessionParticipant]
    let clients: [Client]
    var conflict = false
    var onTogglePaid: ((SessionParticipant) -> Void)? = nil

    private var people: [SessionParticipant] {
        var seen = Set<UUID>()
        return participants.filter { $0.sessionID == session.id }
            .sorted { $0.clientName.localizedStandardCompare($1.clientName) == .orderedAscending }
            .filter { seen.insert($0.clientID).inserted }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(SchedulingSuggestions.hourLabel(session.startDate)) – \(SchedulingSuggestions.hourLabel(session.endDate))")
                .font(.subheadline.weight(.semibold)).monospacedDigit()
                .foregroundStyle(.secondary)
            ForEach(people) { person in
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(clients.first(where: { $0.id == person.clientID })?.fullName ?? person.clientName)
                            .font(.body.weight(.medium))
                            .fixedSize(horizontal: false, vertical: true)
                        if person.packageID != nil {
                            Text("Pacchetto in uso").font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text(Money.format(person.priceCents)).monospacedDigit()
                        }
                        if let onTogglePaid, person.packageID == nil {
                            paidToggle(for: person, action: onTogglePaid)
                        }
                    }
                }
            }
            if people.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle")
                    Text("Cliente non disponibile")
                }
                .font(.caption)
                .foregroundStyle(.orange)
            }
            if conflict {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle")
                    Text("Sovraposizione")
                }
                .font(.caption)
                .foregroundStyle(.orange)
            }
            statusBadge
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(.primary)
        .padding(.vertical, 6).padding(.horizontal, 10)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityValue(session.status.title)
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch session.status {
        case .completed:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                Text("Completato")
            }
            .font(.caption2)
            .foregroundStyle(.green)
        case .provisional:
            HStack(spacing: 4) {
                Image(systemName: "circle.dashed")
                Text("Provvisorio")
            }
            .font(.caption2)
            .foregroundStyle(.orange)
        default:
            EmptyView()
        }
    }

    @ViewBuilder private func paidToggle(for participant: SessionParticipant,
                                         action: @escaping (SessionParticipant) -> Void) -> some View {
        Button {
            action(participant)
        } label: {
            Image(systemName: participant.isPaid ? "eurosign.circle.fill" : "eurosign.circle")
                .font(.caption)
                .foregroundStyle(participant.isPaid ? Color.green : Color.secondary)
                .padding(4)
                .background((participant.isPaid ? Color.green : Color.secondary).opacity(0.15), in: Circle())
        }
        .buttonStyle(.borderless)
        .help(participant.isPaid
              ? "\(participant.clientName): segnato come pagato. Tocca per annullare."
              : "\(participant.clientName): segna come pagato.")
        .accessibilityLabel(participant.isPaid ? "Pagato: \(participant.clientName)" : "Non pagato: \(participant.clientName)")
        .accessibilityIdentifier("participant.paidToggle.\(participant.id.uuidString)")
    }
}