import Foundation
import SwiftData

/// Stato di una fattura elettronica. I titoli sono in italiano per la UI.
/// La fattura è un documento informativo: lo stato descrive il ciclo di trasmissione
/// verso il servizio esterno (Aruba), non altera i movimenti economici.
public enum InvoiceStatus: String, CaseIterable, Identifiable, Codable {
    case draft, queued, transmitted, delivered, rejected, failed
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .draft: return "Bozza"
        case .queued: return "In coda"
        case .transmitted: return "Trasmessa"
        case .delivered: return "Consegnata"
        case .rejected: return "Scartata"
        case .failed: return "Errore"
        }
    }
}

/// Entità fattura elettronica (schema V8). Documento informativo collegato in modo
/// idempotente all'incasso di origine (appuntamento o pacchetto) tramite `sourceKey`.
/// Gli importi sono in centesimi (`Int64`), mai floating point.
@Model public final class Invoice {
    public var id: UUID = UUID()
    public var clientID: UUID = UUID()
    public var clientName: String = ""
    /// Data di fatturazione.
    public var issueDate: Date = Date()
    /// Imponibile in centesimi.
    public var taxableCents: Int64 = 0
    /// Rivalsa/contributo in centesimi.
    public var contributionCents: Int64 = 0
    /// Totale documento in centesimi.
    public var totalCents: Int64 = 0
    /// Metodo dell'incasso di origine (vedi `PaymentMethod`).
    public var paymentMethodRaw: String = "cash"
    /// Chiave stabile per l'idempotenza: collega la fattura all'incasso di origine.
    /// Convenzione: "invoice:session:<sessionID>:<clientID>" oppure "invoice:package:<packageID>".
    public var sourceKey: String = ""
    /// Stato di trasmissione (vedi `InvoiceStatus`).
    public var statusRaw: String = "draft"
    /// Identificativo/numero restituito dal servizio esterno (Aruba); nil finché non trasmessa.
    public var arubaInvoiceId: String?
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    /// Motivo dello scarto o dell'errore, se presente.
    public var errorMessage: String?

    public var status: InvoiceStatus {
        get { InvoiceStatus(rawValue: statusRaw) ?? .draft }
        set { statusRaw = newValue.rawValue }
    }
    public var paymentMethod: PaymentMethod {
        get { PaymentMethod(rawValue: paymentMethodRaw) ?? .cash }
        set { paymentMethodRaw = newValue.rawValue }
    }

    public init(id: UUID = UUID(), clientID: UUID = UUID(), clientName: String = "",
                issueDate: Date = Date(), taxableCents: Int64 = 0, contributionCents: Int64 = 0,
                totalCents: Int64 = 0, paymentMethod: PaymentMethod = .cash, sourceKey: String = "",
                status: InvoiceStatus = .draft, arubaInvoiceId: String? = nil,
                createdAt: Date = Date(), updatedAt: Date = Date(), errorMessage: String? = nil) {
        self.id = id; self.clientID = clientID; self.clientName = clientName
        self.issueDate = issueDate; self.taxableCents = taxableCents
        self.contributionCents = contributionCents; self.totalCents = totalCents
        self.paymentMethodRaw = paymentMethod.rawValue; self.sourceKey = sourceKey
        self.statusRaw = status.rawValue; self.arubaInvoiceId = arubaInvoiceId
        self.createdAt = createdAt; self.updatedAt = updatedAt; self.errorMessage = errorMessage
    }
}

extension Invoice {
    /// Chiave di origine per la fattura di un appuntamento (idempotenza).
    public static func sessionSourceKey(sessionID: UUID, clientID: UUID) -> String {
        "invoice:session:\(sessionID.uuidString.lowercased()):\(clientID.uuidString.lowercased())"
    }
    /// Chiave di origine per la fattura di un pacchetto (idempotenza).
    public static func packageSourceKey(_ packageID: UUID) -> String {
        "invoice:package:\(packageID.uuidString.lowercased())"
    }
}
