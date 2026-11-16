import PaolaCore
import SwiftData
import SwiftUI

struct ClientAvatar: View {
    let client: Client
    var size: CGFloat = 42

    private var initials: String {
        String(client.firstName.prefix(1) + client.lastName.prefix(1)).uppercased()
    }

    var body: some View {
        Text(initials)
            .font(size > 50 ? .title2.weight(.semibold) : .subheadline.weight(.semibold))
            .foregroundStyle(client.isArchived ? Color.secondary : .teal)
            .frame(width: size, height: size)
            .background(
                client.isArchived ? Color.secondary.opacity(0.12) : Color.teal.opacity(0.12),
                in: RoundedRectangle(cornerRadius: size * 0.3)
            )
            .accessibilityHidden(true)
    }
}

struct LocalStorageNotice: View {
    @EnvironmentObject private var storage: StorageCoordinator

    var body: some View {
        Label {
            Text(storage.status)
        } icon: {
            Image(systemName: storage.cloudEnabled ? "icloud" : "internaldrive")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct ArchiveReadErrorView: View {
    let error: Error

    var body: some View {
        ContentUnavailableView {
            Label("Lettura dell'archivio non riuscita", systemImage: "exclamationmark.triangle")
        } description: {
            Text(error.localizedDescription)
                .textSelection(.enabled)
            Text("Chiudi e riapri l'app per riprovare. Non cancellare l'archivio.")
        }
    }
}

struct FormError: Identifiable {
    let id = UUID()
    let message: String

    init(_ error: Error) {
        message = error.localizedDescription
    }
}

/// Avvisi di integrità calcolati fuori dal render, su un contesto separato
/// (`ArchiveHealthChecker`). Il risultato è un calcolo derivato effimero tenuto solo in
/// `@State`: non viene scritto né messo in cache. Si ricalcola al lancio (la vista viene
/// ricreata dopo un ripristino), e dopo operazioni economiche con debounce.
struct IntegrityStatusView: View {
    @Environment(\.modelContext) private var context
    @State private var warnings: [String] = []
    @State private var failure: String?
    @State private var revision = 0
    /// Validazione completa dell'archivio solo al primo calcolo (lancio / dopo ripristino).
    @State private var didRunFullValidation = false
    /// Ultimo esito della validazione completa: riaggiunto a ogni refresh finché non si rilancia.
    @State private var fullValidationMessage: String?

    var body: some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .paolaEconomicDataDidChange)) { _ in revision += 1 }
            .task(id: revision) { await refresh() }
    }

    @MainActor
    private func refresh() async {
        // Debounce: più operazioni ravvicinate annullano il task precedente.
        do { try await Task.sleep(for: .milliseconds(revision == 0 ? 300 : 800)) } catch { return }
        let container = context.container
        let runFull = !didRunFullValidation
        do {
            let signposter = PaolaSignpost.signposter
            let state = signposter.beginInterval("integrity.refresh", id: signposter.makeSignpostID())
            defer { signposter.endInterval("integrity.refresh", state) }
            let (result, full) = try await Task.detached(priority: .utility) { () throws -> ([String], String?) in
                let checker = ArchiveHealthChecker(modelContainer: container)
                let result = try await checker.integrityWarnings()
                let full = runFull ? try await checker.fullValidation() : nil
                return (result, full)
            }.value
            guard !Task.isCancelled else { return }
            if runFull {
                didRunFullValidation = true
                fullValidationMessage = full
            }
            warnings = result + (fullValidationMessage.map { [$0] } ?? [])
            failure = nil
        } catch {
            guard !Task.isCancelled else { return }
            failure = error.localizedDescription
        }
    }

    @ViewBuilder
    private var content: some View {
        if let failure {
            Label("Verifica dell'archivio non riuscita: \(failure)", systemImage: "exclamationmark.triangle")
                .font(.callout).padding().frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.12))
        } else if !warnings.isEmpty {
            DisclosureGroup {
                ForEach(warnings, id: \.self) { warning in
                    Text(warning).frame(maxWidth: .infinity, alignment: .leading)
                }
                Text("Non considerare definitivi i saldi: conserva un backup e risolvi le incoerenze prima di nuove operazioni economiche.")
                    .font(.caption)
            } label: {
                Label("Archivio da verificare: \(warnings.count) segnalazioni", systemImage: "exclamationmark.triangle")
            }
            .font(.callout).padding()
            .background(Color.orange.opacity(0.12))
        }
    }
}
