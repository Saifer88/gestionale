import Foundation
import PaolaCore
import XCTest

final class SchedulingSuggestionsTests: XCTestCase {
    private var calendar: Calendar {
        var value = SchedulingSuggestions.calendar
        value.timeZone = TimeZone(identifier: "Europe/Rome")!
        return value
    }

    private func date(_ year: Int = 2026, _ month: Int = 9, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    func testRemainingWeekAndAllOfNextWeekUseItalianLabels() throws {
        let days = try SchedulingSuggestions.suggestedDays(from: date(2026, 9, 9, 13, 37), calendar: calendar)
        XCTAssertEqual(days.count, 8)
        XCTAssertEqual(days.first, date(2026, 9, 9))
        XCTAssertEqual(days.last, date(2026, 9, 18))
        XCTAssertEqual(SchedulingSuggestions.dayLabel(days[0], calendar: calendar), "Mercoledì 9")
        XCTAssertEqual(SchedulingSuggestions.dayLabel(days[1], calendar: calendar), "Giovedì 10")
        XCTAssertEqual(Set(days).count, 8)
        XCTAssertTrue(days.allSatisfy { !calendar.isDateInWeekend($0) })
        let week = try SchedulingSuggestions.weekDays(containing: days[0], calendar: calendar)
        XCTAssertEqual(week.first, date(2026, 9, 7))
        XCTAssertEqual(week.last, date(2026, 9, 13))
    }

    func testSundayMondayAndYearBoundary() throws {
        XCTAssertEqual(try SchedulingSuggestions.suggestedDays(from: date(2026, 9, 13), calendar: calendar).count, 5)
        XCTAssertEqual(try SchedulingSuggestions.suggestedDays(from: date(2026, 9, 14), calendar: calendar).count, 10)
        let days = try SchedulingSuggestions.suggestedDays(from: date(2026, 12, 31), calendar: calendar)
        XCTAssertEqual(days.first, date(2026, 12, 31))
        XCTAssertEqual(days.last, date(2027, 1, 8))
    }

    func testFullDurationExcludesOccupiedSlotsAndIncludesAdjacentOnes() throws {
        let day = date(2026, 9, 10)
        let session = TrainingSession(startDate: date(2026, 9, 10, 10, 30), durationMinutes: 90)
        let block = Unavailability(startDate: date(2026, 9, 10, 14), endDate: date(2026, 9, 10, 15, 30), title: "Pausa")
        let hours = try SchedulingSuggestions.availableHours(
            on: day, durationMinutes: 90, sessions: [session], blocks: [block], now: day, calendar: calendar
        )
        let values = hours.map { calendar.component(.hour, from: $0) }
        XCTAssertFalse(values.contains(10))
        XCTAssertFalse(values.contains(11))
        XCTAssertFalse(values.contains(13))
        XCTAssertFalse(values.contains(14))
        XCTAssertFalse(values.contains(15))
        XCTAssertTrue(values.contains(9)) // Ends exactly when the existing session starts.
        XCTAssertFalse(values.contains(12))
        XCTAssertTrue(values.contains(16))
        XCTAssertTrue(hours.allSatisfy {
            calendar.component(.minute, from: $0) == 0 && calendar.component(.second, from: $0) == 0
        })
    }

    func testTodayOmitsPastHoursAndCancelledAppointmentsDoNotOccupySlots() throws {
        let now = date(2026, 9, 9, 13, 37)
        let cancelled = TrainingSession(startDate: date(2026, 9, 9, 14), status: .cancelled)
        let absent = TrainingSession(startDate: date(2026, 9, 9, 15), status: .noShow)
        let completed = TrainingSession(startDate: date(2026, 9, 9, 16), status: .completed)
        let hours = try SchedulingSuggestions.availableHours(
            on: now, durationMinutes: 60, sessions: [cancelled, absent, completed], blocks: [],
            now: now, calendar: calendar
        ).map { calendar.component(.hour, from: $0) }
        XCTAssertEqual(hours.first, 14)
        XCTAssertTrue(hours.contains(15))
        XCTAssertFalse(hours.contains(16))
        XCTAssertFalse(hours.contains(13))
    }

    func testNextDayOccupationAndExcludedEditedSession() throws {
        let day = date(2026, 9, 10)
        let session = TrainingSession(startDate: date(2026, 9, 11), durationMinutes: 60)
        let blocked = try SchedulingSuggestions.availableHours(
            on: day, durationMinutes: 300, sessions: [session], blocks: [], now: day, calendar: calendar
        )
        XCTAssertFalse(blocked.contains(date(2026, 9, 10, 20)))
        let available = try SchedulingSuggestions.availableHours(
            on: day, durationMinutes: 300, sessions: [session], blocks: [],
            excludingSessionID: session.id, now: day, calendar: calendar
        )
        XCTAssertTrue(available.contains(date(2026, 9, 10, 20)))
    }

    func testFullDayBlockedAndDurationChange() throws {
        let day = date(2026, 9, 10)
        let block = Unavailability(startDate: day, endDate: date(2026, 9, 11), title: "Ferie")
        XCTAssertTrue(try SchedulingSuggestions.availableHours(
            on: day, durationMinutes: 60, sessions: [], blocks: [block], now: day, calendar: calendar
        ).isEmpty)
        let busy = TrainingSession(startDate: date(2026, 9, 10, 10))
        let oneHour = try SchedulingSuggestions.availableHours(
            on: day, durationMinutes: 60, sessions: [busy], blocks: [], now: day, calendar: calendar
        )
        let twoHours = try SchedulingSuggestions.availableHours(
            on: day, durationMinutes: 120, sessions: [busy], blocks: [], now: day, calendar: calendar
        )
        XCTAssertTrue(oneHour.contains(date(2026, 9, 10, 9)))
        XCTAssertFalse(twoHours.contains(date(2026, 9, 10, 9)))
    }

    func testDSTSpringSkipsNonexistentHourAndAutumnHasNoDuplicateLabels() throws {
        for day in [date(2026, 3, 29), date(2026, 10, 25)] {
            let slots = try SchedulingSuggestions.availableHours(
                on: day, durationMinutes: 60, sessions: [], blocks: [], now: day, calendar: calendar
            )
            XCTAssertEqual(slots.count, 12)
            let labels = slots.map { SchedulingSuggestions.hourLabel($0, calendar: calendar) }
            XCTAssertEqual(Set(labels).count, labels.count)
            XCTAssertTrue(labels.allSatisfy { $0.hasSuffix(":00") })
        }
    }

    func testInvalidInputIsReported() {
        XCTAssertThrowsError(try SchedulingSuggestions.availableHours(on: Date(), durationMinutes: 0, sessions: [], blocks: []))
        XCTAssertThrowsError(try SchedulingSuggestions.suggestedDays(from: Date(timeIntervalSince1970: .nan)))
    }

    func testOnlyRequestedHoursAppearAndBusyDayRefreshesAvailability() throws {
        let day = date(2026, 9, 10)
        let free = try SchedulingSuggestions.availableHours(
            on: day, durationMinutes: 60, sessions: [], blocks: [], now: day, calendar: calendar
        )
        XCTAssertEqual(free.map { calendar.component(.hour, from: $0) },
                       [7, 8, 9, 10, 13, 14, 15, 16, 17, 18, 19, 20])
        let session = TrainingSession(startDate: date(2026, 9, 10, 13, 30), durationMinutes: 90)
        let occupied = try SchedulingSuggestions.availableHours(
            on: day, durationMinutes: 60, sessions: [session], blocks: [], now: day, calendar: calendar
        )
        XCTAssertFalse(occupied.contains(date(2026, 9, 10, 13)))
        XCTAssertFalse(occupied.contains(date(2026, 9, 10, 14)))
        XCTAssertTrue(occupied.contains(date(2026, 9, 10, 15)))
        let nextDay = date(2026, 9, 11)
        XCTAssertEqual(try SchedulingSuggestions.availableHours(
            on: nextDay, durationMinutes: 60, sessions: [session], blocks: [], now: day, calendar: calendar
        ).count, 12)
    }
}
