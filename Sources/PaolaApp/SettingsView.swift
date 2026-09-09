import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var storage: StorageCoordinator
    @AppStorage("privacy.appLockEnabled") private var appLockEnabled = false
    @AppStorage("reminders.enabled") private var remindersEnabled = false
    @AppStorage("reminders.minutesBefore") private var minutesBefore = 15
    @State private var notificationError: String?
    @State private var creatingBlock = false

    var body: some View {
        Form {
            Section("Gestione") {
                NavigationLink { ServicesView() } label: { Label("Servizi e listino", systemImage: "list.bullet.rectangle") }
                NavigationLink { PackagesView() } label: { Label("Pacchetti", systemImage: "rectangle.stack") }
                NavigationLink { ReportsView() } label: { Label("Statistiche ed estratti", systemImage: "chart.bar") }
                Button("Pausa o ferie", systemImage: "calendar.badge.minus") { creatingBlock = true }
            }
            Section("Archivio") {
                LocalStorageNotice()
                if let lastSync = storage.lastSync {
                    LabeledContent("Ultimo trasferimento") {
                        Text(lastSync, format: .dateTime.day().month().hour().minute())
                    }
                }
                Text(storage.cloudEnabled
                     ? "Sincronizzazione asincrona nel database iCloud privato. Nessuna promessa di aggiornamento istantaneo. Un cambio account chiude la scheda aperta per proteggere l'archivio."
                     : "Questa build salva solo sul dispositivo. Per iCloud servono container, capability e firma Apple, come descritto nel documento di progetto. Il semplice accesso allo stesso account non attiva la sincronizzazione.")
                    .font(.caption).foregroundStyle(.secondary)
                NavigationLink { BackupView() } label: { Label("Backup e ripristino", systemImage: "externaldrive") }
            }
            Section {
                Toggle("Blocca l'app con autenticazione di sistema", isOn: $appLockEnabled)
                Text("Quando attivo, richiede Touch ID, Face ID o la credenziale del dispositivo all'apertura e dopo il passaggio in background. Non viene creata una password dell'app.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text("Privacy") }
            Section {
                Toggle("Promemoria appuntamenti", isOn: Binding(
                    get: { remindersEnabled },
                    set: { enabled in
                        if enabled {
                            Task {
                                do {
                                    try await ReminderManager.authorize()
                                    remindersEnabled = true
                                } catch { notificationError = error.localizedDescription }
                            }
                        } else { remindersEnabled = false }
                    }
                ))
                Picker("Anticipo", selection: $minutesBefore) {
                    ForEach([0, 5, 15, 30, 60], id: \.self) { minutes in
                        Text(minutes == 0 ? "All'inizio" : "\(minutes) minuti").tag(minutes)
                    }
                }
                .disabled(!remindersEnabled)
                Text("Notifiche senza nomi o dati personali. Sono programmati fino a 60 promemoria futuri per dispositivo; riapri l'app per aggiornare la coda.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text("Notifiche") }
            Section("Applicazione") {
                LabeledContent("Versione", value: "0.6.0")
                LabeledContent("Utilizzo", value: "Un personal trainer, clienti fitness")
                Text("Nessuna telemetria. Documenti non fiscali. Anamnesi e analisi fisica sono campi riservati: registra solo i dati necessari e legittimamente trattabili. Usa il blocco dell'app e conserva backup cifrati.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Impostazioni")
        .sheet(isPresented: $creatingBlock) { BlockEditor() }
        .alert("Notifiche", isPresented: Binding(get: { notificationError != nil }, set: { if !$0 { notificationError = nil } })) {
            Button("OK", role: .cancel) { notificationError = nil }
        } message: { Text(notificationError ?? "") }
    }
}
