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
                HStack(alignment: .center, spacing: 8) {
                    // Spazio riservato per isPaid per allineamento uniforme
                    Group {
                        if let onTogglePaid, person.packageID == nil {
                            paidToggle(for: person, action: onTogglePaid)
                        } else {
                            Color.clear.frame(width: 24, height: 24)
                        }
                    }
                    Text(clients.first(where: { $0.id == person.clientID })?.fullName ?? person.clientName)
                        .font(.body.weight(.medium))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    if person.packageID != nil {
                        Image(systemName: "shippingbox.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(Money.format(person.priceCents))
                            .font(.subheadline)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
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
            if !session.notes.isEmpty {
                Text(session.notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(.primary)
        .padding(.vertical, 3).padding(.horizontal, 10)
        .background(backgroundColorForStatus, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityValue(session.status.title)
    }

    private var backgroundColorForStatus: Color {
        switch session.status {
        case .completed:
            return Color.green.opacity(0.15)
        case .provisional:
            return Color.orange.opacity(0.15)
        default:
            return Color.secondary.opacity(0.06)
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