import Foundation
import PaolaCore
import SwiftUI
import UniformTypeIdentifiers

/// Una fascia oraria della griglia giornaliera (dalle 7 alle 21), con gli
/// appuntamenti che iniziano in quell'ora.
struct AgendaHourRow: Identifiable {
    let start: Date
    let hour: Int
    /// Appuntamenti che iniziano in questa fascia oraria, ordinati per orario.
    let sessions: [TrainingSession]
    /// Vero se un altro appuntamento o un'indisponibilità copre l'ora (per il drop).
    let occupantID: UUID?
    let isFree: Bool

    var id: Int { hour }
    var hourLabel: String { SchedulingSuggestions.hourLabel(start) }
    var isEmpty: Bool { sessions.isEmpty }
}

/// Calcolo degli slot disponibili durante il drag & drop e regole di riprogrammazione.
/// Parte senza stato/UI, così la logica resta semplice da leggere e riusare.
enum AgendaScheduling {

    /// Ore mostrate nella griglia del calendario: dalle 7 alle 21 incluse.
    static let gridHours: [Int] = Array(7...21)

    /// Righe orarie di un giorno (7–21) con gli appuntamenti raggruppati per ora
    /// di inizio. Usato per la griglia fissa del calendario.
    ///
    /// - `sessions` sono gli appuntamenti (non annullati/assenza) che iniziano in
    ///   quell'ora, così ogni impegno compare nella fascia corrispondente.
    /// - `occupantID`/`isFree` servono al drag & drop: indicano se la fascia è già
    ///   occupata (per lo scambio) o libera per la durata dell'appuntamento trascinato.
    static func hourRows(on day: Date,
                         draggedSessionID: UUID?,
                         draggedDurationMinutes: Int,
                         sessions: [TrainingSession],
                         blocks: [Unavailability],
                         calendar: Calendar = SchedulingSuggestions.calendar) -> [AgendaHourRow] {
        let startOfDay = calendar.startOfDay(for: day)
        return gridHours.compactMap { hour in
            guard let start = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: startOfDay,
                                            matchingPolicy: .strict, repeatedTimePolicy: .first),
                  calendar.isDate(start, inSameDayAs: day),
                  calendar.component(.hour, from: start) == hour else { return nil }
            let hourSessions = sessions.filter {
                $0.status != .cancelled && $0.status != .noShow
                    && calendar.isDate($0.startDate, inSameDayAs: day)
                    && calendar.component(.hour, from: $0.startDate) == hour
            }.sorted {
                $0.startDate == $1.startDate ? $0.id.uuidString < $1.id.uuidString : $0.startDate < $1.startDate
            }
            let duration = draggedDurationMinutes
            let end = start.addingTimeInterval(Double(duration) * 60)
            let occupant = draggedSessionID == nil ? nil : sessions.first {
                $0.id != draggedSessionID && $0.status != .cancelled && $0.status != .noShow
                    && calendar.isDate($0.startDate, inSameDayAs: day)
                    && calendar.component(.hour, from: $0.startDate) == hour
            }
            let free = !sessions.contains {
                $0.id != draggedSessionID && $0.status != .cancelled && $0.status != .noShow
                    && $0.startDate < end && $0.endDate > start
            } && !blocks.contains { $0.startDate < end && $0.endDate > start }
            return AgendaHourRow(start: start, hour: hour, sessions: hourSessions,
                                 occupantID: occupant?.id, isFree: free)
        }
    }
}

/// Wrapper identificabile per presentare l'editor con una data/ora preimpostata
/// (richiesto da `sheet(item:)`, poiché `Date` non è `Identifiable`).
struct AgendaCreationSlot: Identifiable {
    let date: Date
    var id: TimeInterval { date.timeIntervalSinceReferenceDate }
}

/// Rende una fascia oraria bersaglio di rilascio (drop) durante il trascinamento.
/// Usa `onDrop` con un `NSItemProvider` di testo: più affidabile di `dropDestination`
/// dentro liste e viste con scorrimento. Fuori dal trascinamento non applica alcun
/// gesto, così il "+" resta cliccabile.
struct HourDropModifier: ViewModifier {
    let row: AgendaHourRow
    let dragging: Bool
    let onDrop: (UUID) -> Void

    func body(content: Content) -> some View {
        if dragging {
            content.onDrop(of: [.text], isTargeted: nil) { providers in
                AgendaDragPayload.load(from: providers) { id in onDrop(id) }
            }
        } else {
            content
        }
    }
}

/// Utility per il trasporto dell'identificativo dell'appuntamento durante il
/// drag & drop. Trasporta solo l'UUID come testo: nessun dato personale.
enum AgendaDragPayload {
    /// Crea il provider da trascinare a partire dall'id dell'appuntamento.
    static func provider(for id: UUID) -> NSItemProvider {
        NSItemProvider(object: id.uuidString as NSString)
    }

    /// Estrae l'UUID dai provider rilasciati e invoca `handler` sul main thread.
    /// Ritorna `true` se un provider di testo era presente (drop accettato).
    static func load(from providers: [NSItemProvider], handler: @escaping (UUID) -> Void) -> Bool {
        guard let provider = providers.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else {
            return false
        }
        _ = provider.loadObject(ofClass: NSString.self) { value, _ in
            guard let string = value as? String, let id = UUID(uuidString: string) else { return }
            DispatchQueue.main.async { handler(id) }
        }
        return true
    }
}
