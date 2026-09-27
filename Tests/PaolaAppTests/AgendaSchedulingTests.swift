import Foundation
import PaolaCore
@testable import PaolaApp
import XCTest

final class AgendaSchedulingTests: XCTestCase {
    func testHourRowsGroupStartsAndKeepOvernightAppointmentsAsBusy() throws {
        var calendar = SchedulingSuggestions.calendar
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Rome"))
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 9)))
        func time(_ hour: Int, _ minute: Int = 0) -> Date {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
        }

        let dragged = TrainingSession(startDate: time(7))
        let second = TrainingSession(startDate: time(7, 30))
        let overnight = TrainingSession(startDate: time(6, 30), durationMinutes: 120)
        let cancelled = TrainingSession(startDate: time(7, 15), status: .cancelled)
        let rows = AgendaScheduling.hourRows(
            on: day, draggedSessionID: dragged.id, draggedDurationMinutes: 60,
            sessions: [second, overnight, cancelled, dragged], blocks: [], calendar: calendar
        )

        let seven = try XCTUnwrap(rows.first { $0.hour == 7 })
        XCTAssertEqual(seven.sessions.map(\.id), [dragged.id, second.id])
        XCTAssertEqual(seven.occupantID, second.id)
        XCTAssertFalse(seven.isFree)

        let eight = try XCTUnwrap(rows.first { $0.hour == 8 })
        XCTAssertTrue(eight.sessions.isEmpty)
        XCTAssertFalse(eight.isFree)
    }
}