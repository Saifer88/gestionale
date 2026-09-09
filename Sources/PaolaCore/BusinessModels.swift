import Foundation
import SwiftData

public enum SessionStatus: String, CaseIterable, Identifiable, Codable {
    case planned, completed, cancelled, noShow
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .planned: return "Programmata"
        case .completed: return "Completata"
        case .cancelled: return "Annullata"
        case .noShow: return "Assenza"
        }
    }
}

public enum LedgerKind: String, CaseIterable, Identifiable, Codable {
    case charge, payment, refund, credit, unknown
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .charge: return "Addebito"
        case .payment: return "Pagamento"
        case .refund: return "Rimborso"
        case .credit: return "Nota di credito"
        case .unknown: return "Tipo sconosciuto"
        }
    }
}

public enum PaymentMethod: String, CaseIterable, Identifiable, Codable {
    case cash, bankTransfer, card, other
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .cash: return "Contanti"
        case .bankTransfer: return "Bonifico"
        case .card: return "Carta"
        case .other: return "Altro"
        }
    }
}

@Model public final class TrainingService {
    public var id: UUID = UUID()
    public var name: String = ""
    public var durationMinutes: Int = 60
    public var priceCents: Int64 = 0
    public var isActive: Bool = true
    public var updatedAt: Date = Date()

    public init(id: UUID = UUID(), name: String = "", durationMinutes: Int = 60,
                priceCents: Int64 = 0, isActive: Bool = true, updatedAt: Date = Date()) {
        self.id = id; self.name = name; self.durationMinutes = durationMinutes
        self.priceCents = priceCents; self.isActive = isActive; self.updatedAt = updatedAt
    }
}

@Model public final class TrainingSession {
    public var id: UUID = UUID()
    public var startDate: Date = Date()
    public var durationMinutes: Int = 60
    public var serviceID: UUID?
    public var serviceName: String = ""
    public var location: String = ""
    public var notes: String = ""
    public var statusRaw: String = "planned"
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    public var status: SessionStatus {
        get { SessionStatus(rawValue: statusRaw) ?? .planned }
        set { statusRaw = newValue.rawValue }
    }
    public var endDate: Date { startDate.addingTimeInterval(Double(durationMinutes) * 60) }

    public init(id: UUID = UUID(), startDate: Date = Date(), durationMinutes: Int = 60,
                serviceID: UUID? = nil, serviceName: String = "", location: String = "",
                notes: String = "", status: SessionStatus = .planned,
                createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id; self.startDate = startDate; self.durationMinutes = durationMinutes
        self.serviceID = serviceID; self.serviceName = serviceName; self.location = location
        self.notes = notes; self.statusRaw = status.rawValue
        self.createdAt = createdAt; self.updatedAt = updatedAt
    }
}

@Model public final class SessionParticipant {
    public var id: UUID = UUID()
    public var sessionID: UUID = UUID()
    public var clientID: UUID = UUID()
    public var clientName: String = ""
    public var priceCents: Int64 = 0
    public var packageID: UUID?

    public init(id: UUID = UUID(), sessionID: UUID = UUID(), clientID: UUID = UUID(),
                clientName: String = "", priceCents: Int64 = 0, packageID: UUID? = nil) {
        self.id = id; self.sessionID = sessionID; self.clientID = clientID
        self.clientName = clientName; self.priceCents = priceCents; self.packageID = packageID
    }
}

@Model public final class LessonPackage {
    public var id: UUID = UUID()
    public var clientID: UUID = UUID()
    public var clientName: String = ""
    public var purchasedOn: Date = Date()
    public var priceCents: Int64 = 0
    public var capacity: Int = 10
    public var expiresOn: Date?
    public var notes: String = ""

    public init(id: UUID = UUID(), clientID: UUID = UUID(), clientName: String = "",
                purchasedOn: Date = Date(), priceCents: Int64 = 0, capacity: Int = 10,
                expiresOn: Date? = nil, notes: String = "") {
        self.id = id; self.clientID = clientID; self.clientName = clientName
        self.purchasedOn = purchasedOn; self.priceCents = priceCents; self.capacity = capacity
        self.expiresOn = expiresOn; self.notes = notes
    }
}

@Model public final class PackageUse {
    public var id: UUID = UUID()
    public var packageID: UUID = UUID()
    public var sessionID: UUID = UUID()
    public var clientID: UUID = UUID()
    public var createdAt: Date = Date()
    public var sourceKey: String = ""

    public init(id: UUID = UUID(), packageID: UUID = UUID(), sessionID: UUID = UUID(),
                clientID: UUID = UUID(), createdAt: Date = Date(), sourceKey: String = "") {
        self.id = id; self.packageID = packageID; self.sessionID = sessionID
        self.clientID = clientID; self.createdAt = createdAt; self.sourceKey = sourceKey
    }
}

@Model public final class LedgerEntry {
    public var id: UUID = UUID()
    public var clientID: UUID = UUID()
    public var clientName: String = ""
    public var date: Date = Date()
    public var createdAt: Date = Date()
    public var kindRaw: String = "charge"
    public var amountCents: Int64 = 0
    public var methodRaw: String = "other"
    public var notes: String = ""
    public var sourceKey: String = ""
    public var originalEntryID: UUID?

    public var kind: LedgerKind {
        get { LedgerKind(rawValue: kindRaw) ?? .unknown }
        set { kindRaw = newValue.rawValue }
    }
    public var method: PaymentMethod {
        get { PaymentMethod(rawValue: methodRaw) ?? .other }
        set { methodRaw = newValue.rawValue }
    }
    public init(id: UUID = UUID(), clientID: UUID = UUID(), clientName: String = "",
                date: Date = Date(), createdAt: Date = Date(), kind: LedgerKind = .charge,
                amountCents: Int64 = 0, method: PaymentMethod = .other, notes: String = "",
                sourceKey: String = "", originalEntryID: UUID? = nil) {
        self.id = id; self.clientID = clientID; self.clientName = clientName
        self.date = date; self.createdAt = createdAt; self.kindRaw = kind.rawValue
        self.amountCents = amountCents; self.methodRaw = method.rawValue
        self.notes = notes; self.sourceKey = sourceKey; self.originalEntryID = originalEntryID
    }
}

@Model public final class Unavailability {
    public var id: UUID = UUID()
    public var startDate: Date = Date()
    public var endDate: Date = Date()
    public var title: String = ""

    public init(id: UUID = UUID(), startDate: Date = Date(), endDate: Date = Date(),
                title: String = "") {
        self.id = id; self.startDate = startDate; self.endDate = endDate; self.title = title
    }
}

public struct ServiceDraft {
    public var id: UUID?
    public var name = ""
    public var durationMinutes = 60
    public var priceCents: Int64 = 0
    public var tariffs: [ServiceRateDraft] = []
    public var isActive = true
    public init() {}
    public init(_ model: TrainingService) {
        id = model.id; name = model.name; durationMinutes = model.durationMinutes
        priceCents = model.priceCents; isActive = model.isActive
    }
    public init(_ model: TrainingService, rates: [ServiceRate]) {
        self.init(model)
        tariffs = ServiceTariffs.options(for: model, rates: rates)
    }
}

public struct ParticipantDraft {
    public var clientID: UUID
    public var priceCents: Int64
    public var packageID: UUID?
    public var tariffID: UUID? = nil
    public init(clientID: UUID, priceCents: Int64, packageID: UUID? = nil, tariffID: UUID? = nil) {
        self.clientID = clientID; self.priceCents = priceCents; self.packageID = packageID
        self.tariffID = tariffID
    }
}

public struct SessionDraft {
    public var id: UUID?
    public var startDate = Date()
    public var durationMinutes = 60
    public var serviceID: UUID?
    public var serviceName = ""
    public var location = ""
    public var notes = ""
    public var participants: [ParticipantDraft] = []
    public init() {}
    public init(_ model: TrainingSession, participants: [SessionParticipant] = []) {
        id = model.id; startDate = model.startDate; durationMinutes = model.durationMinutes
        serviceID = model.serviceID; serviceName = model.serviceName
        location = model.location; notes = model.notes
        self.participants = participants.filter { $0.sessionID == model.id }.map {
            ParticipantDraft(clientID: $0.clientID, priceCents: $0.priceCents, packageID: $0.packageID)
        }
    }
}

public struct PackageDraft {
    public var clientID = UUID()
    public var purchasedOn = Date()
    public var priceCents: Int64 = 0
    public var capacity = 10
    public var expiresOn: Date?
    public var notes = ""
    public init() {}
}

public struct PaymentDraft {
    public var clientID = UUID()
    public var date = Date()
    public var amountCents: Int64 = 0
    public var method: PaymentMethod = .cash
    public var notes = ""
    public init() {}
}

public struct BlockDraft {
    public var id: UUID?
    public var startDate = Date()
    public var endDate = Date().addingTimeInterval(3600)
    public var title = ""
    public init() {}
    public init(_ model: Unavailability) {
        id = model.id; startDate = model.startDate; endDate = model.endDate; title = model.title
    }
}

public enum BusinessError: Error, LocalizedError {
    case invalidInput(String)
    case notFound(String)
    case overlap
    case completedSessionLocked
    case serviceInUse
    case manualPaymentsDisabled
    case packageExhausted
    case inconsistentData(String)
    case amountExceeded
    case arithmeticOverflow

    public var errorDescription: String? {
        switch self {
        case .invalidInput(let reason), .inconsistentData(let reason): return reason
        case .notFound(let name): return "\(name) non trovato."
        case .overlap: return "L'orario si sovrappone a una lezione o a un'indisponibilità."
        case .completedSessionLocked: return "Una lezione completata non può essere modificata o riaperta."
        case .serviceInUse: return "Il servizio è usato in uno o più appuntamenti e non può essere eliminato senza perdere lo storico. Disattivalo per non proporlo nei nuovi appuntamenti."
        case .manualPaymentsDisabled: return "Gli incassi vengono registrati automaticamente all'acquisto di un pacchetto o al completamento di una lezione. I pagamenti manuali non sono più disponibili."
        case .packageExhausted: return "Il pacchetto non ha lezioni disponibili."
        case .amountExceeded: return "L'importo supera il residuo dell'operazione originale."
        case .arithmeticOverflow: return "L'importo supera il limite supportato."
        }
    }
}

internal enum BusinessRules {
    static func sessionSource(sessionID: UUID, clientID: UUID) -> String {
        "\(sessionID.uuidString.lowercased()):\(clientID.uuidString.lowercased())"
    }
    static func packageSource(_ id: UUID) -> String { id.uuidString.lowercased() }
    static func packageIncomeSource(_ id: UUID) -> String { "income:package:\(packageSource(id))" }
    static func sessionIncomeSource(sessionID: UUID, clientID: UUID) -> String {
        "income:session:\(sessionSource(sessionID: sessionID, clientID: clientID))"
    }
    static func date(_ date: Date) throws {
        guard date.timeIntervalSinceReferenceDate.isFinite,
              date >= .distantPast, date <= .distantFuture else {
            throw BusinessError.invalidInput("Data non valida.")
        }
    }
    static func amount(_ amount: Int64, positive: Bool = false) throws {
        guard amount >= (positive ? 1 : 0) else {
            throw BusinessError.invalidInput("Inserire un importo \(positive ? "positivo" : "non negativo").")
        }
    }
    static func duration(_ minutes: Int) throws {
        guard (1...1440).contains(minutes) else {
            throw BusinessError.invalidInput("La durata deve essere compresa tra 1 e 1440 minuti.")
        }
    }
    static func packageCapacity(_ capacity: Int) throws {
        guard (1...1000).contains(capacity) else {
            throw BusinessError.invalidInput("Il numero di lezioni deve essere compreso tra 1 e 1000.")
        }
    }
    static func add(_ lhs: Int64, _ rhs: Int64) throws -> Int64 {
        let result = lhs.addingReportingOverflow(rhs)
        guard !result.overflow else { throw BusinessError.arithmeticOverflow }
        return result.partialValue
    }
}
