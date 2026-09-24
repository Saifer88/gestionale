import Foundation

public struct PaymentAllocation: Equatable {
    public let paymentID: UUID
    public let chargeID: UUID
    public let amountCents: Int64
    public init(paymentID: UUID, chargeID: UUID, amountCents: Int64) {
        self.paymentID = paymentID; self.chargeID = chargeID; self.amountCents = amountCents
    }
}

/// Un appuntamento completato con addebito non ancora saldato e il relativo residuo.
public struct UnpaidSession: Identifiable, Equatable {
    public let sessionID: UUID
    public let clientID: UUID
    public let clientName: String
    public let date: Date
    public let serviceName: String
    public let residualCents: Int64
    public var id: UUID { sessionID }
    public init(sessionID: UUID, clientID: UUID, clientName: String, date: Date,
                serviceName: String, residualCents: Int64) {
        self.sessionID = sessionID; self.clientID = clientID; self.clientName = clientName
        self.date = date; self.serviceName = serviceName; self.residualCents = residualCents
    }
}

/// Ripartizione fiscale degli incassi di un periodo (importi in centesimi).
public struct TaxBreakdown: Equatable {
    public let blackCents: Int64
    public let whiteCents: Int64
    public let inpsCents: Int64
    public let taxCents: Int64
    public let netCents: Int64
    public var totalCents: Int64 { blackCents + whiteCents }
    public init(blackCents: Int64, whiteCents: Int64, inpsCents: Int64, taxCents: Int64, netCents: Int64) {
        self.blackCents = blackCents; self.whiteCents = whiteCents
        self.inpsCents = inpsCents; self.taxCents = taxCents; self.netCents = netCents
    }

    // MARK: - Spiegazioni (tooltip su hover): operazioni una per riga.

    /// Base imponibile del bianco dopo la rimozione del 4% (centesimi).
    public var whiteBaseCents: Int64 {
        var input = Decimal(whiteCents) * Decimal(string: "0.96")!
        var rounded = Decimal()
        NSDecimalRound(&rounded, &input, 0, .plain)
        return NSDecimalNumber(decimal: rounded).int64Value
    }
    /// Imponibile INPS (base × 0,78), centesimi.
    private var imponibileCents: Int64 {
        var input = Decimal(whiteCents) * Decimal(string: "0.96")! * Decimal(string: "0.78")!
        var rounded = Decimal()
        NSDecimalRound(&rounded, &input, 0, .plain)
        return NSDecimalNumber(decimal: rounded).int64Value
    }

    // Ogni riga tooltip ha 3 colonne separate da "\t": operatore, descrizione, formula/valore.
    // Una riga con operatore "=" è il totale (mostrato in grassetto).

    /// Intestazione INPS: operazioni con formule generiche.
    public static var inpsFormula: String {
        [
            "\tBianchi\t",
            "-\trivalsa INPS\tBianchi × 4%",
            "×\tcoefficiente redditività\t(Bianchi − Rivalsa Inps) × 78%",
            "×\tinps\t(Bianchi − Rivalsa Inps) × Coeff. redditività × 26,07%"
        ].joined(separator: "\n")
    }
    /// Intestazione Imposte.
    public static var taxFormula: String {
        [
            "\tBianchi\t",
            "-\trivalsa INPS\tBianchi × 4%",
            "×\tcoefficiente redditività\t(Bianchi − Rivalsa Inps) × 78%",
            "-\tinps\t(Bianchi − Rivalsa Inps) × Coeff. redditività × 26,07%",
            "×\timposte\t(imponibile − Inps) × 5%"
        ].joined(separator: "\n")
    }
    /// Intestazione Netto.
    public static var netFormula: String {
        [
            "\tNeri\t",
            "+\tBianchi\t",
            "-\trivalsa INPS\tBianchi × 4%",
            "-\tinps\t",
            "-\timposte\t",
            "-\tspese\t"
        ].joined(separator: "\n")
    }

    /// Passaggi reali per la cella INPS. Totale in grassetto (operatore "=").
    public var inpsSteps: String {
        let rivalsa = whiteCents - whiteBaseCents
        return [
            "\tBianchi\t\(Money.format(whiteCents))",
            "-\trivalsa INPS\t\(Money.format(rivalsa))",
            "×\tcoefficiente redditività\t\(Money.format(imponibileCents))",
            "×\tinps\t\(Money.format(inpsCents))",
            "=\t\t\(Money.format(inpsCents))"
        ].joined(separator: "\n")
    }
    /// Passaggi reali per la cella imposte.
    public var taxSteps: String {
        let rivalsa = whiteCents - whiteBaseCents
        return [
            "\tBianchi\t\(Money.format(whiteCents))",
            "-\trivalsa INPS\t\(Money.format(rivalsa))",
            "×\tcoefficiente redditività\t\(Money.format(imponibileCents))",
            "-\tinps\t\(Money.format(inpsCents))",
            "×\timposte\t\(Money.format(taxCents))",
            "=\t\t\(Money.format(taxCents))"
        ].joined(separator: "\n")
    }
    /// Passaggi reali per la cella netto. Le spese del periodo sono già incluse nel netto.
    public var netSteps: String {
        let senzaSpese = blackCents + whiteBaseCents - inpsCents - taxCents
        let speseCents = senzaSpese - netCents
        return [
            "\tNeri\t\(Money.format(blackCents))",
            "+\tBianchi\t\(Money.format(whiteCents))",
            "-\trivalsa INPS\t\(Money.format(whiteCents - whiteBaseCents))",
            "-\tinps\t\(Money.format(inpsCents))",
            "-\timposte\t\(Money.format(taxCents))",
            "-\tspese\t\(Money.format(speseCents))",
            "=\t\t\(Money.format(netCents))"
        ].joined(separator: "\n")
    }
}

/// Riepilogo per cliente delle lezioni completate non pagate.
public struct UnpaidClientSummary: Identifiable, Equatable {
    public let clientID: UUID
    public let clientName: String
    public let sessionCount: Int
    public let residualCents: Int64
    public var id: UUID { clientID }
    public init(clientID: UUID, clientName: String, sessionCount: Int, residualCents: Int64) {
        self.clientID = clientID; self.clientName = clientName
        self.sessionCount = sessionCount; self.residualCents = residualCents
    }
}

public struct AccountStatement {
    public let openingBalance: Int64
    public let closingBalance: Int64
    public let entries: [LedgerEntry]
    public let chargedCents: Int64
    public let paidCents: Int64
    public let refundedCents: Int64
    public let creditedCents: Int64
}

public struct BusinessStatistics {
    public let receivedCents: Int64
    public let refundedCents: Int64
    public let workedMinutes: Double
    public let completedSessions: Int
    public let popularHours: [Int: Int]
    public let hourlyIncomeCents: Double?
}

public enum BusinessReports {
    public static func integrityWarnings(entries: [LedgerEntry], packages: [LessonPackage],
                                         uses: [PackageUse]) -> [String] {
        var warnings = Set<String>()
        func warn(_ message: String) { warnings.insert(message) }
        func duplicateIDs<T: AnyObject>(_ rows: [T], id: (T) -> UUID) -> Bool {
            var seen: [UUID: ObjectIdentifier] = [:]
            for row in rows {
                let identity = ObjectIdentifier(row)
                if let previous = seen[id(row)], previous != identity { return true }
                seen[id(row)] = identity
            }
            return false
        }
        if duplicateIDs(entries, id: { $0.id }) { warn("Esistono movimenti distinti con lo stesso identificativo.") }
        if duplicateIDs(packages, id: { $0.id }) { warn("Esistono pacchetti distinti con lo stesso identificativo.") }
        if duplicateIDs(uses, id: { $0.id }) { warn("Esistono utilizzi distinti con lo stesso identificativo.") }
        var entrySources: [String: LedgerEntry] = [:]
        var entriesByID: [UUID: LedgerEntry] = [:]
        for entry in entries {
            entriesByID[entry.id] = entry
            if entry.kind == .unknown { warn("Sono presenti movimenti di tipo sconosciuto: i saldi non sono affidabili.") }
            if PaymentMethod(rawValue: entry.methodRaw) == nil { warn("Sono presenti metodi di pagamento sconosciuti.") }
            if entry.amountCents < 0 || (entry.kind != .charge && entry.amountCents == 0) {
                warn("Sono presenti importi non validi.")
            }
            if (try? BusinessRules.date(entry.date)) == nil || (try? BusinessRules.date(entry.createdAt)) == nil {
                warn("Sono presenti date di movimento non valide.")
            }
            let source = entry.sourceKey.lowercased()
            if source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                warn("Sono presenti movimenti senza origine identificabile.")
            } else if let previous = entrySources[source] {
                if previous.amountCents != entry.amountCents || previous.kindRaw != entry.kindRaw
                    || previous.clientID != entry.clientID || previous.originalEntryID != entry.originalEntryID
                    || previous.methodRaw != entry.methodRaw || previous.date != entry.date {
                    warn("Movimenti con la stessa origine hanno valori incompatibili: verificare prima di registrare altre operazioni.")
                }
            } else {
                entrySources[source] = entry
            }
        }
        let canonical = canonicalEntries(entries)
        for entry in canonical {
            let source = entry.sourceKey.lowercased()
            if source.hasPrefix("income:") {
                let parts = source.split(separator: ":", omittingEmptySubsequences: false)
                let packageIncome = parts.count == 3 && parts[1] == "package"
                    && UUID(uuidString: String(parts[2])) != nil
                let sessionIncome = parts.count == 4 && parts[1] == "session"
                    && UUID(uuidString: String(parts[2])) != nil && UUID(uuidString: String(parts[3])) == entry.clientID
                let chargeSource = parts.dropFirst(2).joined(separator: ":")
                // Il metodo di pagamento è ora selezionabile (contanti/Stripe/carta/bonifico):
                // non è più vincolato a "Altro". Restano validati origine e tipo.
                if !(packageIncome || sessionIncome) || entry.kind != .payment
                    || PaymentMethod(rawValue: entry.methodRaw) == nil {
                    warn("Un incasso automatico ha origine o metodo non validi.")
                }
                if let charge = entrySources[chargeSource] {
                    if charge.kind != .charge || charge.clientID != entry.clientID
                        || charge.amountCents != entry.amountCents || (packageIncome && charge.date != entry.date) {
                        warn("Un incasso automatico non corrisponde al relativo addebito.")
                    }
                } else {
                    warn("Un incasso automatico non ha il relativo addebito.")
                }
            }
            if entry.kind == .refund || entry.kind == .credit {
                guard let originalID = entry.originalEntryID, let original = entriesByID[originalID] else {
                    warn("Una rettifica fa riferimento a un movimento originale mancante.")
                    continue
                }
                if original.clientID != entry.clientID
                    || original.kind != (entry.kind == .refund ? .payment : .charge) {
                    warn("Una rettifica non corrisponde al tipo o al cliente del movimento originale.")
                }
                if entry.date < original.date { warn("Una rettifica precede la data del movimento originale.") }
            } else if entry.originalEntryID != nil {
                warn("Un movimento non di rettifica contiene un riferimento originale inatteso.")
            }
        }
        for original in canonical where original.kind == .payment || original.kind == .charge {
            let aliases = Set(entries.filter {
                $0.id == original.id || (!original.sourceKey.isEmpty && $0.sourceKey.lowercased() == original.sourceKey.lowercased())
            }.map(\.id))
            let adjustments = canonical.filter { $0.originalEntryID.map(aliases.contains) == true }
                .reduce(Decimal(0)) { $0 + Decimal($1.amountCents) }
            if adjustments > Decimal(original.amountCents) {
                warn("I rimborsi o le note di credito superano l'importo originale.")
            }
        }
        var debitTotal = Decimal(0)
        var creditTotal = Decimal(0)
        for entry in canonical {
            switch entry.kind {
            case .charge, .refund: debitTotal += Decimal(entry.amountCents)
            case .payment, .credit: creditTotal += Decimal(entry.amountCents)
            case .unknown: break
            }
        }
        if debitTotal > Decimal(Int64.max) || creditTotal > Decimal(Int64.max) {
            warn("I totali monetari superano il limite supportato.")
        }
        var packagesByID: [UUID: LessonPackage] = [:]
        for package in packages {
            packagesByID[package.id] = package
            if (package.kind != .timed && (try? BusinessRules.packageCapacity(package.capacity)) == nil)
                || package.priceCents < 0 {
                warn("Un pacchetto ha capienza o prezzo non validi.")
            }
            let source = BusinessRules.packageSource(package.id)
            if let charge = entrySources[source] {
                if charge.kind != .charge || charge.clientID != package.clientID
                    || charge.amountCents != package.priceCents || charge.date != package.purchasedOn {
                    warn("L'addebito di un pacchetto non corrisponde ai dati dell'acquisto.")
                }
            } else {
                warn("Un pacchetto non ha il relativo addebito di acquisto.")
            }
        }
        var useSources: [String: PackageUse] = [:]
        var logicalUses: [String: PackageUse] = [:]
        for use in uses {
            let logicalKey = BusinessRules.sessionSource(sessionID: use.sessionID, clientID: use.clientID)
            if use.sourceKey.lowercased() != logicalKey {
                warn("Un utilizzo pacchetto ha un'origine non coerente con lezione e cliente.")
            }
            if let previous = useSources[use.sourceKey.lowercased()],
               previous.packageID != use.packageID || previous.clientID != use.clientID || previous.sessionID != use.sessionID {
                warn("Utilizzi con la stessa origine fanno riferimento a pacchetti, lezioni o clienti differenti.")
            }
            useSources[use.sourceKey.lowercased()] = use
            if let previous = logicalUses[logicalKey], previous.packageID != use.packageID {
                warn("La stessa lezione del cliente risulta consumata da pacchetti differenti.")
            }
            logicalUses[logicalKey] = use
            if let package = packagesByID[use.packageID] {
                if package.clientID != use.clientID { warn("Un utilizzo pacchetto appartiene a un cliente diverso dall'acquirente.") }
            } else {
                warn("Un utilizzo fa riferimento a un pacchetto mancante.")
            }
        }
        for package in packages where package.kind != .timed {
            let count = Set(uses.filter { $0.packageID == package.id }.map {
                BusinessRules.sessionSource(sessionID: $0.sessionID, clientID: $0.clientID)
            }).count
            if count > package.capacity {
                warn("Un pacchetto supera il numero di lezioni disponibili: possibile conflitto di sincronizzazione.")
            }
        }
        return warnings.sorted()
    }

    public static func balance(clientID: UUID, entries: [LedgerEntry]) -> Int64 {
        net(canonicalEntries(entries).filter { $0.clientID == clientID })
    }

    /// Sintesi per la sezione "Saldi" del cliente.
    public struct ClientTotals: Equatable {
        public let completedCount: Int
        public let unpaidCount: Int
        public let totalValueCents: Int64
        public init(completedCount: Int, unpaidCount: Int, totalValueCents: Int64) {
            self.completedCount = completedCount
            self.unpaidCount = unpaidCount
            self.totalValueCents = totalValueCents
        }
    }

    /// Contatori del cliente:
    /// - `completedCount`: appuntamenti completati (in cui il cliente partecipa).
    /// - `unpaidCount`: appuntamenti completati con almeno una quota del cliente non
    ///   pagata (`isPaid == false` sul partecipante senza pacchetto).
    /// - `totalValueCents`: somma delle quote del cliente di TUTTI i suoi appuntamenti
    ///   (ogni stato, deduplicati per partecipante) PIÙ i prezzi di tutti i suoi pacchetti.
    public static func clientTotals(clientID: UUID, sessions: [TrainingSession],
                                    participants: [SessionParticipant],
                                    packages: [LessonPackage]) -> ClientTotals {
        let clientSessionIDs = Set(participants.filter { $0.clientID == clientID }.map(\.sessionID))
        let clientSessions = sessions.filter { clientSessionIDs.contains($0.id) }
        let completed = clientSessions.filter { $0.status == .completed }
        let completedCount = completed.count
        // Non pagato: il cliente ha, in quella sessione, almeno un partecipante senza
        // pacchetto con isPaid == false (il flag ora vive sul partecipante, non sulla sessione).
        let unpaidCount = completed.filter { session in
            participants.contains { $0.sessionID == session.id && $0.clientID == clientID
                && $0.packageID == nil && !$0.isPaid }
        }.count

        // Quote del cliente su tutti gli appuntamenti (dedup per partecipante).
        var seen = Set<UUID>()
        let appointmentsValue = participants
            .filter { $0.clientID == clientID }
            .filter { seen.insert($0.id).inserted }
            .reduce(Int64(0)) { saturatedAdd($0, max(0, $1.priceCents)) }
        // Prezzi di tutti i pacchetti del cliente.
        let packagesValue = packages
            .filter { $0.clientID == clientID }
            .reduce(Int64(0)) { saturatedAdd($0, max(0, $1.priceCents)) }

        return ClientTotals(completedCount: completedCount, unpaidCount: unpaidCount,
                            totalValueCents: saturatedAdd(appointmentsValue, packagesValue))
    }

    /// Importo "da incassare" di un appuntamento per un cliente: il prezzo concordato
    /// dei soli partecipanti senza pacchetto e NON pagati (le lezioni coperte da
    /// pacchetto, o già pagate, non hanno importo da incassare). Somma se il cliente
    /// compare più volte (deduplicato).
    private static func sessionDueCents(sessionID: UUID, clientID: UUID,
                                        participants: [SessionParticipant]) -> Int64 {
        var seen = Set<UUID>()
        return participants
            .filter { $0.sessionID == sessionID && $0.clientID == clientID
                && $0.packageID == nil && !$0.isPaid }
            .filter { seen.insert($0.id).inserted }
            .reduce(Int64(0)) { saturatedAdd($0, max(0, $1.priceCents)) }
    }

    /// Appuntamenti completati con almeno una quota NON pagata (`isPaid == false` sul
    /// partecipante senza pacchetto) di un cliente, con l'importo da incassare di
    /// ciascuno. Il "pagato" è il flag manuale del partecipante, non un calcolo dai
    /// movimenti. Ordinati per data.
    public static func unpaidCompletedSessions(clientID: UUID, sessions: [TrainingSession],
                                               participants: [SessionParticipant]) -> [UnpaidSession] {
        let clientSessionIDs = Set(participants
            .filter { $0.clientID == clientID && $0.packageID == nil && !$0.isPaid }
            .map(\.sessionID))
        var result: [UnpaidSession] = []
        for session in sessions
        where session.status == .completed && clientSessionIDs.contains(session.id) {
            let due = sessionDueCents(sessionID: session.id, clientID: clientID, participants: participants)
            // Escludi le lezioni senza importo da incassare (interamente coperte da
            // pacchetto, già pagate o a prezzo zero): non sono un debito del cliente.
            guard due > 0 else { continue }
            let name = participants.first { $0.sessionID == session.id && $0.clientID == clientID }?.clientName ?? ""
            result.append(UnpaidSession(sessionID: session.id, clientID: clientID,
                                        clientName: name, date: session.startDate,
                                        serviceName: session.serviceName, residualCents: due))
        }
        return result.sorted { $0.date < $1.date }
    }

    /// Clienti con appuntamenti completati con quote non pagate e importo totale da
    /// incassare, ordinati per importo decrescente. Utile per la panoramica.
    public static func unpaidCompletedByClient(sessions: [TrainingSession],
                                               participants: [SessionParticipant]) -> [UnpaidClientSummary] {
        let completedIDs = Set(sessions.filter { $0.status == .completed }.map(\.id))
        let clientIDs = Set(participants
            .filter { completedIDs.contains($0.sessionID) && $0.packageID == nil && !$0.isPaid }
            .map(\.clientID))
        var summaries: [UnpaidClientSummary] = []
        for clientID in clientIDs {
            let unpaid = unpaidCompletedSessions(clientID: clientID, sessions: sessions, participants: participants)
            guard !unpaid.isEmpty else { continue }
            let total = unpaid.reduce(Int64(0)) { saturatedAdd($0, $1.residualCents) }
            summaries.append(UnpaidClientSummary(clientID: clientID, clientName: unpaid.first?.clientName ?? "",
                                                 sessionCount: unpaid.count, residualCents: total))
        }
        return summaries.sorted {
            $0.residualCents == $1.residualCents
                ? $0.clientName.localizedStandardCompare($1.clientName) == .orderedAscending
                : $0.residualCents > $1.residualCents
        }
    }

    public static func remaining(package: LessonPackage, uses: [PackageUse]) -> Int {
        max(0, package.capacity - used(package: package, uses: uses))
    }

    /// Numero di lezioni effettivamente utilizzate dal pacchetto (dedup per sessione).
    public static func used(package: LessonPackage, uses: [PackageUse]) -> Int {
        let keys = Set(uses.filter { $0.packageID == package.id }.map {
            BusinessRules.sessionSource(sessionID: $0.sessionID, clientID: $0.clientID)
        })
        return min(max(0, package.capacity), keys.count)
    }

    public static func statement(clientID: UUID?, from: Date, to: Date,
                                 entries: [LedgerEntry]) -> AccountStatement {
        let relevant = canonicalEntries(entries).filter { clientID == nil || $0.clientID == clientID }
        let period = relevant.filter { $0.date >= from && $0.date < to }
        let opening = relevant.filter { $0.date < from }
        let closing = relevant.filter { $0.date < max(from, to) }
        return AccountStatement(
            openingBalance: net(opening), closingBalance: net(closing), entries: period,
            chargedCents: total(period, .charge), paidCents: total(period, .payment),
            refundedCents: total(period, .refund), creditedCents: total(period, .credit)
        )
    }

    public static func allocations(clientID: UUID, entries: [LedgerEntry]) -> [PaymentAllocation] {
        let originals = entries.filter { $0.clientID == clientID }
        let entries = canonicalEntries(originals)
        func aliases(_ original: LedgerEntry) -> Set<UUID> {
            guard !original.sourceKey.isEmpty else { return [original.id] }
            return Set(originals.filter { $0.sourceKey.lowercased() == original.sourceKey.lowercased() }.map(\.id))
        }
        let charges = entries.filter { $0.kind == .charge }
        let payments = entries.filter { $0.kind == .payment }
        var chargeAmounts = charges.map { original in
            let ids = aliases(original)
            return max(0, original.amountCents - min(max(0, original.amountCents),
                total(entries.filter { $0.originalEntryID.map(ids.contains) == true }, .credit)))
        }
        var result: [PaymentAllocation] = []
        var chargeIndex = 0
        for payment in payments {
            let ids = aliases(payment)
            var available = max(0, payment.amountCents - min(max(0, payment.amountCents),
                total(entries.filter { $0.originalEntryID.map(ids.contains) == true }, .refund)))
            while available > 0 && chargeIndex < charges.count {
                let amount = min(available, chargeAmounts[chargeIndex])
                if amount > 0 {
                    result.append(PaymentAllocation(paymentID: payment.id,
                        chargeID: charges[chargeIndex].id, amountCents: amount))
                    available -= amount
                    chargeAmounts[chargeIndex] -= amount
                }
                if chargeAmounts[chargeIndex] == 0 { chargeIndex += 1 }
            }
        }
        return result
    }

    public static func statistics(from: Date, to: Date, sessions: [TrainingSession],
                                  entries: [LedgerEntry]) -> BusinessStatistics {
        let cash = canonicalEntries(entries).filter { $0.date >= from && $0.date < to }
        let received = total(cash, .payment)
        let refunded = total(cash, .refund)
        var seen = Set<UUID>()
        let completed = sessions.filter {
            seen.insert($0.id).inserted && $0.statusRaw == SessionStatus.completed.rawValue
                && $0.startDate < to && $0.endDate > from && $0.endDate > $0.startDate && to > from
        }
        let intervals = completed.map { (max(from, $0.startDate), min(to, $0.endDate)) }
            .sorted { $0.0 < $1.0 }
        var seconds: Double = 0
        var mergedStart: Date?
        var mergedEnd: Date?
        for (start, end) in intervals {
            if let previousStart = mergedStart, let previousEnd = mergedEnd {
                if start <= previousEnd {
                    mergedEnd = max(previousEnd, end)
                } else {
                    seconds += previousEnd.timeIntervalSince(previousStart)
                    mergedStart = start; mergedEnd = end
                }
            } else {
                mergedStart = start; mergedEnd = end
            }
        }
        if let start = mergedStart, let end = mergedEnd { seconds += end.timeIntervalSince(start) }
        var hours: [Int: Int] = [:]
        for session in completed {
            hours[Calendar.current.component(.hour, from: session.startDate), default: 0] += 1
        }
        return BusinessStatistics(receivedCents: received, refundedCents: refunded,
            workedMinutes: seconds / 60, completedSessions: completed.count, popularHours: hours,
            hourlyIncomeCents: seconds > 0 ? (Double(received) - Double(refunded)) / (seconds / 3600) : nil)
    }

    /// Netto orario (centesimi per ora): incassi imputati diviso ore lavorate, sui soli
    /// appuntamenti completati con importo imputato > 0. Regole:
    /// - Quota di un partecipante senza pacchetto: il suo `priceCents` (se > 0).
    /// - Quota di un partecipante con pacchetto: prezzo del pacchetto diviso il numero
    ///   di lezioni (capienza) del pacchetto — la quota "per lezione".
    /// - Un appuntamento contribuisce con le proprie ore (durata) una sola volta se ha
    ///   almeno una quota imputata > 0; gli appuntamenti interamente a 0€ sono esclusi.
    /// Restituisce nil se non ci sono ore valide (nessun appuntamento idoneo).
    public static func netHourlyCents(sessions: [TrainingSession], participants: [SessionParticipant],
                                      packages: [LessonPackage]) -> Double? {
        let packageByID = Dictionary(packages.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var totalCents: Double = 0
        var totalHours: Double = 0
        var seenSessions = Set<UUID>()
        for session in sessions
        where session.statusRaw == SessionStatus.completed.rawValue
            && seenSessions.insert(session.id).inserted
            && session.durationMinutes > 0 {
            var sessionCents: Int64 = 0
            var seenParticipants = Set<UUID>()
            for participant in participants
            where participant.sessionID == session.id && seenParticipants.insert(participant.id).inserted {
                if let packageID = participant.packageID {
                    // Quota per lezione del pacchetto: prezzo / capienza (numero di lezioni).
                    if let package = packageByID[packageID], package.capacity > 0, package.priceCents > 0 {
                        sessionCents = saturatedAdd(sessionCents, package.priceCents / Int64(package.capacity))
                    }
                } else if participant.priceCents > 0 {
                    sessionCents = saturatedAdd(sessionCents, participant.priceCents)
                }
            }
            // Solo appuntamenti con importo imputato > 0 concorrono a incassi e ore.
            guard sessionCents > 0 else { continue }
            totalCents += Double(sessionCents)
            totalHours += Double(session.durationMinutes) / 60.0
        }
        guard totalHours > 0 else { return nil }
        return totalCents / totalHours
    }

    internal static func canonicalEntries(_ entries: [LedgerEntry]) -> [LedgerEntry] {
        var ids = Set<UUID>()
        var sources = Set<String>()
        return entries.sorted {
            if $0.date != $1.date { return $0.date < $1.date }
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.id.uuidString < $1.id.uuidString
        }.filter {
            guard ids.insert($0.id).inserted else { return false }
            return $0.sourceKey.isEmpty || sources.insert($0.sourceKey.lowercased()).inserted
        }
    }

    private static func total(_ entries: [LedgerEntry], _ kind: LedgerKind) -> Int64 {
        entries.filter { $0.kindRaw == kind.rawValue }.reduce(0) {
            saturatedAdd($0, max(0, $1.amountCents))
        }
    }

    private static func net(_ entries: [LedgerEntry]) -> Int64 {
        // Decimal keeps cancellation exact even when the intermediate sum exceeds Int64.
        let result = entries.reduce(Decimal(0)) { sum, entry in
            guard let kind = LedgerKind(rawValue: entry.kindRaw), kind != .unknown else { return sum }
            return sum + Decimal(entry.amountCents) * ((kind == .charge || kind == .refund) ? 1 : -1)
        }
        if result > Decimal(Int64.max) { return Int64.max }
        if result < Decimal(Int64.min) { return Int64.min }
        return NSDecimalNumber(decimal: result).int64Value
    }

    private static func saturatedAdd(_ lhs: Int64, _ rhs: Int64) -> Int64 {
        let result = lhs.addingReportingOverflow(rhs)
        return result.overflow ? Int64.max : result.partialValue
    }

    /// Ripartizione fiscale degli incassi netti di un periodo, separati in bianchi e
    /// neri secondo il contrassegno contabile della prestazione di origine.
    ///
    /// - Incassi neri/bianchi: pagamenti (al netto dei rimborsi collegati) la cui
    ///   prestazione di origine ha `isBlack` true/false. La prestazione è la sessione
    ///   (sourceKey `income:session:...`) o il pacchetto (sourceKey `income:package:...`).
    /// - baseBianchi = bianchi × 0,96 (si rimuove il 4% prima delle tasse)
    /// - inps = (baseBianchi × 0,78) × 0,2607
    /// - imposte = ((baseBianchi × 0,78) − inps) × 0,05
    /// - netto = neri + baseBianchi − (inps + imposte + spese)
    /// `expensesCents` sono le spese del periodo (già calcolate a monte). Gli importi
    /// sono in centesimi; le quote fiscali sono arrotondate al centesimo.
    public static func taxSummary(from: Date, to: Date, entries: [LedgerEntry],
                                  sessions: [TrainingSession], packages: [LessonPackage],
                                  expensesCents: Int64 = 0) -> TaxBreakdown {
        let canonical = canonicalEntries(entries)
        // Lookup per risalire dalla chiave d'incasso (sourceKey) al colore della
        // prestazione: la chiave sessione include il clientID, quindi indicizziamo per id.
        let sessionByID = Dictionary(sessions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let packageByID = Dictionary(packages.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        func isBlackForPayment(_ sourceKey: String) -> Bool? {
            let key = sourceKey.lowercased()
            let sessionPrefix = "income:session:"
            let packagePrefix = "income:package:"
            if key.hasPrefix(sessionPrefix) {
                let rest = key.dropFirst(sessionPrefix.count)
                let first = rest.split(separator: ":", omittingEmptySubsequences: false).first.map(String.init) ?? ""
                if let id = UUID(uuidString: first) { return sessionByID[id]?.isBlack }
            } else if key.hasPrefix(packagePrefix) {
                let rest = key.dropFirst(packagePrefix.count)
                let idString = String(rest)
                if let id = UUID(uuidString: idString) { return packageByID[id]?.isBlack }
            }
            return nil
        }

        // Rimborsi collegati a ciascun pagamento (per id del pagamento originale).
        var refundByPaymentID: [UUID: Int64] = [:]
        for entry in canonical where entry.kind == .refund {
            if let original = entry.originalEntryID {
                refundByPaymentID[original] = saturatedAdd(refundByPaymentID[original] ?? 0, max(0, entry.amountCents))
            }
        }

        var blackCents: Int64 = 0
        var whiteCents: Int64 = 0
        for payment in canonical
        where payment.kind == .payment && payment.date >= from && payment.date < to {
            let refunded = min(max(0, payment.amountCents), refundByPaymentID[payment.id] ?? 0)
            let netCents = max(0, payment.amountCents - refunded)
            guard netCents > 0 else { continue }
            // Colore dalla prestazione; se ignoto, considera bianco (prudenziale ai fini fiscali).
            let black = isBlackForPayment(payment.sourceKey) ?? false
            if black { blackCents = saturatedAdd(blackCents, netCents) }
            else { whiteCents = saturatedAdd(whiteCents, netCents) }
        }

        // Dal bianco si rimuove il 4% prima di calcolare INPS e imposte.
        let whiteBase = Decimal(whiteCents) * Decimal(string: "0.96")!
        let whiteBaseCents = roundedCents(whiteBase)
        let whiteImponibile = whiteBase * Decimal(string: "0.78")!
        let inps = whiteImponibile * Decimal(string: "0.2607")!
        let imposte = (whiteImponibile - inps) * Decimal(string: "0.05")!
        let inpsCents = roundedCents(inps)
        let imposteCents = roundedCents(imposte)
        let netCents = blackCents + whiteBaseCents - (inpsCents + imposteCents + max(0, expensesCents))

        return TaxBreakdown(blackCents: blackCents, whiteCents: whiteCents,
                            inpsCents: inpsCents, taxCents: imposteCents, netCents: netCents)
    }

    /// Arrotonda un importo in centesimi (Decimal) all'intero più vicino, saturando su Int64.
    private static func roundedCents(_ value: Decimal) -> Int64 {
        var input = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &input, 0, .plain)
        if rounded > Decimal(Int64.max) { return Int64.max }
        if rounded < Decimal(Int64.min) { return Int64.min }
        return NSDecimalNumber(decimal: rounded).int64Value
    }
}
