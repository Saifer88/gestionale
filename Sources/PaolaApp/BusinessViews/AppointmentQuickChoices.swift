import PaolaCore
import SwiftUI

struct AppointmentQuickChoices: View {
    @Binding var startDate: Date
    let durationMinutes: Int
    let sessions: [TrainingSession]
    let blocks: [Unavailability]
    let excludingSessionID: UUID?
    @State private var selectionError: String?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            choices(now: timeline.date)
        }
        .alert("Selezione non disponibile", isPresented: Binding(
            get: { selectionError != nil }, set: { if !$0 { selectionError = nil } }
        )) {
            Button("OK", role: .cancel) { selectionError = nil }
        } message: { Text(selectionError ?? "") }
    }

    @ViewBuilder
    private func choices(now: Date) -> some View {
        switch availableChoices(now: now) {
        case .failure(let error):
            Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
                .font(.caption).foregroundStyle(.orange)
        case .success(let choices):
            VStack(alignment: .leading, spacing: 12) {
                Text("Giorni proposti").font(.subheadline.bold())
                Text("Giorni feriali da oggi a venerdì della prossima settimana")
                    .font(.caption).foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], alignment: .leading, spacing: 8) {
                    ForEach(choices.days, id: \.self) { day in
                        choiceButton(
                            SchedulingSuggestions.dayLabel(day),
                            selected: SchedulingSuggestions.calendar.isDate(day, inSameDayAs: startDate)
                        ) { selectDay(day, now: now) }
                        .accessibilityIdentifier("session.quickDay.\(Int(day.timeIntervalSince1970))")
                    }
                }
                Text("Orari disponibili · \(durationMinutes) minuti").font(.subheadline.bold())
                Text("Ore 7, 8, 9, 10, 13, 14, 15, 16, 17, 18, 19 e 20. Solo orari liberi per l'intera durata.")
                    .font(.caption).foregroundStyle(.secondary)
                if choices.hours.isEmpty {
                    Label("Nessun orario libero a minuti 00 per questo giorno e questa durata.",
                          systemImage: "calendar.badge.exclamationmark")
                        .font(.callout).foregroundStyle(.secondary)
                        .accessibilityIdentifier("session.noQuickHours")
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 68))], alignment: .leading, spacing: 8) {
                        ForEach(choices.hours, id: \.self) { hour in
                            choiceButton(
                                SchedulingSuggestions.hourLabel(hour),
                                selected: abs(startDate.timeIntervalSince(hour)) < 1
                            ) { startDate = hour }
                            .accessibilityIdentifier("session.quickHour.\(SchedulingSuggestions.hourLabel(hour))")
                        }
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("session.quickChoices")
        }
    }

    private func choiceButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.callout)
                .frame(maxWidth: .infinity, minHeight: 28)
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
                .foregroundStyle(selected ? Color.white : Color.primary)
                .background(selected ? Color.teal : Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func availableChoices(now: Date) -> Result<(days: [Date], hours: [Date]), Error> {
        Result {
            (
                try SchedulingSuggestions.suggestedDays(from: now),
                try SchedulingSuggestions.availableHours(
                    on: startDate, durationMinutes: durationMinutes,
                    sessions: sessions, blocks: blocks, excludingSessionID: excludingSessionID, now: now
                )
            )
        }
    }

    private func selectDay(_ day: Date, now: Date) {
        let result = Result {
            try SchedulingSuggestions.availableHours(
                on: day, durationMinutes: durationMinutes, sessions: sessions,
                blocks: blocks, excludingSessionID: excludingSessionID, now: now
            )
        }
        switch result {
        case .success(let hours):
            let currentHour = SchedulingSuggestions.calendar.component(.hour, from: startDate)
            startDate = hours.first(where: { SchedulingSuggestions.calendar.component(.hour, from: $0) == currentHour })
                ?? hours.first ?? day
        case .failure(let error):
            selectionError = error.localizedDescription
        }
    }
}
