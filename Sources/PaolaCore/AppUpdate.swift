import Foundation

/// Versione applicativa nel formato `major.minor.patch`, confrontabile in ordine numerico.
public struct AppVersion: Comparable, Equatable, CustomStringConvertible, Sendable {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major; self.minor = minor; self.patch = patch
    }

    /// Interpreta stringhe come `0.6`, `0.6.42` o `v0.6.42`. La patch mancante vale 0.
    public init?(_ raw: String) {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("v") || text.hasPrefix("V") { text.removeFirst() }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard (2...3).contains(parts.count) else { return nil }
        let numbers = parts.map { Int($0) }
        guard numbers.allSatisfy({ $0 != nil && $0! >= 0 }) else { return nil }
        major = numbers[0]!
        minor = numbers[1]!
        patch = parts.count == 3 ? numbers[2]! : 0
    }

    public var description: String { "\(major).\(minor).\(patch)" }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }
}

/// Un asset scaricabile pubblicato in una release GitHub.
public struct ReleaseAsset: Equatable, Sendable {
    public let name: String
    public let downloadURL: URL
    public let sizeBytes: Int64

    public init(name: String, downloadURL: URL, sizeBytes: Int64) {
        self.name = name; self.downloadURL = downloadURL; self.sizeBytes = sizeBytes
    }
}

/// La release più recente pubblicata su GitHub, con gli asset utili all'aggiornamento.
public struct ReleaseInfo: Equatable, Sendable {
    public let tag: String
    public let version: AppVersion
    public let notes: String
    public let appArchive: ReleaseAsset
    public let checksums: ReleaseAsset?

    public init(tag: String, version: AppVersion, notes: String,
                appArchive: ReleaseAsset, checksums: ReleaseAsset?) {
        self.tag = tag; self.version = version; self.notes = notes
        self.appArchive = appArchive; self.checksums = checksums
    }
}

/// Esito del confronto tra la versione installata e l'ultima release disponibile.
public enum UpdateCheck: Equatable, Sendable {
    case upToDate(current: AppVersion)
    case updateAvailable(current: AppVersion, release: ReleaseInfo)

    public var release: ReleaseInfo? {
        if case let .updateAvailable(_, release) = self { return release }
        return nil
    }
}

public enum UpdateError: Error, LocalizedError, Equatable {
    case invalidResponse
    case noCompatibleAsset
    case unreadableVersion
    case checksumMissing
    case checksumMismatch

    public var errorDescription: String? {
        switch self {
        case .invalidResponse: return "La risposta di GitHub non è valida o non contiene una release."
        case .noCompatibleAsset: return "La release non contiene un archivio dell'app compatibile."
        case .unreadableVersion: return "Impossibile leggere il numero di versione della release."
        case .checksumMissing: return "L'archivio dei checksum non elenca il file scaricato."
        case .checksumMismatch: return "Il file scaricato non corrisponde al checksum pubblicato."
        }
    }
}

/// Coordinate del repository GitHub da cui leggere le release.
public struct GitHubRepository: Sendable, Equatable {
    public let owner: String
    public let name: String

    public init(owner: String, name: String) {
        self.owner = owner; self.name = name
    }

    /// Repository di default della release ufficiale (vedi PROGETTO.md, sezione 17).
    public static let paola = GitHubRepository(owner: "Saifer88", name: "gestionale")

    public var latestReleaseURL: URL {
        URL(string: "https://api.github.com/repos/\(owner)/\(name)/releases/latest")!
    }
}

/// Analisi pura (senza rete) delle risposte GitHub, così da poterla testare.
public enum GitHubReleaseParser {
    /// Riconosce l'archivio universale dell'app tra gli asset della release.
    public static func isAppArchive(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.hasSuffix(".zip") && lower.contains("paolagestionale") && lower.contains("macos")
    }

    /// Costruisce `ReleaseInfo` dal JSON di `/releases/latest`.
    public static func parseLatestRelease(_ data: Data) throws -> ReleaseInfo {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UpdateError.invalidResponse
        }
        guard object["draft"] as? Bool != true else { throw UpdateError.invalidResponse }
        guard let tag = object["tag_name"] as? String, !tag.isEmpty else {
            throw UpdateError.invalidResponse
        }
        guard let version = AppVersion(tag) else { throw UpdateError.unreadableVersion }
        let notes = (object["body"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let rawAssets = object["assets"] as? [[String: Any]] ?? []
        let assets: [ReleaseAsset] = rawAssets.compactMap { entry in
            guard let name = entry["name"] as? String,
                  let urlString = entry["browser_download_url"] as? String,
                  let url = URL(string: urlString) else { return nil }
            let size = (entry["size"] as? NSNumber)?.int64Value ?? 0
            return ReleaseAsset(name: name, downloadURL: url, sizeBytes: size)
        }

        guard let appArchive = assets.first(where: { isAppArchive($0.name) }) else {
            throw UpdateError.noCompatibleAsset
        }
        let checksums = assets.first { $0.name.uppercased() == "SHA256SUMS.TXT" }
        return ReleaseInfo(tag: tag, version: version, notes: notes,
                           appArchive: appArchive, checksums: checksums)
    }

    /// Confronta l'ultima release con la versione installata.
    public static func evaluate(current: AppVersion, release: ReleaseInfo) -> UpdateCheck {
        release.version > current
            ? .updateAvailable(current: current, release: release)
            : .upToDate(current: current)
    }
}

/// Analisi di `SHA256SUMS.txt` (formato `shasum -a 256`: "<hash>  <nome file>").
public enum ChecksumManifest {
    /// Ritorna lo SHA-256 atteso (minuscolo) per il file indicato, se presente.
    public static func expectedHash(for fileName: String, manifest: String) -> String? {
        for line in manifest.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            // Separa l'hash dal nome file; il nome può iniziare con "*" (modalità binaria).
            let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count == 2 else { continue }
            let hash = parts[0].lowercased()
            var name = parts[1].trimmingCharacters(in: .whitespaces)
            if name.hasPrefix("*") { name.removeFirst() }
            if name == fileName, hash.count == 64,
               hash.allSatisfy({ $0.isHexDigit }) {
                return hash
            }
        }
        return nil
    }
}
