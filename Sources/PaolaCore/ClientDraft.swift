import Foundation

public enum ClientValidationError: LocalizedError, Equatable {
    case missingName
    case invalidEmail
    case possibleDuplicate
    case staleRecord
    case invalidDate

    public var errorDescription: String? {
        switch self {
        case .missingName:
            return "Inserisci sia il nome sia il cognome."
        case .invalidEmail:
            return "Inserisci un indirizzo email valido oppure lascia il campo vuoto."
        case .possibleDuplicate:
            return "Esiste gia un cliente con lo stesso nome e cognome, telefono o email. Verifica prima di continuare."
        case .staleRecord:
            return "Questo cliente e stato modificato o non e piu disponibile. Riapri la scheda prima di salvare."
        case .invalidDate:
            return "Inserisci una data di inizio rapporto valida."
        }
    }
}

public struct ClientDraft {
    public var firstName: String = ""
    public var lastName: String = ""
    public var phone: String = ""
    public var email: String = ""
    public var notes: String = ""
    public var anamnesis: String = ""
    public var physicalAnalysis: String = ""
    public var joinedOn: Date = Calendar.current.startOfDay(for: Date())

    private var originalID: UUID?
    private var originalUpdatedAt: Date?

    public init() {}

    public init(client: Client) {
        firstName = client.firstName
        lastName = client.lastName
        phone = client.phone
        email = client.email
        notes = client.notes
        anamnesis = client.anamnesis
        physicalAnalysis = client.physicalAnalysis
        joinedOn = client.joinedOn
        originalID = client.id
        originalUpdatedAt = client.updatedAt
    }

    public func validated() throws -> ClientDraft {
        var result = self
        result.firstName = TextNormalization.spaces(firstName)
        result.lastName = TextNormalization.spaces(lastName)
        result.phone = TextNormalization.spaces(phone)
        result.email = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        result.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        result.anamnesis = anamnesis.trimmingCharacters(in: .whitespacesAndNewlines)
        result.physicalAnalysis = physicalAnalysis.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !result.firstName.isEmpty, !result.lastName.isEmpty else {
            throw ClientValidationError.missingName
        }
        guard result.email.isEmpty || Self.isValidEmail(result.email) else {
            throw ClientValidationError.invalidEmail
        }
        guard joinedOn.timeIntervalSinceReferenceDate.isFinite else {
            throw ClientValidationError.invalidDate
        }
        result.joinedOn = Calendar.current.startOfDay(for: joinedOn)
        return result
    }

    func checkOriginal(for client: Client?) throws {
        guard let originalID, let originalUpdatedAt else { return }
        guard let client, client.id == originalID, client.updatedAt == originalUpdatedAt else {
            throw ClientValidationError.staleRecord
        }
    }

    private static func isValidEmail(_ email: String) -> Bool {
        guard !email.unicodeScalars.contains(where: {
            CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0)
        }) else { return false }

        let parts = email.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return false }
        let local = parts[0]
        guard !local.isEmpty,
              !local.hasPrefix("."), !local.hasSuffix("."), !local.contains(".."),
              !local.contains(where: { "(),:;<>[\\]\"".contains($0) }) else {
            return false
        }

        let labels = parts[1].split(separator: ".", omittingEmptySubsequences: false)
        return labels.count >= 2 && labels.allSatisfy { label in
            !label.isEmpty && !label.hasPrefix("-") && !label.hasSuffix("-")
                && label.unicodeScalars.allSatisfy {
                    CharacterSet.alphanumerics.contains($0) || $0 == "-"
                }
        }
    }
}

enum TextNormalization {
    static func spaces(_ value: String) -> String {
        value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static func key(_ value: String) -> String {
        spaces(value).folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "it_IT")
        )
    }

    static func phone(_ value: String) -> String {
        key(value).filter { $0.isLetter || $0.isNumber || $0 == "+" }
    }
}
