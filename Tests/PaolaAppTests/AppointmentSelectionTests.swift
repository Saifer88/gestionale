import Foundation
import PaolaCore
@testable import PaolaApp
import XCTest

final class AppointmentSelectionTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = SchedulingSuggestions.calendar
        calendar.timeZone = TimeZone(identifier: "Europe/Rome")!
        return calendar
    }

    private func date(_ day: Int = 9, _ hour: Int = 7, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }

    func testReusesExactClientServiceTimeRateAndPackage() throws {
        let clientID = UUID()
        let service = TrainingService(name: "Allenamento", priceCents: 5000)
        let first = ServiceRate(serviceID: service.id, name: "Standard", priceCents: 5000)
        let chosen = ServiceRate(serviceID: service.id, name: "Abituale", priceCents: 5000, sortOrder: 1)
        let package = LessonPackage(clientID: clientID, purchasedOn: date(8), priceCents: 40000)
        let preference = ClientAppointmentPreference(clientID: clientID, serviceID: service.id,
            preferredHour: 14, preferredMinute: 0, rateID: chosen.id, priceCents: 5000,
            packageID: package.id, durationMinutes: 90)
        let value = try AppointmentSelection.propose(
            clientID: clientID, now: date(), services: [service], rates: [first, chosen],
            sessions: [], participants: [], blocks: [], packages: [package], uses: [],
            preferences: [preference], calendar: calendar
        )
        XCTAssertEqual(value.serviceID, service.id)
        XCTAssertEqual(value.rateID, chosen.id)
        XCTAssertEqual(value.packageID, package.id)
        XCTAssertEqual(value.priceCents, 5000)
        XCTAssertEqual(value.durationMinutes, 90)
        XCTAssertEqual(value.startDate, date(9, 14))
        XCTAssertTrue(value.notices.isEmpty)
    }

    func testOtherClientsDoNotInheritSelectionsAndNoPackageIsSelectedWithoutHistory() throws {
        let otherClient = UUID()
        let service = TrainingService(name: "Allenamento", priceCents: 4500)
        let package = LessonPackage(clientID: otherClient, purchasedOn: date(8), priceCents: 40000)
        let previous = ClientAppointmentPreference(clientID: otherClient, serviceID: service.id,
            preferredHour: 19, priceCents: 3500, packageID: package.id)
        let value = try AppointmentSelection.propose(
            clientID: UUID(), now: date(), services: [service], rates: [], sessions: [],
            participants: [], blocks: [], packages: [package], uses: [], preferences: [previous], calendar: calendar
        )
        XCTAssertEqual(value.startDate, date())
        XCTAssertEqual(value.priceCents, 4500)
        XCTAssertNil(value.packageID)
        XCTAssertEqual(value.rateID, service.id)
    }

    func testBusyPreferredTimeMovesToFirstFreeWeekdayIncludingBlockAndWholeDuration() throws {
        let client = UUID()
        let service = TrainingService(name: "Allenamento", priceCents: 4500)
        let previous = ClientAppointmentPreference(clientID: client, serviceID: service.id,
            preferredHour: 14, priceCents: 4500, durationMinutes: 90)
        let busy = TrainingSession(startDate: date(9, 15), durationMinutes: 60)
        let block = Unavailability(startDate: date(10, 13), endDate: date(10, 16), title: "Pausa")
        let value = try AppointmentSelection.propose(
            clientID: client, now: date(), services: [service], rates: [], sessions: [busy],
            participants: [], blocks: [block], packages: [], uses: [], preferences: [previous], calendar: calendar
        )
        XCTAssertEqual(value.startDate, date(11, 14))
    }

    func testUnavailablePackageIsNotSelectedAndDeletedTariffKeepsAgreedPrice() throws {
        let clientID = UUID()
        let service = TrainingService(name: "Allenamento", priceCents: 5000)
        let package = LessonPackage(clientID: clientID, purchasedOn: date(1), priceCents: 40000,
                                    expiresOn: date(8))
        let previous = ClientAppointmentPreference(clientID: clientID, serviceID: service.id,
            preferredHour: 9, rateID: UUID(), priceCents: 3500, packageID: package.id)
        let value = try AppointmentSelection.propose(
            clientID: clientID, now: date(), services: [service], rates: [], sessions: [],
            participants: [], blocks: [], packages: [package], uses: [], preferences: [previous], calendar: calendar
        )
        XCTAssertNil(value.packageID)
        XCTAssertNil(value.rateID)
        XCTAssertEqual(value.priceCents, 3500)
        XCTAssertEqual(value.notices.count, 2)
    }

    func testChangedTariffPriceAndInactiveServiceAreReported() throws {
        let clientID = UUID()
        let service = TrainingService(name: "Allenamento", priceCents: 5000)
        let rate = ServiceRate(serviceID: service.id, priceCents: 6000)
        let previous = ClientAppointmentPreference(clientID: clientID, serviceID: service.id,
            preferredHour: 9, rateID: rate.id, priceCents: 5000)
        let value = try AppointmentSelection.propose(
            clientID: clientID, now: date(), services: [service], rates: [rate], sessions: [],
            participants: [], blocks: [], packages: [], uses: [], preferences: [previous], calendar: calendar
        )
        XCTAssertEqual(value.priceCents, 6000)
        XCTAssertEqual(value.notices.count, 1)
        service.isActive = false
        let fallback = TrainingService(name: "Altro", priceCents: 3000)
        let inactive = try AppointmentSelection.propose(
            clientID: clientID, now: date(), services: [service, fallback], rates: [rate], sessions: [],
            participants: [], blocks: [], packages: [], uses: [], preferences: [previous], calendar: calendar
        )
        XCTAssertEqual(inactive.serviceID, fallback.id)
        XCTAssertEqual(inactive.priceCents, 3000)
        XCTAssertEqual(inactive.notices.count, 1)
    }

    func testHistoricalManualTimeRemainsSelectableButNeverInQuickHours() throws {
        let client = UUID()
        let service = TrainingService(name: "Lezione", priceCents: 5000)
        let preference = ClientAppointmentPreference(clientID: client, serviceID: service.id,
            preferredHour: 11, preferredMinute: 30, priceCents: 5000)
        let selection = try AppointmentSelection.propose(
            clientID: client, now: date(), services: [service], rates: [], sessions: [], participants: [],
            blocks: [], packages: [], uses: [], preferences: [preference], calendar: calendar
        )
        XCTAssertEqual(selection.startDate, date(9, 11, 30))
        let quick = try SchedulingSuggestions.availableHours(
            on: selection.startDate, durationMinutes: 60, sessions: [], blocks: [], now: date(), calendar: calendar
        )
        XCTAssertFalse(quick.contains(selection.startDate))
    }

    func testConfiguredServiceAndRateOverrideHistoryWithoutLosingUsualTimeOrPackage() throws {
        let client = UUID()
        let preferred = TrainingService(name: "Preferito", durationMinutes: 45, priceCents: 5000)
        let preferredRate = ServiceRate(serviceID: preferred.id, name: "Ridotta", priceCents: 3500)
        let other = TrainingService(name: "Occasionale", priceCents: 7000)
        let package = LessonPackage(clientID: client, purchasedOn: date(8), priceCents: 40000)
        let previous = ClientAppointmentPreference(clientID: client, serviceID: other.id,
            preferredHour: 16, priceCents: 7000, packageID: package.id, durationMinutes: 90)
        let value = try AppointmentSelection.propose(
            clientID: client, now: date(), services: [other, preferred], rates: [preferredRate],
            sessions: [], participants: [], blocks: [], packages: [package], uses: [], preferences: [previous],
            preferredServiceID: preferred.id, preferredRateID: preferredRate.id, calendar: calendar
        )
        XCTAssertEqual(value.serviceID, preferred.id)
        XCTAssertEqual(value.rateID, preferredRate.id)
        XCTAssertEqual(value.priceCents, 3500)
        XCTAssertEqual(value.durationMinutes, 45)
        XCTAssertEqual(value.startDate, date(9, 16))
        XCTAssertEqual(value.packageID, package.id)
    }

    func testConfiguredPreferenceWorksBeforeFirstAppointmentAndUsesCurrentRatePrice() throws {
        let service = TrainingService(name: "Preferito", priceCents: 5000)
        let rate = ServiceRate(serviceID: service.id, name: "Ridotta", priceCents: 3500)
        let value = try AppointmentSelection.propose(
            clientID: UUID(), now: date(), services: [service], rates: [rate], sessions: [], participants: [],
            blocks: [], packages: [], uses: [], preferences: [],
            preferredServiceID: service.id, preferredRateID: rate.id, calendar: calendar
        )
        XCTAssertEqual(value.serviceID, service.id)
        XCTAssertEqual(value.rateID, rate.id)
        XCTAssertEqual(value.priceCents, 3500)
        XCTAssertNil(value.packageID)
    }

    func testUnavailableConfiguredPreferenceFallsBackWithNoticeAndCanBeRemoved() throws {
        let client = UUID()
        let inactive = TrainingService(name: "Vecchio", priceCents: 5000, isActive: false)
        let current = TrainingService(name: "Attivo", priceCents: 3500)
        let previous = ClientAppointmentPreference(clientID: client, serviceID: current.id,
            preferredHour: 14, priceCents: 3500)
        let value = try AppointmentSelection.propose(
            clientID: client, now: date(), services: [inactive, current], rates: [], sessions: [], participants: [],
            blocks: [], packages: [], uses: [], preferences: [previous],
            preferredServiceID: inactive.id, preferredRateID: UUID(), calendar: calendar
        )
        XCTAssertEqual(value.serviceID, current.id)
        XCTAssertEqual(value.priceCents, 3500)
        XCTAssertFalse(value.notices.isEmpty)
        let missingRate = try AppointmentSelection.propose(
            clientID: client, now: date(), services: [current], rates: [], sessions: [], participants: [],
            blocks: [], packages: [], uses: [], preferences: [previous],
            preferredServiceID: current.id, preferredRateID: UUID(), calendar: calendar
        )
        XCTAssertEqual(missingRate.priceCents, 3500)
        XCTAssertEqual(missingRate.rateID, current.id)
        XCTAssertFalse(missingRate.notices.isEmpty)
    }
}
