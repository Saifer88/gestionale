import Foundation

public struct PaymentAllocation: Equatable {
    public let paymentID: UUID
    public let chargeID: UUID
    public let amountCents: Int64
    public init(paymentID: UUID, chargeID: UUID, amountCents: Int64) {
        self.paymentID = paymentID; self.chargeID = chargeID; self.amountCents = amountCents
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
                if !(packageIncome || sessionIncome) || entry.kind != .payment || entry.method != .other {
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
            if package.capacity != 10 || package.priceCents < 0 { warn("Un pacchetto ha capienza o prezzo non validi.") }
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
        for package in packages {
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

    public static func remaining(package: LessonPackage, uses: [PackageUse]) -> Int {
        let keys = Set(uses.filter { $0.packageID == package.id }.map {
            BusinessRules.sessionSource(sessionID: $0.sessionID, clientID: $0.clientID)
        })
        return max(0, package.capacity - min(max(0, package.capacity), keys.count))
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
}
