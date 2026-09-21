import PaolaCore
import SwiftUI

struct CalendarSessionRow: View {
    let session: TrainingSession
    let participants: [SessionParticipant]
    let clients: [Client]
    var conflict = false
    /// Commuta il contrassegno "pagato" del partecipante indicato. Se nil, l'icona non
    /// viene mostrata (es. contesti di sola lettura come la panoramica).
    var onTogglePaid: ((SessionParticipant) -> Void)? = nil

    private var people: [SessionParticipant] {
        var seen = Set<UUID>()
        return participants.filter { $0.sessionID == session.id }
            .sorted { $0.clientName.localizedStandardCompare($1.clientName) == .orderedAscending }
            .filter { seen.insert($0.clientID).inserted }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(SchedulingSuggestions.hourLabel(session.startDate)) – \(SchedulingSuggestions.hourLabel(session.endDate))")
                .font(.subheadline.weight(.semibold)).monospacedDigit()
            ForEach(people) { person in
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(clients.first(where: { $0.id == person.clientID })?.fullName ?? person.clientName)
                            .font(.headline)
                            .fixedSize(horizontal: false, vertical: true)
                        if person.packageID != nil {
                            Text("Pacchetto in uso").font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text(Money.format(person.priceCents)).monospacedDigit()
                        }
                    }
                    // Icona "pagato" allineata in alto, alla stessa altezza del nome del
                    // partecipante. Solo per chi non usa un pacchetto.
                    if let onTogglePaid, person.packageID == nil {
                        Spacer(minLength: 0)
                        paidToggle(for: person, action: onTogglePaid)
                    }
                }
            }
            if people.isEmpty {
                Label("Cliente non disponibile", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
            if conflict {
                Label("Sovrapposizione", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(.primary)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityValue(session.status.title)
    }

    /// Interruttore "pagato" a icona del singolo partecipante, senza aprire il dettaglio.
    @ViewBuilder private func paidToggle(for participant: SessionParticipant,
                                         action: @escaping (SessionParticipant) -> Void) -> some View {
        Button {
            action(participant)
        } label: {
            Image(systemName: participant.isPaid ? "eurosign.circle.fill" : "eurosign.circle")
                .font(.callout)
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
