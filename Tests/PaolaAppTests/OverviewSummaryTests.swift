import Foundation
import PaolaCore
@testable import PaolaApp
import XCTest

final class OverviewSummaryTests: XCTestCase {
    private var calendar: Calendar {
        var value = SchedulingSuggestions.calendar
        value.timeZone = TimeZone(identifier: "Europe/Rome")!
        return value
    }

    private func date(_ day: Int, _ hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour))!
    }

    func testForecastOnlyFuturePlannedSessionsAndNoSecondIncomeFromPackages() throws {
        let now = date(9, 12)
        let future = TrainingSession(startDate: date(9, 14))
        let nextWeek = TrainingSession(startDate: date(14, 10))
        let past = TrainingSession(startDate: date(9, 8))
        let exactNow = TrainingSession(startDate: now)
        let cancelled = TrainingSession(startDate: date(10, 10), status: .cancelled)
        let completed = TrainingSession(startDate: date(10, 11), status: .completed)
        let noShow = TrainingSession(startDate: date(10, 12), status: .noShow)
        let sessions = [future, nextWeek, past, exactNow, cancelled, completed, noShow]
        var people = sessions.map { SessionParticipant(sessionID: $0.id, clientID: UUID(), priceCents: 5000) }
        people.append(SessionParticipant(sessionID: future.id, clientID: UUID(), priceCents: 4000, packageID: UUID()))
        let summary = try OverviewSummary(entries: [], sessions: sessions, participants: people, now: now, calendar: calendar)
        XCTAssertEqual(summary.forecastCents, 10000)
        XCTAssertEqual(summary.plannedSessionsThisWeek, 3)
        XCTAssertEqual(summary.bookedClientsThisWeek, 4)
    }

    func testWeekCountsUniqueCustomersAndOneLessonForMultipleParticipants() throws {
        let clientA = UUID()
        let clientB = UUID()
        let sessionA = TrainingSession(startDate: date(7, 10))
        let sessionB = TrainingSession(startDate: date(11, 10))
        let outside = TrainingSession(startDate: date(14, 10))
        let completed = TrainingSession(startDate: date(8, 10), status: .completed)
        let cancelled = TrainingSession(startDate: date(9, 10), status: .cancelled)
        let participants = [
            SessionParticipant(sessionID: sessionA.id, clientID: clientA, priceCents: 5000),
            SessionParticipant(sessionID: sessionB.id, clientID: clientA, priceCents: 5000),
            SessionParticipant(sessionID: sessionB.id, clientID: clientB, priceCents: 3500),
            SessionParticipant(sessionID: outside.id, clientID: UUID(), priceCents: 5000),
            SessionParticipant(sessionID: completed.id, clientID: UUID(), priceCents: 5000),
            SessionParticipant(sessionID: cancelled.id, clientID: UUID(), priceCents: 5000)
        ]
        let summary = try OverviewSummary(
            entries: [], sessions: [sessionA, sessionA, sessionB, outside, completed, cancelled],
            participants: participants, now: date(9, 12), calendar: calendar
        )
        XCTAssertEqual(summary.plannedSessionsThisWeek, 2)
        XCTAssertEqual(summary.bookedClientsThisWeek, 2)
        XCTAssertEqual(summary.forecastCents, 13500)
    }

    func testCancelledAppointmentsNeverAppearInAnyCalendarIntervalButRemainInHistory() throws {
        let cancelled = TrainingSession(startDate: date(9, 10), status: .cancelled)
        let completed = TrainingSession(startDate: date(9, 11), status: .completed)
        let planned = TrainingSession(startDate: date(9, 14))
        let all = [cancelled, completed, planned]
        for component: Calendar.Component in [.day, .weekOfYear, .month] {
            let interval = try XCTUnwrap(calendar.dateInterval(of: component, for: date(9)))
            XCTAssertEqual(CalendarAppointments.visible(all, in: interval).map(\.id), [completed.id, planned.id])
        }
        XCTAssertEqual(cancelled.status, .cancelled)
        XCTAssertEqual(all.count, 3)
    }

    func testTodayIncludesPastCompletedAndOvernightAppointmentsWithoutCancelled() throws {
        let overnight = TrainingSession(startDate: date(8, 23), durationMinutes: 120)
        let endedAtMidnight = TrainingSession(startDate: date(8, 23), durationMinutes: 60)
        let completed = TrainingSession(startDate: date(9, 9), status: .completed)
        let afternoon = TrainingSession(startDate: date(9, 15))
        let cancelled = TrainingSession(startDate: date(9, 10), status: .cancelled)
        let tomorrow = TrainingSession(startDate: date(10))
        let summary = try OverviewSummary(entries: [],
            sessions: [tomorrow, cancelled, completed, endedAtMidnight, afternoon, overnight],
            participants: [], now: date(9, 12), calendar: calendar)
        XCTAssertEqual(summary.today.map(\.id), [overnight.id, completed.id, afternoon.id])
    }

    func testDeduplicatesSameBookingAndSurfacesConflictingOrOverflowingForecasts() throws {
        let session = TrainingSession(startDate: date(10, 10))
        let person = SessionParticipant(sessionID: session.id, priceCents: 5000)
        let summary = try OverviewSummary(entries: [], sessions: [session, session],
            participants: [person, person], now: date(9), calendar: calendar)
        XCTAssertEqual(summary.forecastCents, 5000)
        let duplicate = SessionParticipant(sessionID: session.id, clientID: person.clientID, priceCents: 6000)
        XCTAssertThrowsError(try OverviewSummary(entries: [], sessions: [session],
            participants: [person, duplicate], now: date(9), calendar: calendar))
        let large = SessionParticipant(sessionID: session.id, priceCents: .max)
        XCTAssertThrowsError(try OverviewSummary(entries: [], sessions: [session],
            participants: [person, large], now: date(9), calendar: calendar))
    }
}
