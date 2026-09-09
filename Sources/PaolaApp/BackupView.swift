import PaolaCore
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

private struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.data] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw ArchiveError.invalidArchive }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct BackupView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var storage: StorageCoordinator
    @AppStorage("backup.lastSuccess") private var lastBackup = 0.0
    @State private var password = ""
    @State private var confirmation = ""
    @State private var exportDocument: BackupDocument?
    @State private var exporting = false
    @State private var importing = false
    @State private var pendingSnapshot: ArchiveSnapshot?
    @State private var confirmingRestore = false
    @State private var busy = false
    @State private var message: String?
    @AppStorage("backup.lastSafetyPath") private var safetyBackupPath = ""

    var body: some View {
        Form {
            Section {
                SecureField("Password del backup (almeno 12 caratteri)", text: $password)
                    .textContentType(.newPassword)
                SecureField("Ripeti password per creare un backup", text: $confirmation)
                Text("Conserva la password in un luogo sicuro: non viene memorizzata e non puo' essere recuperata. Il backup e' cifrato e comprende l'intero archivio, non solo gli estratti.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: { Text("Backup cifrato") }

            Section {
                Button("Crea backup completo", action: createBackup)
                    .disabled(busy)
                if lastBackup > 0 {
                    LabeledContent("Ultimo backup esportato") {
                        Text(Date(timeIntervalSince1970: lastBackup), format: .dateTime.day().month().year().hour().minute())
                    }
                }
                Button("Apri backup da ripristinare") { importing = true }
                    .disabled(busy || storage.cloudEnabled)
                if busy { ProgressView("Elaborazione in corso...") }
            } footer: {
                Text("Il ripristino crea un nuovo archivio locale e conserva quello precedente. Prima del cambio viene creata anche una copia cifrata di sicurezza. Con iCloud attivo il ripristino sostitutivo e' bloccato.")
            }
            if !safetyBackupPath.isEmpty {
                Section("Copia di sicurezza precedente al ripristino") {
                    Text(safetyBackupPath).textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Backup e ripristino")
        .fileExporter(isPresented: $exporting, document: exportDocument,
                      contentType: .data, defaultFilename: "Paola-backup-\(Date().formatted(.iso8601.year().month().day())).paolabackup") { result in
            switch result {
            case .success:
                lastBackup = Date().timeIntervalSince1970
                password = ""
                confirmation = ""
            case .failure(let error):
                message = error.localizedDescription
            }
            exportDocument = nil
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.data]) { result in
            switch result {
            case .success(let url): readBackup(url)
            case .failure(let error): message = error.localizedDescription
            }
        }
        .confirmationDialog("Ripristinare questo archivio?", isPresented: $confirmingRestore, titleVisibility: .visible) {
            Button("Crea copia di sicurezza e ripristina", role: .destructive) { restoreBackup() }
            Button("Annulla", role: .cancel) { pendingSnapshot = nil }
        } message: {
            if let pendingSnapshot {
                Text("Backup del \(pendingSnapshot.createdAt.formatted(date: .abbreviated, time: .shortened)): \(pendingSnapshot.clients.count) clienti, \(pendingSnapshot.recordCount) record totali. L'archivio precedente viene conservato.")
            }
        }
        .alert("Backup", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) { message = nil }
        } message: { Text(message ?? "") }
    }

    private func createBackup() {
        guard password == confirmation else {
            message = "Le password non coincidono."
            return
        }
        do {
            let payload = try ArchiveSnapshot.capture(context: context).encoded()
            let secret = password
            busy = true
            Task {
                do {
                    let encrypted = try await Task.detached {
                        try BackupCipher.encrypt(payload, password: secret)
                    }.value
                    exportDocument = BackupDocument(data: encrypted)
                    exporting = true
                } catch { message = error.localizedDescription }
                busy = false
            }
        } catch { message = error.localizedDescription }
    }

    private func readBackup(_ url: URL) {
        let granted = url.startAccessingSecurityScopedResource()
        defer { if granted { url.stopAccessingSecurityScopedResource() } }
        do {
            guard let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                  size <= 150_000_000 else { throw ArchiveError.invalidArchive }
            let data = try Data(contentsOf: url)
            let secret = password
            busy = true
            Task {
                do {
                    let payload = try await Task.detached {
                        try BackupCipher.decrypt(data, password: secret)
                    }.value
                    pendingSnapshot = try ArchiveSnapshot.decode(payload)
                    confirmingRestore = true
                } catch { message = error.localizedDescription }
                busy = false
            }
        } catch { message = error.localizedDescription }
    }

    private func restoreBackup() {
        guard let snapshot = pendingSnapshot else {
            message = "Seleziona prima un backup valido."
            return
        }
        do {
            guard !storage.cloudEnabled else { throw StorageError.restoreWhileCloudEnabled }
            let previous = try ArchiveSnapshot.capture(context: context).encoded()
            let secret = password
            busy = true
            storage.maintenanceMessage = "Copia di sicurezza e ripristino dell'archivio..."
            Task {
                defer { storage.maintenanceMessage = nil }
                do {
                    let encrypted = try await Task.detached {
                        try BackupCipher.encrypt(previous, password: secret)
                    }.value
                    let base = try StoreFactory.applicationDirectory()
                    let safety = base.appendingPathComponent("Backups", isDirectory: true)
                    try FileManager.default.createDirectory(at: safety, withIntermediateDirectories: true)
                    let safetyURL = safety.appendingPathComponent("prima-ripristino-\(UUID().uuidString).paolabackup")
                    try encrypted.write(to: safetyURL, options: [.atomic])
                    let destination = base.appendingPathComponent("Restored/\(UUID().uuidString)/Clienti-v1.store")
                    try snapshot.restore(toNewStoreAt: destination)
                    safetyBackupPath = safetyURL.path
                    try storage.installRestoredStore(at: destination)
                    password = ""
                    confirmation = ""
                    pendingSnapshot = nil
                } catch { message = error.localizedDescription }
                busy = false
            }
        } catch { message = error.localizedDescription }
    }
}
