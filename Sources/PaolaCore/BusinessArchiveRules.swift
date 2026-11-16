import Foundation

/// Regole di coerenza per singola entità, condivise da `BusinessArchive.validate`
/// (validazione completa) e da `ScopedValidation` (validazione mirata del completamento).
/// Un'unica implementazione evita che le due validazioni divergano.
enum BusinessArchiveRules {
    typealias Session = BusinessArchive.SessionRecord
    typealias Participant = BusinessArchive.ParticipantRecord
    typealias Package = BusinessArchive.PackageRecord
    typealias Use = BusinessArchive.PackageUseRecord
    typealias Ledger = BusinessArchive.LedgerRecord
    typealias ExpenseRow = BusinessArchive.ExpenseRecord

    static func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw BusinessError.inconsistentData(message) }
    }

    static func checkExpiry(_ expiry: Date?, sessionDate: Date) throws {
        if let expiry {
            try require(Calendar.current.startOfDay(for: sessionDate) <= Calendar.current.startOfDay(for: expiry),
                        "Il pacchetto è scaduto alla data della lezione.")
        }
    }

    // MARK: Sessione

    static func session(_ session: Session, serviceIDs: Set<UUID>, participants: [Participant]) throws {
        try BusinessRules.date(session.startDate); try BusinessRules.date(session.createdAt)
        try BusinessRules.date(session.updatedAt); try BusinessRules.duration(session.durationMinutes)
        try BusinessRules.date(session.startDate.addingTimeInterval(Double(session.durationMinutes) * 60))
        try require(SessionStatus(rawValue: session.statusRaw) != nil, "Stato lezione non valido.")
        if let serviceID = session.serviceID {
            try require(serviceIDs.contains(serviceID), "Servizio della lezione mancante.")
        }
        try require(!participants.isEmpty && Set(participants.map(\.clientID)).count == participants.count,
                    "Una lezione richiede almeno un cliente, senza partecipanti duplicati.")
    }

    // MARK: Pacchetto

    static func package(_ package: Package, clientIDs: Set<UUID>) throws {
        try require(clientIDs.contains(package.clientID), "Cliente del pacchetto mancante.")
        // La capienza si valida solo per i pacchetti a lezioni; quelli a tempo sono illimitati.
        if PackageKind(rawValue: package.kindRaw) != .timed {
            try BusinessRules.packageCapacity(package.capacity)
        }
        try BusinessRules.amount(package.priceCents); try BusinessRules.date(package.purchasedOn)
        if let expiry = package.expiresOn {
            try BusinessRules.date(expiry)
            try require(Calendar.current.startOfDay(for: expiry) >= Calendar.current.startOfDay(for: package.purchasedOn),
                        "La scadenza precede l'acquisto.")
        }
    }

    static func packageCapacity(_ package: Package, usedCount: Int) throws {
        guard PackageKind(rawValue: package.kindRaw) != .timed else { return }
        try require(usedCount <= package.capacity, "Il pacchetto supera il numero di lezioni disponibili.")
    }

    // MARK: Partecipante

    static func participant(_ participant: Participant, session: Session?, package: Package?,
                            clientIDs: Set<UUID>) throws {
        try require(clientIDs.contains(participant.clientID), "Cliente della lezione mancante.")
        guard let session else {
            throw BusinessError.inconsistentData("Lezione del partecipante mancante.")
        }
        try BusinessRules.amount(participant.priceCents)
        if participant.packageID != nil {
            guard let package, package.clientID == participant.clientID else {
                throw BusinessError.inconsistentData("Pacchetto non appartenente al cliente.")
            }
            try checkExpiry(package.expiresOn, sessionDate: session.startDate)
        }
    }

    // MARK: Utilizzo pacchetto

    /// Ritorna la `sourceKey` logica (minuscola) dell'utilizzo.
    static func packageUse(_ use: Use, session: Session?, package: Package?,
                           sessionParticipants: [Participant]) throws -> String {
        try BusinessRules.date(use.createdAt)
        let source = BusinessRules.sessionSource(sessionID: use.sessionID, clientID: use.clientID)
        try require(use.sourceKey.lowercased() == source, "Origine utilizzo pacchetto non valida.")
        guard let package, package.clientID == use.clientID,
              let session, session.statusRaw == SessionStatus.completed.rawValue,
              sessionParticipants.contains(where: { $0.clientID == use.clientID && $0.packageID == use.packageID }) else {
            throw BusinessError.inconsistentData("Utilizzo pacchetto senza lezione completata o cliente valido.")
        }
        return source
    }

    static func registerUse(_ use: Use, source: String, into useSources: inout [String: Use]) throws {
        if let prior = useSources[source] {
            try require(prior.packageID == use.packageID, "Utilizzi duplicati incompatibili.")
        }
        useSources[source] = use
    }

    // MARK: Movimento

    /// Controlla il singolo movimento e ne ritorna il tipo.
    @discardableResult
    static func ledgerEntry(_ entry: Ledger, clientIDs: Set<UUID>) throws -> LedgerKind {
        try require(clientIDs.contains(entry.clientID), "Cliente del movimento mancante.")
        try BusinessRules.date(entry.date); try BusinessRules.date(entry.createdAt)
        try BusinessRules.amount(entry.amountCents, positive: entry.kindRaw != LedgerKind.charge.rawValue)
        guard let kind = LedgerKind(rawValue: entry.kindRaw), kind != .unknown,
              PaymentMethod(rawValue: entry.methodRaw) != nil else {
            throw BusinessError.inconsistentData("Tipo movimento o metodo non valido.")
        }
        try require(!entry.sourceKey.isEmpty, "Origine movimento mancante.")
        return kind
    }

    /// Movimenti con la stessa `sourceKey` (minuscola) devono avere gli stessi valori.
    static func registerSource(_ entry: Ledger, into sources: inout [String: Ledger]) throws {
        let key = entry.sourceKey.lowercased()
        if let previous = sources[key] {
            try require(previous.clientID == entry.clientID && previous.kindRaw == entry.kindRaw
                && previous.amountCents == entry.amountCents && previous.date == entry.date
                && previous.methodRaw == entry.methodRaw && previous.originalEntryID == entry.originalEntryID,
                "Movimenti con la stessa origine ma valori diversi.")
        } else {
            sources[key] = entry
        }
    }

    /// Legame di una rettifica con l'originale (o assenza di legame per gli altri tipi).
    static func adjustmentLink(_ entry: Ledger, kind: LedgerKind, original: Ledger?) throws {
        if kind == .refund || kind == .credit {
            guard let original, original.clientID == entry.clientID,
                  original.kindRaw == (kind == .refund ? LedgerKind.payment.rawValue : LedgerKind.charge.rawValue) else {
                throw BusinessError.inconsistentData("Rettifica senza movimento originale valido.")
            }
            try require(entry.date >= original.date, "La rettifica precede il movimento originale.")
        } else {
            try require(entry.originalEntryID == nil, "Riferimento originale non valido.")
        }
    }

    // MARK: Economia della lezione

    /// Coerenza tra lezione, partecipanti, movimenti (`sources`) e utilizzi (`useSources`).
    static func sessionEconomics(session: Session, participants: [Participant],
                                 sources: [String: Ledger], useSources: [String: Use]) throws {
        for participant in participants {
            let source = BusinessRules.sessionSource(sessionID: session.id, clientID: participant.clientID)
            if session.statusRaw == "completed" {
                if participant.packageID != nil {
                    try require(useSources[source] != nil && sources[source] == nil,
                                "La lezione a pacchetto richiede un solo utilizzo, senza addebito.")
                } else {
                    let incomeSource = BusinessRules.sessionIncomeSource(sessionID: session.id, clientID: participant.clientID)
                    guard let charge = sources[source] else {
                        throw BusinessError.inconsistentData("Addebito lezione mancante.")
                    }
                    try require(charge.kindRaw == "charge" && charge.clientID == participant.clientID
                        && charge.amountCents == participant.priceCents && charge.date == session.startDate,
                        "Addebito lezione incoerente.")
                    if let income = sources[incomeSource] {
                        try require(income.kindRaw == "payment" && income.clientID == participant.clientID
                            && income.amountCents == participant.priceCents
                            && PaymentMethod(rawValue: income.methodRaw) != nil,
                            "Incasso lezione incoerente.")
                    }
                }
            } else {
                try require(sources[source] == nil && useSources[source] == nil,
                            "Movimento presente per una lezione non completata.")
            }
        }
    }

    // MARK: Spesa

    static func expense(_ expense: ExpenseRow) throws {
        try require(!expense.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "Nome della spesa mancante.")
        try BusinessRules.date(expense.date); try BusinessRules.date(expense.createdAt)
        try BusinessRules.date(expense.updatedAt)
        try BusinessRules.amount(expense.amountCents)
        try require(ExpenseKind(rawValue: expense.kindRaw) != nil, "Tipo di spesa non valido.")
    }
}
