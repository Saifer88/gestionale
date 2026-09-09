import Foundation

public enum ClientFilter: String, CaseIterable, Identifiable {
    case active
    case archived
    case all

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .active: return "Attivi"
        case .archived: return "Archiviati"
        case .all: return "Tutti"
        }
    }
}

public enum ClientSearch {
    public static func matches(_ client: Client, query: String, filter: ClientFilter) -> Bool {
        switch filter {
        case .active where client.isArchived: return false
        case .archived where !client.isArchived: return false
        default: break
        }

        let tokens = TextNormalization.key(query).split(separator: " ")
        let text = TextNormalization.key("\(client.fullName) \(client.email) \(client.phone)")
        let phone = TextNormalization.phone(client.phone)
        return tokens.allSatisfy { token in
            if text.contains(token) { return true }
            guard token.contains(where: \.isNumber),
                  token.allSatisfy({ $0.isNumber || "+()-./".contains($0) }) else {
                return false
            }
            return phone.contains(TextNormalization.phone(String(token)))
        }
    }
}
