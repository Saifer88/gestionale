import PaolaCore
import SwiftUI

struct CalendarSessionRow: View {
    let session: TrainingSession
    let participants: [SessionParticipant]
    let clients: [Client]
    var conflict = false

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
                VStack(alignment: .leading, spacing: 4) {
                    Text(clients.first(where: { $0.id == person.clientID })?.fullName ?? person.clientName)
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(Money.format(person.priceCents)).monospacedDigit()
                    if person.packageID != nil {
                        Text("Pacchetto in uso").font(.caption).foregroundStyle(.secondary)
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
}
