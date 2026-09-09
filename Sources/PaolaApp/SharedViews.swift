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

struct IntegrityStatusView: View {
    @Query private var entries: [LedgerEntry]
    @Query private var packages: [LessonPackage]
    @Query private var uses: [PackageUse]

    private var warnings: [String] {
        BusinessReports.integrityWarnings(entries: entries, packages: packages, uses: uses)
    }

    var body: some View {
        if let error = _entries.fetchError ?? _packages.fetchError ?? _uses.fetchError {
            Label("Verifica dell'archivio non riuscita: \(error.localizedDescription)", systemImage: "exclamationmark.triangle")
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
