#if os(macOS)
import AppKit
import CryptoKit
import Foundation
import PaolaCore
import SwiftUI

/// Coordina il controllo, il download verificato e la preparazione di un aggiornamento
/// dell'app a partire dalle release pubblicate su GitHub.
///
/// Aggiornamento assistito (Opzione 1): l'app scarica e verifica lo ZIP della nuova
/// versione, lo espande in una cartella dedicata e apre il Finder sul nuovo bundle,
/// chiedendo all'utente di sostituire manualmente l'app. Non tenta la sostituzione
/// automatica del proprio bundle: la build è firmata solo ad hoc e non notarizzata,
/// quindi una sostituzione silenziosa sarebbe inaffidabile con Gatekeeper.
@MainActor
final class AppUpdater: ObservableObject {
    enum Phase: Equatable {
        case idle
        case checking
        case downloading(progress: Double)
        case ready(URL)
        case upToDate
        case localBuild
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    /// Popolato quando è disponibile una release più recente, per mostrare la conferma.
    @Published var availableRelease: ReleaseInfo?

    private let repository: GitHubRepository
    private let session: URLSession
    private let currentVersion: AppVersion
    private let localBuild: Bool

    init(repository: GitHubRepository = .paola,
         session: URLSession = .shared,
         currentVersion: AppVersion? = nil,
         isLocalBuild: Bool = AppUpdater.installedIsLocalBuild()) {
        self.repository = repository
        self.session = session
        self.currentVersion = currentVersion ?? AppUpdater.installedVersion()
        self.localBuild = isLocalBuild
    }

    /// Legge la versione installata da `CFBundleShortVersionString`.
    nonisolated static func installedVersion() -> AppVersion {
        let raw = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        return AppVersion(raw) ?? AppVersion(major: 0, minor: 0, patch: 0)
    }

    /// Le build locali di sviluppo (create da build-app.sh) sono marcate `PaolaLocalBuild=YES`
    /// e non devono proporre aggiornamenti da GitHub.
    nonisolated static func installedIsLocalBuild() -> Bool {
        (Bundle.main.object(forInfoDictionaryKey: "PaolaLocalBuild") as? String) == "YES"
    }

    var currentVersionText: String { currentVersion.description }

    var isBusy: Bool {
        switch phase {
        case .checking, .downloading: return true
        default: return false
        }
    }

    var isLocalBuild: Bool { localBuild }

    /// Interroga GitHub e, se c'è una versione più recente, prepara la conferma.
    func checkForUpdates() async {
        guard !localBuild else {
            phase = .localBuild
            return
        }
        phase = .checking
        availableRelease = nil
        do {
            var request = URLRequest(url: repository.latestReleaseURL)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
            request.setValue("PaolaGestionale", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw UpdateError.invalidResponse
            }
            let release = try GitHubReleaseParser.parseLatestRelease(data)
            switch GitHubReleaseParser.evaluate(current: currentVersion, release: release) {
            case .upToDate:
                phase = .upToDate
            case .updateAvailable(_, let release):
                availableRelease = release
                phase = .idle
            }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// Scarica lo ZIP della release, verifica lo SHA-256 (se disponibile) e lo espande.
    /// Al termine apre il Finder sul nuovo bundle e passa a `.ready`.
    func downloadAndPrepare(_ release: ReleaseInfo) async {
        availableRelease = nil
        phase = .downloading(progress: 0)
        do {
            let archiveData = try await download(release.appArchive.downloadURL)

            if let checksums = release.checksums {
                let manifestData = try await download(checksums.downloadURL)
                let manifest = String(decoding: manifestData, as: UTF8.self)
                guard let expected = ChecksumManifest.expectedHash(for: release.appArchive.name, manifest: manifest) else {
                    throw UpdateError.checksumMissing
                }
                let actual = SHA256.hash(data: archiveData).map { String(format: "%02x", $0) }.joined()
                guard actual == expected else { throw UpdateError.checksumMismatch }
            }

            let bundleURL = try expand(archiveData: archiveData, tag: release.tag)
            NSWorkspace.shared.activateFileViewerSelecting([bundleURL])
            phase = .ready(bundleURL)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func reset() { phase = .idle; availableRelease = nil }

    /// Da chiamare all'apparire della vista: mostra subito lo stato di build locale.
    func prepareInitialState() {
        if localBuild { phase = .localBuild }
    }

    // MARK: - Rete

    private func download(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("PaolaGestionale", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw UpdateError.invalidResponse
        }
        return data
    }

    // MARK: - Estrazione

    /// Scrive lo ZIP in una cartella dedicata in Application Support e lo espande con `ditto`.
    /// Ritorna l'URL del `.app` estratto.
    private func expand(archiveData: Data, tag: String) throws -> URL {
        let fileManager = FileManager.default
        let base = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                       appropriateFor: nil, create: true)
            .appendingPathComponent("PaolaGestionale/Updates/\(sanitize(tag))", isDirectory: true)
        if fileManager.fileExists(atPath: base.path) {
            try fileManager.removeItem(at: base)
        }
        try fileManager.createDirectory(at: base, withIntermediateDirectories: true)

        let zipURL = base.appendingPathComponent("update.zip")
        try archiveData.write(to: zipURL, options: .atomic)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", zipURL.path, base.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw UpdateError.invalidResponse }

        let contents = try fileManager.contentsOfDirectory(at: base, includingPropertiesForKeys: nil)
        guard let app = contents.first(where: { $0.pathExtension == "app" }) else {
            throw UpdateError.noCompatibleAsset
        }
        return app
    }

    private func sanitize(_ tag: String) -> String {
        let allowed = CharacterSet(charactersIn:
            "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_")
        return String(tag.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
    }
}
#endif
