import Foundation
import SwiftData

/// Tipo di spesa: una tantum (con data specifica) oppure ricorrente mensile
/// (considerata il primo giorno di ogni mese, dalla data di inizio in poi).
public enum ExpenseKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case oneTime, monthlyRecurring
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .oneTime: return "Una tantum"
        case .monthlyRecurring: return "Ricorrente mensile"
        }
    }
}

/// Spesa (schema V11). Importi in centesimi (`Int64`), mai floating point.
/// - `date`: per una spesa una tantum è il giorno di spesa; per una ricorrente è la
///   data di inizio (la ricorrenza vale dal primo giorno del mese di `date` in poi).
/// - `sourceKey`: chiave stabile per l'idempotenza delle spese automatiche generate
///   dagli incassi Stripe/carta; vuota per le spese inserite a mano.
@Model public final class Expense {
    public var id: UUID = UUID()
    public var name: String = ""
    public var date: Date = Date()
    public var amountCents: Int64 = 0
    public var kindRaw: String = "oneTime"
    public var sourceKey: String = ""
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    public var kind: ExpenseKind {
        get { ExpenseKind(rawValue: kindRaw) ?? .oneTime }
        set { kindRaw = newValue.rawValue }
    }

    public init(id: UUID = UUID(), name: String = "", date: Date = Date(),
                amountCents: Int64 = 0, kind: ExpenseKind = .oneTime, sourceKey: String = "",
                createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id; self.name = name; self.date = date
        self.amountCents = amountCents; self.kindRaw = kind.rawValue; self.sourceKey = sourceKey
        self.createdAt = createdAt; self.updatedAt = updatedAt
    }
}

extension Expense {
    /// Chiave di origine per la spesa automatica dell'incasso di un appuntamento.
    public static func sessionFeeSourceKey(sessionID: UUID, clientID: UUID) -> String {
        "expense:fee:session:\(sessionID.uuidString.lowercased()):\(clientID.uuidString.lowercased())"
    }
    /// Chiave di origine per la spesa automatica dell'incasso di un pacchetto.
    public static func packageFeeSourceKey(_ packageID: UUID) -> String {
        "expense:fee:package:\(packageID.uuidString.lowercased())"
    }
}

/// Commissione di transazione per gli incassi elettronici (Stripe/carta).
/// Carta: prezzo × 1,4% + 0,10 €. Stripe: prezzo × 1,5% + 0,25 €.
/// Restituisce la commissione in centesimi (arrotondata al centesimo).
public enum TransactionFee {
    /// Metodi che generano una commissione (e quindi una spesa automatica).
    public static func applies(to method: PaymentMethod) -> Bool {
        method == .stripe || method == .card
    }

    /// Commissione in centesimi per un incasso di `priceCents` col metodo indicato.
    /// Ritorna nil se il metodo non prevede commissione.
    public static func cents(for priceCents: Int64, method: PaymentMethod) -> Int64? {
        let percent: Double
        let fixed: Int64
        switch method {
        case .card: percent = 0.014; fixed = 10   // 1,4% + 0,10 €
        case .stripe: percent = 0.015; fixed = 25 // 1,5% + 0,25 €
        default: return nil
        }
        let variable = Int64((Double(priceCents) * percent).rounded())
        return variable + fixed
    }
}
