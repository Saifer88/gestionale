import Foundation

/// Astrazione per la conservazione di segreti (credenziali Aruba). L'implementazione
/// di produzione usa il Keychain; i test possono iniettare un'implementazione in memoria.
/// I valori non vengono mai scritti nei log.
public protocol SecretStore: AnyObject {
    func string(for key: String) -> String?
    func set(_ value: String?, for key: String) throws
}

public enum SecretKey {
    public static let arubaUsername = "aruba.username"
    public static let arubaPassword = "aruba.password"
    /// Password del backup automatico giornaliero (Keychain). Scelta dall'utente,
    /// usata per cifrare i backup automatici senza doverla ridigitare.
    public static let autoBackupPassword = "backup.autoPassword"
}

/// Legge/scrive la password del backup automatico tramite un `SecretStore` (Keychain).
public final class BackupPasswordStore {
    private let secrets: SecretStore
    public init(secrets: SecretStore) { self.secrets = secrets }

    /// Password memorizzata (nil se non impostata).
    public func password() -> String? {
        let value = secrets.string(for: SecretKey.autoBackupPassword)
        return (value?.isEmpty == false) ? value : nil
    }
    public var isConfigured: Bool { password() != nil }

    /// Salva la password (minimo 12 caratteri, come per i backup manuali).
    public func save(_ password: String) throws {
        guard password.count >= 12 else {
            throw BusinessError.invalidInput("La password del backup deve avere almeno 12 caratteri.")
        }
        try secrets.set(password, for: SecretKey.autoBackupPassword)
    }
    public func clear() throws {
        try secrets.set(nil, for: SecretKey.autoBackupPassword)
    }
}

/// Credenziali del servizio di fatturazione elettronica Aruba.
public struct ArubaCredentials: Equatable, Sendable {
    public var username: String
    public var password: String

    public init(username: String = "", password: String = "") {
        self.username = username
        self.password = password
    }

    /// Username tipo `123456@aruba.it` e password non vuota.
    public var isComplete: Bool {
        !username.trimmingCharacters(in: .whitespaces).isEmpty
            && !password.isEmpty
    }
}

/// Legge e scrive le credenziali Aruba tramite un `SecretStore`.
public final class ArubaCredentialsStore {
    private let secrets: SecretStore

    public init(secrets: SecretStore) {
        self.secrets = secrets
    }

    public func load() -> ArubaCredentials {
        ArubaCredentials(
            username: secrets.string(for: SecretKey.arubaUsername) ?? "",
            password: secrets.string(for: SecretKey.arubaPassword) ?? ""
        )
    }

    public func save(_ credentials: ArubaCredentials) throws {
        let username = credentials.username.trimmingCharacters(in: .whitespacesAndNewlines)
        try secrets.set(username.isEmpty ? nil : username, for: SecretKey.arubaUsername)
        try secrets.set(credentials.password.isEmpty ? nil : credentials.password, for: SecretKey.arubaPassword)
    }

    public func clear() throws {
        try secrets.set(nil, for: SecretKey.arubaUsername)
        try secrets.set(nil, for: SecretKey.arubaPassword)
    }
}

/// Implementazione in memoria del `SecretStore`, per test e anteprime.
public final class InMemorySecretStore: SecretStore {
    private var storage: [String: String] = [:]
    public init() {}
    public func string(for key: String) -> String? { storage[key] }
    public func set(_ value: String?, for key: String) throws {
        if let value { storage[key] = value } else { storage.removeValue(forKey: key) }
    }
}
