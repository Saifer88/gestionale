import Foundation
import SwiftData

@Model public final class ClientAppointmentPreference {
    public var id: UUID = UUID()
    public var clientID: UUID = UUID()
    public var serviceID: UUID?
    public var preferredHour: Int = 7
    public var preferredMinute: Int = 0
    public var rateID: UUID?
    public var priceCents: Int64 = 0
    public var packageID: UUID?
    public var durationMinutes: Int = 60
    public var updatedAt: Date = Date()

    public init(id: UUID = UUID(), clientID: UUID = UUID(), serviceID: UUID? = nil,
                preferredHour: Int = 7, preferredMinute: Int = 0, rateID: UUID? = nil,
                priceCents: Int64 = 0, packageID: UUID? = nil, durationMinutes: Int = 60,
                updatedAt: Date = Date()) {
        self.id = id; self.clientID = clientID; self.serviceID = serviceID
        self.preferredHour = preferredHour; self.preferredMinute = preferredMinute
        self.rateID = rateID; self.priceCents = priceCents; self.packageID = packageID
        self.durationMinutes = durationMinutes; self.updatedAt = updatedAt
    }
}

public struct AppointmentDefaults: Equatable {
    public let serviceID: UUID?
    public let hour: Int
    public let minute: Int
    public let rateID: UUID?
    public let priceCents: Int64
    public let packageID: UUID?
    public let durationMinutes: Int

    public init(serviceID: UUID?, hour: Int, minute: Int, rateID: UUID?,
                priceCents: Int64, packageID: UUID?, durationMinutes: Int) {
        self.serviceID = serviceID; self.hour = hour; self.minute = minute
        self.rateID = rateID; self.priceCents = priceCents; self.packageID = packageID
        self.durationMinutes = durationMinutes
    }
}

public enum AppointmentPreferences {
    public static func lastUsed(clientID: UUID, sessions: [TrainingSession],
                                participants: [SessionParticipant],
                                preferences: [ClientAppointmentPreference]) -> AppointmentDefaults? {
        if let preference = preferences.filter({ $0.clientID == clientID }).sorted(by: {
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.id.uuidString < $1.id.uuidString
        }).first {
            return AppointmentDefaults(serviceID: preference.serviceID, hour: preference.preferredHour,
                minute: preference.preferredMinute, rateID: preference.rateID,
                priceCents: preference.priceCents, packageID: preference.packageID,
                durationMinutes: preference.durationMinutes)
        }
        let clientParticipants = participants.filter { $0.clientID == clientID }
        let sessionIDs = Set(clientParticipants.map(\.sessionID))
        guard let session = sessions.filter({
            sessionIDs.contains($0.id) && ($0.status == .planned || $0.status == .completed)
        }).sorted(by: {
            if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.id.uuidString < $1.id.uuidString
        }).first,
        let participant = clientParticipants.filter({ $0.sessionID == session.id })
            .sorted(by: { $0.id.uuidString < $1.id.uuidString }).first else { return nil }
        let calendar = SchedulingSuggestions.calendar
        return AppointmentDefaults(serviceID: session.serviceID,
            hour: calendar.component(.hour, from: session.startDate),
            minute: calendar.component(.minute, from: session.startDate), rateID: nil,
            priceCents: participant.priceCents, packageID: participant.packageID,
            durationMinutes: session.durationMinutes)
    }
}
