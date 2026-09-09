import PaolaCore
import SwiftData
import SwiftUI
import UserNotifications

enum ReminderError: LocalizedError {
    case denied
    var errorDescription: String? { "Le notifiche non sono autorizzate. Puoi abilitarle nelle impostazioni del dispositivo." }
}

enum ReminderManager {
    static func authorize() async throws {
        guard try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) else {
            throw ReminderError.denied
        }
    }

    static func replace(with reminders: [(id: String, date: Date)]) async throws {
        let center = UNUserNotificationCenter.current()
        let existing = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: existing.map(\.identifier).filter { $0.hasPrefix("paola.session.") })
        if reminders.isEmpty { return }
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            throw ReminderError.denied
        }
        for reminder in reminders {
            try Task.checkCancellation()
            let content = UNMutableNotificationContent()
            content.title = "Appuntamento in agenda"
            content.body = "Apri Paola Gestionale per consultare i dettagli."
            content.sound = .default
            let interval = reminder.date.timeIntervalSinceNow
            if interval <= 0 { continue }
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(interval, 1), repeats: false)
            try await center.add(UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger))
        }
    }
}

struct ReminderSchedulerView: View {
    @Query(sort: \TrainingSession.startDate) private var sessions: [TrainingSession]
    @AppStorage("reminders.enabled") private var enabled = false
    @AppStorage("reminders.minutesBefore") private var minutesBefore = 15
    @State private var errorMessage: String?
    @Environment(\.scenePhase) private var scenePhase

    private var signature: String {
        "\(enabled)-\(minutesBefore)-\(scenePhase == .active)-" +
        sessions.map { "\($0.id)-\($0.startDate.timeIntervalSince1970)-\($0.statusRaw)" }.joined(separator: "|")
    }

    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .task(id: signature) {
                guard scenePhase == .active else { return }
                do {
                    if let error = _sessions.fetchError { throw error }
                    let reminders = enabled ? sessions.filter {
                        $0.status == .planned && $0.startDate.addingTimeInterval(-Double(minutesBefore * 60)) > Date()
                    }.prefix(60).map {
                        (id: "paola.session.\($0.id.uuidString)", date: $0.startDate.addingTimeInterval(-Double(minutesBefore * 60)))
                    } : []
                    try await ReminderManager.replace(with: reminders)
                } catch is CancellationError {
                    return
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
            .alert("Promemoria non aggiornati", isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
    }
}
