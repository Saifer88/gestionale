import Foundation
import PaolaCore

/// Un'occorrenza (virtuale) di un corso in una data specifica: non è materializzata
/// nell'archivio, viene calcolata a runtime dalla ricorrenza settimanale del corso.
struct CourseOccurrence: Identifiable {
    let course: Course
    let start: Date
    let end: Date
    /// Nomi dei partecipanti il cui pacchetto a tempo è ancora valido a questa data.
    let participantNames: [String]
    /// Identificatore stabile: corso + data di inizio.
    var id: String { "\(course.id.uuidString):\(start.timeIntervalSinceReferenceDate)" }
}

enum CourseOccurrences {
    /// Orizzonte di ricorrenza: da oggi a +6 mesi.
    static func horizon(now: Date = Date(), calendar: Calendar = SchedulingSuggestions.calendar) -> DateInterval {
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .month, value: 6, to: start) ?? start
        return DateInterval(start: start, end: end)
    }

    /// Espande i corsi in occorrenze che intersecano `interval`, entro l'orizzonte di 6
    /// mesi da oggi. Per ogni occorrenza include solo i partecipanti il cui pacchetto a
    /// tempo è ancora valido alla data dell'occorrenza (o senza pacchetto associato).
    static func expand(courses: [Course], participants: [CourseParticipant],
                       packages: [LessonPackage], in interval: DateInterval,
                       now: Date = Date(), calendar: Calendar = SchedulingSuggestions.calendar) -> [CourseOccurrence] {
        let horizon = horizon(now: now, calendar: calendar)
        // Limita alla sovrapposizione tra l'intervallo richiesto e l'orizzonte.
        let from = max(interval.start, horizon.start)
        let to = min(interval.end, horizon.end)
        guard from < to else { return [] }

        let packagesByID = Dictionary(packages.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var result: [CourseOccurrence] = []

        for course in courses where course.weekdaysMask != 0 {
            let people = participants.filter { $0.courseID == course.id }
            // Itera giorno per giorno nell'intervallo; per i giorni che combaciano con
            // i weekday del corso genera l'occorrenza all'orario indicato.
            var day = calendar.startOfDay(for: from)
            while day < to {
                let weekday = calendar.component(.weekday, from: day)
                if course.weekdays.contains(weekday),
                   let start = calendar.date(bySettingHour: course.startHour, minute: course.startMinute,
                                             second: 0, of: day) {
                    let end = start.addingTimeInterval(Double(course.durationMinutes) * 60)
                    if start < to && end > from {
                        let names = people.compactMap { person -> String? in
                            // Visibile solo se il pacchetto a tempo è valido a questa data.
                            if let packageID = person.packageID, let package = packagesByID[packageID] {
                                if let expiry = package.expiresOn,
                                   calendar.startOfDay(for: start) > calendar.startOfDay(for: expiry) {
                                    return nil
                                }
                            }
                            return person.clientName
                        }
                        result.append(CourseOccurrence(course: course, start: start, end: end,
                                                       participantNames: names))
                    }
                }
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
        }
        return result.sorted { $0.start < $1.start }
    }

    /// Occorrenze che intersecano una fascia oraria [start, end).
    static func occurrences(_ occurrences: [CourseOccurrence], overlapping start: Date, end: Date) -> [CourseOccurrence] {
        occurrences.filter { $0.start < end && $0.end > start }
    }
}
