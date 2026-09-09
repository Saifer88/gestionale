import Foundation
import PaolaCore

struct AppointmentSelection {
    var serviceID: UUID?
    var durationMinutes: Int
    var rateID: UUID?
    var priceCents: Int64
    var packageID: UUID?
    var startDate: Date
    var notices: [String]

    static func propose(
        clientID: UUID, now: Date = Date(),
        services: [TrainingService], rates: [ServiceRate],
        sessions: [TrainingSession], participants: [SessionParticipant], blocks: [Unavailability],
        packages: [LessonPackage], uses: [PackageUse],
        preferences: [ClientAppointmentPreference],
        calendar: Calendar = SchedulingSuggestions.calendar
    ) throws -> AppointmentSelection {
        let previous = AppointmentPreferences.lastUsed(
            clientID: clientID, sessions: sessions, participants: participants, preferences: preferences
        )
        let activeServices = services.filter(\.isActive).sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        let service = activeServices.first { $0.id == previous?.serviceID } ?? activeServices.first
        let sameService = previous != nil && previous?.serviceID == service?.id
        let options = service.map { ServiceTariffs.options(for: $0, rates: rates) } ?? []
        var selectedRate = options.first
        var price = selectedRate?.priceCents ?? 0
        var notices: [String] = []
        if let previous {
            if sameService {
                if let rate = options.first(where: { $0.id == previous.rateID }) {
                    selectedRate = rate
                    price = rate.priceCents
                    if price != previous.priceCents { notices.append("La tariffa precedente usa il prezzo aggiornato del listino.") }
                } else {
                    price = previous.priceCents
                    selectedRate = previous.rateID == nil ? options.first { $0.priceCents == price } : nil
                    if previous.rateID != nil {
                        notices.append("La tariffa precedente non è più disponibile: mantenuto il prezzo concordato.")
                    }
                }
            } else {
                notices.append("Il servizio precedente non è attivo: proposto il primo servizio disponibile.")
            }
        }
        let duration = sameService ? previous?.durationMinutes ?? service?.durationMinutes ?? 60 : service?.durationMinutes ?? 60
        let days = try SchedulingSuggestions.suggestedDays(from: now, calendar: calendar)
        var candidates: [Date] = []
        for day in days {
            candidates += try SchedulingSuggestions.availableHours(
                on: day, durationMinutes: duration, sessions: sessions, blocks: blocks,
                now: now, calendar: calendar
            )
        }
        var preferred: Date?
        if let previous {
            for day in days {
                guard let candidate = calendar.date(
                    bySettingHour: previous.hour, minute: previous.minute, second: 0, of: day,
                    matchingPolicy: .strict, repeatedTimePolicy: .first
                ), calendar.isDate(candidate, inSameDayAs: day), candidate >= now else { continue }
                if try SchedulingSuggestions.isAvailable(
                    candidate, durationMinutes: duration, sessions: sessions, blocks: blocks
                ) {
                    preferred = candidate
                    break
                }
            }
        }
        let startDate = preferred ?? candidates.first ?? now
        if candidates.isEmpty && preferred == nil {
            notices.append("Nessun orario rapido libero: seleziona manualmente giorno e orario.")
        } else if previous != nil && preferred == nil {
            notices.append("L'orario precedente non è disponibile nelle proposte: selezionato il primo orario libero.")
        }
        var packageID: UUID?
        if let oldID = previous?.packageID {
            if let package = packages.first(where: { $0.id == oldID && $0.clientID == clientID }),
               package.purchasedOn <= startDate,
               package.expiresOn.map({ BusinessDates.exclusiveEnd($0) > startDate }) ?? true,
               BusinessReports.remaining(package: package, uses: uses) > 0 {
                packageID = oldID
            } else {
                notices.append("Il pacchetto precedente è esaurito, scaduto o non disponibile: verifica la scelta prima di salvare.")
            }
        }
        return AppointmentSelection(serviceID: service?.id, durationMinutes: duration,
                                    rateID: selectedRate?.id, priceCents: price, packageID: packageID,
                                    startDate: startDate, notices: notices)
    }
}
