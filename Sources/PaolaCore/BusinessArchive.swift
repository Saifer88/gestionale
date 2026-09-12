import Foundation
import SwiftData

public struct BusinessArchive: Codable, Equatable {
    public var services: [ServiceRecord] = []
    public var rates: [RateRecord] = []
    public var preferences: [PreferenceRecord] = []
    public var sessions: [SessionRecord] = []
    public var participants: [ParticipantRecord] = []
    public var packages: [PackageRecord] = []
    public var packageUses: [PackageUseRecord] = []
    public var ledgerEntries: [LedgerRecord] = []
    public var blocks: [BlockRecord] = []
    public var invoices: [InvoiceRecord] = []

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case services, rates, preferences, sessions, participants, packages, packageUses, ledgerEntries, blocks, invoices
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        services = try values.decode([ServiceRecord].self, forKey: .services)
        rates = try values.decodeIfPresent([RateRecord].self, forKey: .rates) ?? []
        preferences = try values.decodeIfPresent([PreferenceRecord].self, forKey: .preferences) ?? []
        sessions = try values.decode([SessionRecord].self, forKey: .sessions)
        participants = try values.decode([ParticipantRecord].self, forKey: .participants)
        packages = try values.decode([PackageRecord].self, forKey: .packages)
        packageUses = try values.decode([PackageUseRecord].self, forKey: .packageUses)
        ledgerEntries = try values.decode([LedgerRecord].self, forKey: .ledgerEntries)
        blocks = try values.decode([BlockRecord].self, forKey: .blocks)
        invoices = try values.decodeIfPresent([InvoiceRecord].self, forKey: .invoices) ?? []
    }

    public var recordCount: Int {
        services.count + rates.count + sessions.count + participants.count + packages.count
            + packageUses.count + ledgerEntries.count + blocks.count + preferences.count + invoices.count
    }

    public func canonicalized() -> BusinessArchive {
        var archive = self
        archive.services.sort { $0.id.uuidString < $1.id.uuidString }
        archive.rates.sort { $0.id.uuidString < $1.id.uuidString }
        archive.preferences.sort { $0.id.uuidString < $1.id.uuidString }
        archive.sessions.sort { $0.id.uuidString < $1.id.uuidString }
        archive.participants.sort { $0.id.uuidString < $1.id.uuidString }
        archive.packages.sort { $0.id.uuidString < $1.id.uuidString }
        archive.packageUses.sort { $0.id.uuidString < $1.id.uuidString }
        archive.ledgerEntries.sort { $0.id.uuidString < $1.id.uuidString }
        archive.blocks.sort { $0.id.uuidString < $1.id.uuidString }
        archive.invoices.sort { $0.id.uuidString < $1.id.uuidString }
        return archive
    }

    @MainActor
    public static func capture(context: ModelContext) throws -> BusinessArchive {
        var archive = BusinessArchive()
        archive.services = try context.fetch(FetchDescriptor<TrainingService>()).map(ServiceRecord.init)
        archive.rates = try context.fetch(FetchDescriptor<ServiceRate>()).map(RateRecord.init)
        archive.preferences = try context.fetch(FetchDescriptor<ClientAppointmentPreference>()).map(PreferenceRecord.init)
        archive.sessions = try context.fetch(FetchDescriptor<TrainingSession>()).map(SessionRecord.init)
        archive.participants = try context.fetch(FetchDescriptor<SessionParticipant>()).map(ParticipantRecord.init)
        archive.packages = try context.fetch(FetchDescriptor<LessonPackage>()).map(PackageRecord.init)
        archive.packageUses = try context.fetch(FetchDescriptor<PackageUse>()).map(PackageUseRecord.init)
        archive.ledgerEntries = try context.fetch(FetchDescriptor<LedgerEntry>()).map(LedgerRecord.init)
        archive.blocks = try context.fetch(FetchDescriptor<Unavailability>()).map(BlockRecord.init)
        archive.invoices = try context.fetch(FetchDescriptor<Invoice>()).map(InvoiceRecord.init)
        return archive.canonicalized()
    }

    public func validate(clientIDs: Set<UUID>) throws {
        try unique(services.map(\.id)); try unique(rates.map(\.id)); try unique(sessions.map(\.id))
        try unique(participants.map(\.id)); try unique(packages.map(\.id))
        try unique(packageUses.map(\.id)); try unique(ledgerEntries.map(\.id)); try unique(blocks.map(\.id))
        try unique(preferences.map(\.id)); try unique(preferences.map(\.clientID))
        try unique(invoices.map(\.id))
        let serviceIDs = Set(services.map(\.id))
        let sessionMap = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
        let packageMap = Dictionary(uniqueKeysWithValues: packages.map { ($0.id, $0) })
        let entryMap = Dictionary(uniqueKeysWithValues: ledgerEntries.map { ($0.id, $0) })
        for preference in preferences {
            try require(clientIDs.contains(preference.clientID), "Cliente delle preferenze mancante.")
            if let serviceID = preference.serviceID {
                try require(serviceIDs.contains(serviceID), "Servizio delle preferenze mancante.")
            }
            if let rateID = preference.rateID, let rate = rates.first(where: { $0.id == rateID }) {
                try require(rate.serviceID == preference.serviceID, "Tariffa delle preferenze di un altro servizio.")
            }
            if let packageID = preference.packageID, let package = packageMap[packageID] {
                try require(package.clientID == preference.clientID, "Pacchetto delle preferenze di un altro cliente.")
            }
            try require((0...23).contains(preference.preferredHour) && (0...59).contains(preference.preferredMinute),
                        "Orario delle preferenze non valido.")
            try BusinessRules.date(preference.updatedAt)
            try BusinessRules.amount(preference.priceCents)
            try BusinessRules.duration(preference.durationMinutes)
        }
        for service in services {
            try require(!service.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "Nome servizio mancante.")
            try BusinessRules.duration(service.durationMinutes); try BusinessRules.amount(service.priceCents)
            try BusinessRules.date(service.updatedAt)
        }
        var tariffNames: [UUID: Set<String>] = [:]
        for rate in rates {
            try require(serviceIDs.contains(rate.serviceID), "Servizio della tariffa mancante.")
            let name = TextNormalization.key(rate.name)
            try require(!name.isEmpty && tariffNames[rate.serviceID, default: []].insert(name).inserted,
                        "Nomi delle tariffe mancanti o duplicati.")
            try BusinessRules.amount(rate.priceCents)
            try require(rate.sortOrder >= 0, "Ordine della tariffa non valido.")
        }
        for session in sessions {
            try BusinessRules.date(session.startDate); try BusinessRules.date(session.createdAt)
            try BusinessRules.date(session.updatedAt); try BusinessRules.duration(session.durationMinutes)
            try BusinessRules.date(session.startDate.addingTimeInterval(Double(session.durationMinutes) * 60))
            try require(SessionStatus(rawValue: session.statusRaw) != nil, "Stato lezione non valido.")
            if let serviceID = session.serviceID {
                try require(serviceIDs.contains(serviceID), "Servizio della lezione mancante.")
            }
            let pair = participants.filter { $0.sessionID == session.id }
            try require(!pair.isEmpty && Set(pair.map(\.clientID)).count == pair.count,
                        "Una lezione richiede almeno un cliente, senza partecipanti duplicati.")
        }
        for package in packages {
            try require(clientIDs.contains(package.clientID), "Cliente del pacchetto mancante.")
            try BusinessRules.packageCapacity(package.capacity)
            try BusinessRules.amount(package.priceCents); try BusinessRules.date(package.purchasedOn)
            if let expiry = package.expiresOn {
                try BusinessRules.date(expiry)
                try require(Calendar.current.startOfDay(for: expiry) >= Calendar.current.startOfDay(for: package.purchasedOn),
                            "La scadenza precede l'acquisto.")
            }
        }
        for participant in participants {
            try require(clientIDs.contains(participant.clientID), "Cliente della lezione mancante.")
            guard let session = sessionMap[participant.sessionID] else {
                throw BusinessError.inconsistentData("Lezione del partecipante mancante.")
            }
            try BusinessRules.amount(participant.priceCents)
            if let packageID = participant.packageID {
                guard let package = packageMap[packageID], package.clientID == participant.clientID else {
                    throw BusinessError.inconsistentData("Pacchetto non appartenente al cliente.")
                }
                try checkExpiry(package.expiresOn, sessionDate: session.startDate)
            }
        }
        var useSources: [String: PackageUseRecord] = [:]
        for use in packageUses {
            try BusinessRules.date(use.createdAt)
            let source = BusinessRules.sessionSource(sessionID: use.sessionID, clientID: use.clientID)
            try require(use.sourceKey.lowercased() == source, "Origine utilizzo pacchetto non valida.")
            guard let package = packageMap[use.packageID],
                  package.clientID == use.clientID,
                  let session = sessionMap[use.sessionID], session.statusRaw == SessionStatus.completed.rawValue,
                  participants.contains(where: { $0.sessionID == use.sessionID && $0.clientID == use.clientID && $0.packageID == use.packageID }) else {
                throw BusinessError.inconsistentData("Utilizzo pacchetto senza lezione completata o cliente valido.")
            }
            if let prior = useSources[source] {
                try require(prior.packageID == use.packageID, "Utilizzi duplicati incompatibili.")
            }
            useSources[source] = use
        }
        for package in packages {
            try require(useSources.values.filter { $0.packageID == package.id }.count <= package.capacity,
                        "Il pacchetto supera il numero di lezioni disponibili.")
        }
        var sources: [String: LedgerRecord] = [:]
        for entry in ledgerEntries {
            try require(clientIDs.contains(entry.clientID), "Cliente del movimento mancante.")
            try BusinessRules.date(entry.date); try BusinessRules.date(entry.createdAt)
            try BusinessRules.amount(entry.amountCents, positive: entry.kindRaw != LedgerKind.charge.rawValue)
            guard let kind = LedgerKind(rawValue: entry.kindRaw), kind != .unknown,
                  PaymentMethod(rawValue: entry.methodRaw) != nil else {
                throw BusinessError.inconsistentData("Tipo movimento o metodo non valido.")
            }
            try require(!entry.sourceKey.isEmpty, "Origine movimento mancante.")
            let key = entry.sourceKey.lowercased()
            if let previous = sources[key] {
                try require(previous.clientID == entry.clientID && previous.kindRaw == entry.kindRaw
                    && previous.amountCents == entry.amountCents && previous.date == entry.date
                    && previous.methodRaw == entry.methodRaw && previous.originalEntryID == entry.originalEntryID,
                    "Movimenti con la stessa origine ma valori diversi.")
            } else {
                sources[key] = entry
            }
            if kind == .refund || kind == .credit {
                guard let originalID = entry.originalEntryID, let original = entryMap[originalID],
                      original.clientID == entry.clientID,
                      original.kindRaw == (kind == .refund ? LedgerKind.payment.rawValue : LedgerKind.charge.rawValue) else {
                    throw BusinessError.inconsistentData("Rettifica senza movimento originale valido.")
                }
                try require(entry.date >= original.date, "La rettifica precede il movimento originale.")
            } else {
                try require(entry.originalEntryID == nil, "Riferimento originale non valido.")
            }
        }
        let canonical = Array(sources.values)
        var totals: [LedgerKind: Int64] = [:]
        for entry in canonical {
            guard let kind = LedgerKind(rawValue: entry.kindRaw) else { continue }
            totals[kind] = try BusinessRules.add(totals[kind, default: 0], entry.amountCents)
        }
        _ = try BusinessRules.add(totals[.charge, default: 0], totals[.refund, default: 0])
        _ = try BusinessRules.add(totals[.payment, default: 0], totals[.credit, default: 0])
        for original in canonical where original.kindRaw == "payment" || original.kindRaw == "charge" {
            // Refunds/credits may refer to either physical copy of the same logical source.
            let originalIDs = Set(ledgerEntries.filter { $0.sourceKey.lowercased() == original.sourceKey.lowercased() }.map(\.id))
            let adjusted = try canonical.filter { $0.originalEntryID.map(originalIDs.contains) == true }
                .reduce(Int64(0)) { try BusinessRules.add($0, $1.amountCents) }
            try require(adjusted <= original.amountCents, "Rettifiche superiori all'importo originale.")
        }
        var expectedChargeSources = Set<String>()
        var expectedIncomeSources = Set<String>()
        for package in packages {
            let source = BusinessRules.packageSource(package.id)
            let incomeSource = BusinessRules.packageIncomeSource(package.id)
            expectedIncomeSources.insert(incomeSource)
            expectedChargeSources.insert(source)
            guard let charge = sources[source] else {
                throw BusinessError.inconsistentData("Addebito acquisto pacchetto mancante.")
            }
            try require(charge.kindRaw == "charge" && charge.clientID == package.clientID
                && charge.amountCents == package.priceCents && charge.date == package.purchasedOn,
                "Addebito pacchetto incoerente.")
            if let income = sources[incomeSource] {
                try require(income.kindRaw == "payment" && income.clientID == package.clientID
                    && income.amountCents == package.priceCents && income.date == package.purchasedOn
                    && PaymentMethod(rawValue: income.methodRaw) != nil,
                    "Incasso pacchetto incoerente.")
            }
        }
        for session in sessions {
            for participant in participants where participant.sessionID == session.id {
                let source = BusinessRules.sessionSource(sessionID: session.id, clientID: participant.clientID)
                if session.statusRaw == "completed" {
                    if participant.packageID != nil {
                        try require(useSources[source] != nil && sources[source] == nil,
                                    "La lezione a pacchetto richiede un solo utilizzo, senza addebito.")
                    } else {
                        expectedChargeSources.insert(source)
                        let incomeSource = BusinessRules.sessionIncomeSource(sessionID: session.id, clientID: participant.clientID)
                        expectedIncomeSources.insert(incomeSource)
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
        for entry in canonical where entry.kindRaw == "charge" {
            try require(expectedChargeSources.contains(entry.sourceKey.lowercased()), "Addebito senza origine valida.")
        }
        for entry in canonical where entry.sourceKey.lowercased().hasPrefix("income:") {
            try require(expectedIncomeSources.contains(entry.sourceKey.lowercased()), "Incasso senza origine valida.")
        }
        for block in blocks {
            try BusinessRules.date(block.startDate); try BusinessRules.date(block.endDate)
            try require(block.startDate < block.endDate, "Intervallo indisponibilità non valido.")
            try require(!block.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "Titolo indisponibilità mancante.")
        }
        // La fattura è un documento informativo: si verificano solo integrità di base
        // (cliente esistente, date finite, importi non negativi, stato e metodo validi),
        // senza vincoli economici sui movimenti.
        for invoice in invoices {
            try require(clientIDs.contains(invoice.clientID), "Cliente della fattura mancante.")
            try BusinessRules.date(invoice.issueDate); try BusinessRules.date(invoice.createdAt)
            try BusinessRules.date(invoice.updatedAt)
            try BusinessRules.amount(invoice.taxableCents)
            try BusinessRules.amount(invoice.contributionCents)
            try BusinessRules.amount(invoice.totalCents)
            try require(InvoiceStatus(rawValue: invoice.statusRaw) != nil, "Stato fattura non valido.")
            try require(PaymentMethod(rawValue: invoice.paymentMethodRaw) != nil, "Metodo di pagamento della fattura non valido.")
        }
    }

    @MainActor
    public func insert(into context: ModelContext) throws {
        let clientIDs = Set(try context.fetch(FetchDescriptor<Client>()).map(\.id))
        try validate(clientIDs: clientIDs)
        let existing = try BusinessArchive.capture(context: context)
        try require(Set(existing.services.map(\.id)).isDisjoint(with: services.map(\.id))
            && Set(existing.rates.map(\.id)).isDisjoint(with: rates.map(\.id))
            && Set(existing.preferences.map(\.id)).isDisjoint(with: preferences.map(\.id))
            && Set(existing.sessions.map(\.id)).isDisjoint(with: sessions.map(\.id))
            && Set(existing.participants.map(\.id)).isDisjoint(with: participants.map(\.id))
            && Set(existing.packages.map(\.id)).isDisjoint(with: packages.map(\.id))
            && Set(existing.packageUses.map(\.id)).isDisjoint(with: packageUses.map(\.id))
            && Set(existing.ledgerEntries.map(\.id)).isDisjoint(with: ledgerEntries.map(\.id))
            && Set(existing.blocks.map(\.id)).isDisjoint(with: blocks.map(\.id))
            && Set(existing.invoices.map(\.id)).isDisjoint(with: invoices.map(\.id)),
            "L'archivio contiene identificativi già presenti.")
        var combined = existing
        combined.services += services; combined.sessions += sessions; combined.participants += participants
        combined.rates += rates
        combined.preferences += preferences
        combined.packages += packages; combined.packageUses += packageUses
        combined.ledgerEntries += ledgerEntries; combined.blocks += blocks
        combined.invoices += invoices
        try combined.validate(clientIDs: clientIDs)
        for record in services { context.insert(record.model()) }
        for record in rates { context.insert(record.model()) }
        for record in preferences { context.insert(record.model()) }
        for record in sessions { context.insert(record.model()) }
        for record in participants { context.insert(record.model()) }
        for record in packages { context.insert(record.model()) }
        for record in packageUses { context.insert(record.model()) }
        for record in ledgerEntries { context.insert(record.model()) }
        for record in blocks { context.insert(record.model()) }
        for record in invoices { context.insert(record.model()) }
    }

    private func unique(_ ids: [UUID]) throws {
        try require(Set(ids).count == ids.count, "Identificativi duplicati nell'archivio.")
    }
    private func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw BusinessError.inconsistentData(message) }
    }
    internal func checkExpiry(_ expiry: Date?, sessionDate: Date) throws {
        if let expiry {
            try require(Calendar.current.startOfDay(for: sessionDate) <= Calendar.current.startOfDay(for: expiry),
                        "Il pacchetto è scaduto alla data della lezione.")
        }
    }

    public struct ServiceRecord: Codable, Equatable {
        public var id: UUID
        public var name: String
        public var durationMinutes: Int
        public var priceCents: Int64
        public var isActive: Bool
        public var updatedAt: Date
        public init(_ value: TrainingService) {
            id = value.id; name = value.name; durationMinutes = value.durationMinutes
            priceCents = value.priceCents; isActive = value.isActive; updatedAt = value.updatedAt
        }
        internal func model() -> TrainingService {
            TrainingService(id: id, name: name, durationMinutes: durationMinutes, priceCents: priceCents,
                            isActive: isActive, updatedAt: updatedAt)
        }
    }
    public struct RateRecord: Codable, Equatable {
        public var id: UUID
        public var serviceID: UUID
        public var name: String
        public var priceCents: Int64
        public var sortOrder: Int

        public init(_ value: ServiceRate) {
            id = value.id; serviceID = value.serviceID; name = value.name
            priceCents = value.priceCents; sortOrder = value.sortOrder
        }

        internal func model() -> ServiceRate {
            ServiceRate(id: id, serviceID: serviceID, name: name, priceCents: priceCents, sortOrder: sortOrder)
        }
    }
    public struct PreferenceRecord: Codable, Equatable {
        public var id: UUID
        public var clientID: UUID
        public var serviceID: UUID?
        public var preferredHour: Int
        public var preferredMinute: Int
        public var rateID: UUID?
        public var priceCents: Int64
        public var packageID: UUID?
        public var durationMinutes: Int
        public var updatedAt: Date

        public init(_ value: ClientAppointmentPreference) {
            id = value.id; clientID = value.clientID; serviceID = value.serviceID
            preferredHour = value.preferredHour; preferredMinute = value.preferredMinute
            rateID = value.rateID; priceCents = value.priceCents; packageID = value.packageID
            durationMinutes = value.durationMinutes; updatedAt = value.updatedAt
        }

        internal func model() -> ClientAppointmentPreference {
            ClientAppointmentPreference(id: id, clientID: clientID, serviceID: serviceID,
                preferredHour: preferredHour, preferredMinute: preferredMinute, rateID: rateID,
                priceCents: priceCents, packageID: packageID, durationMinutes: durationMinutes,
                updatedAt: updatedAt)
        }
    }
    public struct SessionRecord: Codable, Equatable {
        public var id: UUID
        public var startDate: Date
        public var durationMinutes: Int
        public var serviceID: UUID?
        public var serviceName: String
        public var location: String
        public var notes: String
        public var statusRaw: String
        public var invoiceDate: Date?
        public var isPaid: Bool
        public var isBlack: Bool
        public var createdAt: Date
        public var updatedAt: Date
        public init(_ value: TrainingSession) {
            id = value.id; startDate = value.startDate; durationMinutes = value.durationMinutes
            serviceID = value.serviceID; serviceName = value.serviceName; location = value.location
            notes = value.notes; statusRaw = value.statusRaw; invoiceDate = value.invoiceDate
            isPaid = value.isPaid; isBlack = value.isBlack
            createdAt = value.createdAt; updatedAt = value.updatedAt
        }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(UUID.self, forKey: .id)
            startDate = try c.decode(Date.self, forKey: .startDate)
            durationMinutes = try c.decode(Int.self, forKey: .durationMinutes)
            serviceID = try c.decodeIfPresent(UUID.self, forKey: .serviceID)
            serviceName = try c.decode(String.self, forKey: .serviceName)
            location = try c.decode(String.self, forKey: .location)
            notes = try c.decode(String.self, forKey: .notes)
            statusRaw = try c.decode(String.self, forKey: .statusRaw)
            invoiceDate = try c.decodeIfPresent(Date.self, forKey: .invoiceDate)
            isPaid = try c.decodeIfPresent(Bool.self, forKey: .isPaid) ?? false
            isBlack = try c.decodeIfPresent(Bool.self, forKey: .isBlack) ?? false
            createdAt = try c.decode(Date.self, forKey: .createdAt)
            updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        }
        internal func model() -> TrainingSession {
            let value = TrainingSession(id: id, startDate: startDate, durationMinutes: durationMinutes,
                serviceID: serviceID, serviceName: serviceName, location: location, notes: notes,
                invoiceDate: invoiceDate, isPaid: isPaid, isBlack: isBlack,
                createdAt: createdAt, updatedAt: updatedAt)
            value.statusRaw = statusRaw
            return value
        }
    }
    public struct ParticipantRecord: Codable, Equatable {
        public var id: UUID
        public var sessionID: UUID
        public var clientID: UUID
        public var clientName: String
        public var priceCents: Int64
        public var packageID: UUID?
        public var paymentMethodRaw: String
        public init(_ value: SessionParticipant) {
            id = value.id; sessionID = value.sessionID; clientID = value.clientID
            clientName = value.clientName; priceCents = value.priceCents; packageID = value.packageID
            paymentMethodRaw = value.paymentMethodRaw
        }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(UUID.self, forKey: .id)
            sessionID = try c.decode(UUID.self, forKey: .sessionID)
            clientID = try c.decode(UUID.self, forKey: .clientID)
            clientName = try c.decode(String.self, forKey: .clientName)
            priceCents = try c.decode(Int64.self, forKey: .priceCents)
            packageID = try c.decodeIfPresent(UUID.self, forKey: .packageID)
            paymentMethodRaw = try c.decodeIfPresent(String.self, forKey: .paymentMethodRaw) ?? "cash"
        }
        internal func model() -> SessionParticipant {
            SessionParticipant(id: id, sessionID: sessionID, clientID: clientID,
                clientName: clientName, priceCents: priceCents, packageID: packageID,
                paymentMethod: PaymentMethod(rawValue: paymentMethodRaw) ?? .cash)
        }
    }
    public struct PackageRecord: Codable, Equatable {
        public var id: UUID
        public var clientID: UUID
        public var clientName: String
        public var purchasedOn: Date
        public var priceCents: Int64
        public var capacity: Int
        public var expiresOn: Date?
        public var notes: String
        public var paymentMethodRaw: String
        public var invoiceDate: Date?
        public var isBlack: Bool
        public init(_ value: LessonPackage) {
            id = value.id; clientID = value.clientID; clientName = value.clientName
            purchasedOn = value.purchasedOn; priceCents = value.priceCents; capacity = value.capacity
            expiresOn = value.expiresOn; notes = value.notes
            paymentMethodRaw = value.paymentMethodRaw; invoiceDate = value.invoiceDate
            isBlack = value.isBlack
        }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(UUID.self, forKey: .id)
            clientID = try c.decode(UUID.self, forKey: .clientID)
            clientName = try c.decode(String.self, forKey: .clientName)
            purchasedOn = try c.decode(Date.self, forKey: .purchasedOn)
            priceCents = try c.decode(Int64.self, forKey: .priceCents)
            capacity = try c.decode(Int.self, forKey: .capacity)
            expiresOn = try c.decodeIfPresent(Date.self, forKey: .expiresOn)
            notes = try c.decode(String.self, forKey: .notes)
            paymentMethodRaw = try c.decodeIfPresent(String.self, forKey: .paymentMethodRaw) ?? "cash"
            invoiceDate = try c.decodeIfPresent(Date.self, forKey: .invoiceDate)
            isBlack = try c.decodeIfPresent(Bool.self, forKey: .isBlack) ?? false
        }
        internal func model() -> LessonPackage {
            LessonPackage(id: id, clientID: clientID, clientName: clientName, purchasedOn: purchasedOn,
                priceCents: priceCents, capacity: capacity, expiresOn: expiresOn, notes: notes,
                paymentMethod: PaymentMethod(rawValue: paymentMethodRaw) ?? .cash, invoiceDate: invoiceDate,
                isBlack: isBlack)
        }
    }
    public struct PackageUseRecord: Codable, Equatable {
        public var id: UUID
        public var packageID: UUID
        public var sessionID: UUID
        public var clientID: UUID
        public var createdAt: Date
        public var sourceKey: String
        public init(_ value: PackageUse) {
            id = value.id; packageID = value.packageID; sessionID = value.sessionID
            clientID = value.clientID; createdAt = value.createdAt; sourceKey = value.sourceKey
        }
        internal func model() -> PackageUse {
            PackageUse(id: id, packageID: packageID, sessionID: sessionID, clientID: clientID,
                       createdAt: createdAt, sourceKey: sourceKey)
        }
    }
    public struct LedgerRecord: Codable, Equatable {
        public var id: UUID
        public var clientID: UUID
        public var clientName: String
        public var date: Date
        public var createdAt: Date
        public var kindRaw: String
        public var amountCents: Int64
        public var methodRaw: String
        public var notes: String
        public var sourceKey: String
        public var originalEntryID: UUID?
        public init(_ value: LedgerEntry) {
            id = value.id; clientID = value.clientID; clientName = value.clientName; date = value.date
            createdAt = value.createdAt; kindRaw = value.kindRaw; amountCents = value.amountCents
            methodRaw = value.methodRaw; notes = value.notes
            sourceKey = value.sourceKey; originalEntryID = value.originalEntryID
        }
        internal func model() -> LedgerEntry {
            let value = LedgerEntry(id: id, clientID: clientID, clientName: clientName, date: date,
                createdAt: createdAt, amountCents: amountCents, notes: notes,
                sourceKey: sourceKey, originalEntryID: originalEntryID)
            value.kindRaw = kindRaw; value.methodRaw = methodRaw
            return value
        }
    }
    public struct BlockRecord: Codable, Equatable {
        public var id: UUID
        public var startDate: Date
        public var endDate: Date
        public var title: String
        public init(_ value: Unavailability) {
            id = value.id; startDate = value.startDate; endDate = value.endDate; title = value.title
        }
        internal func model() -> Unavailability {
            Unavailability(id: id, startDate: startDate, endDate: endDate, title: title)
        }
    }
    public struct InvoiceRecord: Codable, Equatable {
        public var id: UUID
        public var clientID: UUID
        public var clientName: String
        public var issueDate: Date
        public var taxableCents: Int64
        public var contributionCents: Int64
        public var totalCents: Int64
        public var paymentMethodRaw: String
        public var sourceKey: String
        public var statusRaw: String
        public var arubaInvoiceId: String?
        public var createdAt: Date
        public var updatedAt: Date
        public var errorMessage: String?
        public init(_ value: Invoice) {
            id = value.id; clientID = value.clientID; clientName = value.clientName
            issueDate = value.issueDate; taxableCents = value.taxableCents
            contributionCents = value.contributionCents; totalCents = value.totalCents
            paymentMethodRaw = value.paymentMethodRaw; sourceKey = value.sourceKey
            statusRaw = value.statusRaw; arubaInvoiceId = value.arubaInvoiceId
            createdAt = value.createdAt; updatedAt = value.updatedAt; errorMessage = value.errorMessage
        }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(UUID.self, forKey: .id)
            clientID = try c.decode(UUID.self, forKey: .clientID)
            clientName = try c.decode(String.self, forKey: .clientName)
            issueDate = try c.decode(Date.self, forKey: .issueDate)
            taxableCents = try c.decode(Int64.self, forKey: .taxableCents)
            contributionCents = try c.decodeIfPresent(Int64.self, forKey: .contributionCents) ?? 0
            totalCents = try c.decode(Int64.self, forKey: .totalCents)
            paymentMethodRaw = try c.decodeIfPresent(String.self, forKey: .paymentMethodRaw) ?? "cash"
            sourceKey = try c.decodeIfPresent(String.self, forKey: .sourceKey) ?? ""
            statusRaw = try c.decodeIfPresent(String.self, forKey: .statusRaw) ?? "draft"
            arubaInvoiceId = try c.decodeIfPresent(String.self, forKey: .arubaInvoiceId)
            createdAt = try c.decode(Date.self, forKey: .createdAt)
            updatedAt = try c.decode(Date.self, forKey: .updatedAt)
            errorMessage = try c.decodeIfPresent(String.self, forKey: .errorMessage)
        }
        internal func model() -> Invoice {
            Invoice(id: id, clientID: clientID, clientName: clientName, issueDate: issueDate,
                    taxableCents: taxableCents, contributionCents: contributionCents, totalCents: totalCents,
                    paymentMethod: PaymentMethod(rawValue: paymentMethodRaw) ?? .cash, sourceKey: sourceKey,
                    status: InvoiceStatus(rawValue: statusRaw) ?? .draft, arubaInvoiceId: arubaInvoiceId,
                    createdAt: createdAt, updatedAt: updatedAt, errorMessage: errorMessage)
        }
    }
}
