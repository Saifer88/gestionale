import CommonCrypto
import CryptoKit
import Foundation
import Security

public enum BackupCipher {
    public static let minimumPasswordLength = 12
    public static let maximumPasswordBytes = 2_048
    public static let maximumPayloadSize = 64_000_000
    public static let maximumArchiveSize = 100_000_000

    private static let version = 1
    private static let saltSize = 32
    private static let keySize = 32
    private static let combinedOverhead = 12 + 16
    private static let derivationRounds: UInt32 = 600_000

    public static func encrypt(_ payload: Data, password: String) throws -> Data {
        guard payload.count <= maximumPayloadSize else {
            throw BackupCipherError.payloadTooLarge
        }
        try validatePassword(password, forEncryption: true)

        let salt = try randomSalt()
        let metadata = Metadata(
            version: version,
            createdAt: Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970)),
            saltData: salt
        )
        let key = try deriveKey(password: password, salt: salt)
        let sealedBox: AES.GCM.SealedBox
        do {
            sealedBox = try AES.GCM.seal(
                payload,
                using: key,
                authenticating: authenticatedData(for: metadata)
            )
        } catch {
            throw BackupCipherError.encryptionFailed
        }
        guard let combined = sealedBox.combined,
              combined.count <= maximumPayloadSize + combinedOverhead else {
            throw BackupCipherError.encryptionFailed
        }

        let archive = try encoder().encode(Envelope(metadata: metadata, combinedData: combined))
        guard archive.count <= maximumArchiveSize else {
            throw BackupCipherError.archiveTooLarge
        }
        return archive
    }

    public static func decrypt(_ archive: Data, password: String) throws -> Data {
        guard archive.count <= maximumArchiveSize else {
            throw BackupCipherError.archiveTooLarge
        }
        guard !archive.isEmpty else {
            throw BackupCipherError.invalidArchive
        }
        try validatePassword(password, forEncryption: false)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let envelope: Envelope
        do {
            envelope = try decoder.decode(Envelope.self, from: archive)
        } catch let error as BackupCipherError {
            throw error
        } catch {
            throw BackupCipherError.invalidArchive
        }
        guard envelope.saltData.count == saltSize,
              envelope.combinedData.count >= combinedOverhead else {
            throw BackupCipherError.invalidArchive
        }
        guard envelope.combinedData.count <= maximumPayloadSize + combinedOverhead else {
            throw BackupCipherError.archiveTooLarge
        }

        let key = try deriveKey(password: password, salt: envelope.saltData)
        do {
            let sealedBox = try AES.GCM.SealedBox(combined: envelope.combinedData)
            return try AES.GCM.open(
                sealedBox,
                using: key,
                authenticating: authenticatedData(for: envelope.metadata)
            )
        } catch {
            throw BackupCipherError.authenticationFailed
        }
    }

    private static func validatePassword(_ password: String, forEncryption: Bool) throws {
        guard password.utf8.prefix(maximumPasswordBytes + 1).count <= maximumPasswordBytes else {
            throw BackupCipherError.passwordTooLong
        }
        guard !password.isEmpty else {
            throw BackupCipherError.emptyPassword
        }
        if forEncryption && password.prefix(minimumPasswordLength).count < minimumPasswordLength {
            throw BackupCipherError.passwordTooShort
        }
    }

    private static func randomSalt() throws -> Data {
        var salt = Data(count: saltSize)
        let status = salt.withUnsafeMutableBytes { buffer -> OSStatus in
            guard let address = buffer.baseAddress else {
                return errSecAllocate
            }
            return SecRandomCopyBytes(kSecRandomDefault, buffer.count, address)
        }
        guard status == errSecSuccess else {
            throw BackupCipherError.randomGenerationFailed(status)
        }
        return salt
    }

    private static func deriveKey(password: String, salt: Data) throws -> SymmetricKey {
        var passwordBytes = Data(password.utf8)
        var keyBytes = Data(count: keySize)
        defer {
            passwordBytes.resetBytes(in: 0..<passwordBytes.count)
            keyBytes.resetBytes(in: 0..<keyBytes.count)
        }
        let status = passwordBytes.withUnsafeBytes { passwordBuffer in
            salt.withUnsafeBytes { saltBuffer in
                keyBytes.withUnsafeMutableBytes { keyBuffer -> Int32 in
                    guard let passwordAddress = passwordBuffer.bindMemory(to: CChar.self).baseAddress,
                          let saltAddress = saltBuffer.bindMemory(to: UInt8.self).baseAddress,
                          let keyAddress = keyBuffer.bindMemory(to: UInt8.self).baseAddress else {
                        return Int32(kCCParamError)
                    }
                    return CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordAddress,
                        passwordBuffer.count,
                        saltAddress,
                        saltBuffer.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        derivationRounds,
                        keyAddress,
                        keyBuffer.count
                    )
                }
            }
        }
        guard status == kCCSuccess else {
            throw BackupCipherError.keyDerivationFailed
        }
        return SymmetricKey(data: keyBytes)
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static func authenticatedData(for metadata: Metadata) throws -> Data {
        // Version 1 authenticates its canonical JSON header as well as the ciphertext.
        var data = Data("PaolaGestionale.BackupCipher.v1\u{0000}".utf8)
        data.append(try encoder().encode(metadata))
        return data
    }

    private struct Metadata: Codable {
        let version: Int
        let createdAt: Date?
        let saltData: Data
    }

    private struct Envelope: Codable {
        let version: Int
        let createdAt: Date?
        let saltData: Data
        let combinedData: Data

        var metadata: Metadata {
            Metadata(version: version, createdAt: createdAt, saltData: saltData)
        }

        init(metadata: Metadata, combinedData: Data) {
            version = metadata.version
            createdAt = metadata.createdAt
            saltData = metadata.saltData
            self.combinedData = combinedData
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            version = try container.decode(Int.self, forKey: .version)
            guard version == BackupCipher.version else {
                throw BackupCipherError.unsupportedVersion(version)
            }
            createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
            saltData = try container.decode(Data.self, forKey: .saltData)
            combinedData = try container.decode(Data.self, forKey: .combinedData)
        }
    }
}

public enum BackupCipherError: Error, Equatable, LocalizedError {
    case emptyPassword
    case passwordTooShort
    case passwordTooLong
    case payloadTooLarge
    case archiveTooLarge
    case invalidArchive
    case unsupportedVersion(Int)
    case authenticationFailed
    case randomGenerationFailed(OSStatus)
    case keyDerivationFailed
    case encryptionFailed

    public var errorDescription: String? {
        switch self {
        case .emptyPassword:
            return "Inserisci la password del backup."
        case .passwordTooShort:
            return "Scegli una password di almeno 12 caratteri."
        case .passwordTooLong:
            return "La password è troppo lunga: il limite è di 2048 byte UTF-8."
        case .payloadTooLarge:
            return "I dati superano il limite di 64 MB per un backup."
        case .archiveTooLarge:
            return "Il backup supera i limiti consentiti: 100 MB per il file e 64 MB per i dati."
        case .invalidArchive:
            return "Il file non è un backup cifrato valido di Paola Gestionale."
        case .unsupportedVersion:
            return "Questa versione del backup non è supportata. Aggiorna l'app e riprova."
        case .authenticationFailed:
            return "Impossibile aprire il backup: password errata oppure file danneggiato o modificato."
        case .randomGenerationFailed, .keyDerivationFailed, .encryptionFailed:
            return "Impossibile proteggere il backup. Nessun dato è stato esportato. Riprova."
        }
    }
}
