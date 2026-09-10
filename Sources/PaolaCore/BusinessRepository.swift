import Foundation
import SwiftData

@MainActor
public final class BusinessRepository {
    private let context: ModelContext
    private let saveChanges: (ModelContext) throws -> Void

    public convenience init(context: ModelContext) {
        self.init(context: context, saveChanges: { try $0.save() })
    }

    internal init(context: ModelContext, saveChanges: @escaping (ModelContext) throws -> Void) {
        self.context = context
        self.saveChanges = saveChanges
        context.autosaveEnabled = false
    }

    @discardableResult
    public func saveService(_ draft: ServiceDraft) throws -> UUID {
        try transact { writer in
            let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { throw BusinessError.invalidInput("Inserire il nome del servizio.") }
            try BusinessRules.duration(draft.durationMinutes)
            let service: TrainingService
            if let id = draft.id {
                service = try find(id, in: writer, type: TrainingService.self, name: "Servizio")
            } else {
                service = TrainingService()
                writer.insert(service)
            }
            let existingRates = try writer.fetch(FetchDescriptor<ServiceRate>())
            var tariffs = draft.tariffs
            if tariffs.isEmpty {
                // Legacy callers only edit the default price, not the complete tariff list.
                tariffs = ServiceTariffs.options(for: service, rates: existingRates)
                tariffs[0].priceCents = draft.priceCents
            }
            let selectedIDs = Set(tariffs.map(\.id))
            guard selectedIDs.count == tariffs.count else {
                throw BusinessError.invalidInput("Le tariffe devono avere identificativi distinti.")
            }
            var names = Set<String>()
            for (index, tariff) in tariffs.enumerated() {
                let tariffName = tariff.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !tariffName.isEmpty, names.insert(TextNormalization.key(tariffName)).inserted else {
                    throw BusinessError.invalidInput("Inserire nomi di tariffa non vuoti e distinti.")
                }
                try BusinessRules.amount(tariff.priceCents)
                let rate: ServiceRate
                if let existing = existingRates.first(where: { $0.id == tariff.id }) {
                    guard existing.serviceID == service.id else {
                        throw BusinessError.invalidInput("La tariffa appartiene a un altro servizio.")
                    }
                    rate = existing
                } else {
                    rate = ServiceRate(id: tariff.id, serviceID: service.id)
                    writer.insert(rate)
                }
                rate.name = tariffName; rate.priceCents = tariff.priceCents; rate.sortOrder = index
            }
            for rate in existingRates where rate.serviceID == service.id && !selectedIDs.contains(rate.id) {
                writer.delete(rate)
            }
            service.name = name; service.durationMinutes = draft.durationMinutes
            service.priceCents = tariffs[0].priceCents; service.isActive = draft.isActive
            service.updatedAt = Date()
            return service.id
        }
    }

    public func deleteService(_ id: UUID) throws {
        try transact { writer in
            let service = try find(id, in: writer, type: TrainingService.self, name: "Servizio")
            // Lo storico degli appuntamenti è congelato: se un appuntamento (in qualsiasi
            // stato, inclusi annullati e assenze conservati nello storico) referenzia il
            // servizio, la cancellazione lo distruggerebbe. In quel caso si usa la disattivazione.
            let sessions = try writer.fetch(FetchDescriptor<TrainingSession>())
            guard !sessions.contains(where: { $0.serviceID == id }) else {
                throw BusinessError.serviceInUse
            }
            // Le tariffe del servizio vengono rimosse insieme al servizio.
            for rate in try writer.fetch(FetchDescriptor<ServiceRate>()) where rate.serviceID == id {
                writer.delete(rate)
            }
            // Le preferenze cliente che puntavano al servizio ripiegano sulle ultime scelte.
            for preference in try writer.fetch(FetchDescriptor<ClientAppointmentPreference>())
            where preference.serviceID == id {
                preference.serviceID = nil
                preference.rateID = nil
                preference.updatedAt = Date()
            }
            writer.delete(service)
        }
    }

    @discardableResult
    public func saveSession(_ draft: SessionDraft, allowOverlap: Bool = false) throws -> UUID {
        try transact { writer in
            try BusinessRules.date(draft.startDate); try BusinessRules.duration(draft.durationMinutes)
            let endDate = draft.startDate.addingTimeInterval(Double(draft.durationMinutes) * 60)
            try BusinessRules.date(endDate)
            let previousParticipants = try writer.fetch(FetchDescriptor<SessionParticipant>())
            let session: TrainingSession
            if let id = draft.id {
                session = try find(id, in: writer, type: TrainingSession.self, name: "Lezione")
                guard session.status != .completed else { throw BusinessError.completedSessionLocked }
            } else {
                session = TrainingSession()
            }
            guard !draft.participants.isEmpty,
                  Set(draft.participants.map(\.clientID)).count == draft.participants.count else {
                throw BusinessError.invalidInput("Selezionare almeno un cliente, senza partecipanti duplicati.")
            }
            if !allowOverlap, session.status == .planned {
                try checkOverlap(start: draft.startDate, end: endDate, excludingSession: session.id, in: writer)
            }
            var serviceName = draft.serviceName.trimmingCharacters(in: .whitespacesAndNewlines)
            if let serviceID = draft.serviceID {
                let service = try find(serviceID, in: writer, type: TrainingService.self, name: "Servizio")
                guard service.isActive || session.serviceID == serviceID else {
                    throw BusinessError.invalidInput("Il servizio selezionato non è attivo.")
                }
                if serviceName.isEmpty { serviceName = service.name }
            }
            if serviceName.isEmpty { serviceName = "Lezione" }
            var participants: [SessionParticipant] = []
            for draftParticipant in draft.participants {
                try BusinessRules.amount(draftParticipant.priceCents)
                let client = try client(draftParticipant.clientID, in: writer, requireActive: true)
                if let tariffID = draftParticipant.tariffID {
                    guard let serviceID = draft.serviceID else {
                        throw BusinessError.invalidInput("Selezionare il servizio della tariffa.")
                    }
                    let service = try find(serviceID, in: writer, type: TrainingService.self, name: "Servizio")
                    let rates = try writer.fetch(FetchDescriptor<ServiceRate>())
                    guard ServiceTariffs.options(for: service, rates: rates).contains(where: { $0.id == tariffID }) else {
                        throw BusinessError.invalidInput("La tariffa selezionata non è disponibile per questo servizio.")
                    }
                }
                if let packageID = draftParticipant.packageID {
                    let package = try find(packageID, in: writer, type: LessonPackage.self, name: "Pacchetto")
                    try checkPackage(package, clientID: client.id, date: draft.startDate, in: writer)
                }
                participants.append(SessionParticipant(sessionID: session.id, clientID: client.id,
                    clientName: client.fullName, priceCents: draftParticipant.priceCents,
                    packageID: draftParticipant.packageID, paymentMethod: draftParticipant.paymentMethod))
            }
            for previous in previousParticipants where previous.sessionID == session.id {
                writer.delete(previous)
            }
            if draft.id == nil { writer.insert(session) }
            session.startDate = draft.startDate; session.durationMinutes = draft.durationMinutes
            session.serviceID = draft.serviceID; session.serviceName = serviceName
            session.location = draft.location.trimmingCharacters(in: .whitespacesAndNewlines)
            session.notes = draft.notes.trimmingCharacters(in: .whitespacesAndNewlines)
            session.updatedAt = Date()
            participants.forEach { writer.insert($0) }
            let preferences = try writer.fetch(FetchDescriptor<ClientAppointmentPreference>())
            let calendar = SchedulingSuggestions.calendar
            for participant in draft.participants {
                for previous in preferences where previous.clientID == participant.clientID {
                    writer.delete(previous)
                }
                writer.insert(ClientAppointmentPreference(id: participant.clientID, clientID: participant.clientID,
                    serviceID: draft.serviceID, preferredHour: calendar.component(.hour, from: draft.startDate),
                    preferredMinute: calendar.component(.minute, from: draft.startDate), rateID: participant.tariffID,
                    priceCents: participant.priceCents, packageID: participant.packageID,
                    durationMinutes: draft.durationMinutes, updatedAt: session.updatedAt))
            }
            return session.id
        }
    }

    public func setSessionStatus(_ id: UUID, to status: SessionStatus, completionDate: Date = Date()) throws {
        try transact { writer in
            let session = try find(id, in: writer, type: TrainingSession.self, name: "Lezione")
            if session.status == status { return }
            guard session.status != .completed else { throw BusinessError.completedSessionLocked }
            if status == .planned || (status == .completed && session.status != .planned) {
                try checkOverlap(start: session.startDate, end: session.endDate, excludingSession: id, in: writer)
            }
            if status == .completed {
                try BusinessRules.date(completionDate)
                let participants = try writer.fetch(FetchDescriptor<SessionParticipant>()).filter { $0.sessionID == id }
                guard !participants.isEmpty,
                      Set(participants.map(\.clientID)).count == participants.count else {
                    throw BusinessError.inconsistentData("Partecipanti della lezione non validi.")
                }
                for participant in participants {
                    _ = try client(participant.clientID, in: writer, requireActive: true)
                    let source = BusinessRules.sessionSource(sessionID: id, clientID: participant.clientID)
                    if let packageID = participant.packageID {
                        let package = try find(packageID, in: writer, type: LessonPackage.self, name: "Pacchetto")
                        try checkPackage(package, clientID: participant.clientID, date: session.startDate, in: writer)
                        writer.insert(PackageUse(packageID: packageID, sessionID: id,
                            clientID: participant.clientID, sourceKey: source))
                    } else {
                        writer.insert(LedgerEntry(clientID: participant.clientID, clientName: participant.clientName,
                            date: session.startDate, kind: .charge, amountCents: participant.priceCents,
                            notes: session.serviceName, sourceKey: source))
                        if participant.priceCents > 0 {
                            writer.insert(LedgerEntry(clientID: participant.clientID, clientName: participant.clientName,
                                date: completionDate, kind: .payment, amountCents: participant.priceCents,
                                method: participant.paymentMethod, notes: session.serviceName,
                                sourceKey: BusinessRules.sessionIncomeSource(sessionID: id, clientID: participant.clientID)))
                        }
                    }
                }
            }
            session.status = status
            session.updatedAt = Date()
        }
    }

    @discardableResult
    public func savePackage(_ draft: PackageDraft) throws -> UUID {
        try transact { writer in
            try BusinessRules.date(draft.purchasedOn); try BusinessRules.amount(draft.priceCents)
            try BusinessRules.packageCapacity(draft.capacity)
            if let expiry = draft.expiresOn {
                try BusinessRules.date(expiry)
                guard Calendar.current.startOfDay(for: expiry) >= Calendar.current.startOfDay(for: draft.purchasedOn) else {
                    throw BusinessError.invalidInput("La scadenza non può precedere l'acquisto.")
                }
            }
            let notes = draft.notes.trimmingCharacters(in: .whitespacesAndNewlines)

            if let id = draft.id {
                // Modifica di un pacchetto esistente. Il cliente non cambia (i movimenti
                // economici restano associati allo stesso cliente).
                let package = try find(id, in: writer, type: LessonPackage.self, name: "Pacchetto")
                let uses = try writer.fetch(FetchDescriptor<PackageUse>())
                let used = BusinessReports.used(package: package, uses: uses)
                guard draft.capacity >= used else { throw BusinessError.packageCapacityBelowUsage }

                package.purchasedOn = draft.purchasedOn
                package.priceCents = draft.priceCents
                package.capacity = draft.capacity
                package.expiresOn = draft.expiresOn
                package.notes = notes
                package.paymentMethod = draft.paymentMethod

                // Allinea i movimenti economici collegati (addebito e incasso) a prezzo/data/metodo.
                let entries = try writer.fetch(FetchDescriptor<LedgerEntry>())
                let chargeSource = BusinessRules.packageSource(package.id)
                let incomeSource = BusinessRules.packageIncomeSource(package.id)
                for entry in entries where entry.originalEntryID == nil {
                    let key = entry.sourceKey.lowercased()
                    if key == chargeSource.lowercased() {
                        entry.date = draft.purchasedOn
                        entry.amountCents = draft.priceCents
                        entry.notes = "Pacchetto \(draft.capacity) lezioni"
                    } else if key == incomeSource.lowercased() {
                        entry.date = draft.purchasedOn
                        entry.amountCents = draft.priceCents
                        entry.method = draft.paymentMethod
                        entry.notes = "Pacchetto \(draft.capacity) lezioni"
                    }
                }
                return package.id
            }

            let client = try client(draft.clientID, in: writer, requireActive: true)
            let package = LessonPackage(clientID: client.id, clientName: client.fullName,
                purchasedOn: draft.purchasedOn, priceCents: draft.priceCents, capacity: draft.capacity,
                expiresOn: draft.expiresOn, notes: notes, paymentMethod: draft.paymentMethod)
            writer.insert(package)
            writer.insert(LedgerEntry(clientID: client.id, clientName: client.fullName, date: draft.purchasedOn,
                kind: .charge, amountCents: draft.priceCents, notes: "Pacchetto \(draft.capacity) lezioni",
                sourceKey: BusinessRules.packageSource(package.id)))
            if draft.priceCents > 0 {
                writer.insert(LedgerEntry(clientID: client.id, clientName: client.fullName, date: draft.purchasedOn,
                    kind: .payment, amountCents: draft.priceCents, method: draft.paymentMethod,
                    notes: "Pacchetto \(draft.capacity) lezioni",
                    sourceKey: BusinessRules.packageIncomeSource(package.id)))
            }
            return package.id
        }
    }

    /// Elimina un pacchetto e i suoi movimenti economici collegati (addebito e incasso).
    /// Consentito solo se nessuna lezione del pacchetto è stata utilizzata, per non
    /// alterare lo storico delle sedute completate.
    public func deletePackage(_ id: UUID) throws {
        try transact { writer in
            let package = try find(id, in: writer, type: LessonPackage.self, name: "Pacchetto")
            let uses = try writer.fetch(FetchDescriptor<PackageUse>())
            guard !uses.contains(where: { $0.packageID == id }) else {
                throw BusinessError.packageInUse
            }
            let chargeSource = BusinessRules.packageSource(id).lowercased()
            let incomeSource = BusinessRules.packageIncomeSource(id).lowercased()
            for entry in try writer.fetch(FetchDescriptor<LedgerEntry>())
            where entry.sourceKey.lowercased() == chargeSource || entry.sourceKey.lowercased() == incomeSource {
                writer.delete(entry)
            }
            writer.delete(package)
        }
    }

    @discardableResult
    public func recordPayment(_ draft: PaymentDraft) throws -> UUID {
        throw BusinessError.manualPaymentsDisabled
    }

    @discardableResult
    public func recordRefund(paymentID: UUID, amountCents: Int64, date: Date, notes: String) throws -> UUID {
        try recordAdjustment(originalID: paymentID, kind: .refund, amountCents: amountCents, date: date, notes: notes)
    }

    @discardableResult
    public func recordCredit(chargeID: UUID, amountCents: Int64, date: Date, notes: String) throws -> UUID {
        try recordAdjustment(originalID: chargeID, kind: .credit, amountCents: amountCents, date: date, notes: notes)
    }

    @discardableResult
    public func saveBlock(_ draft: BlockDraft, allowOverlap: Bool = false) throws -> UUID {
        try transact { writer in
            try BusinessRules.date(draft.startDate); try BusinessRules.date(draft.endDate)
            let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard draft.endDate > draft.startDate, !title.isEmpty else {
                throw BusinessError.invalidInput("Inserire titolo e un intervallo orario valido.")
            }
            let block: Unavailability
            if let id = draft.id {
                block = try find(id, in: writer, type: Unavailability.self, name: "Indisponibilità")
            } else { block = Unavailability() }
            if !allowOverlap {
                try checkOverlap(start: draft.startDate, end: draft.endDate, excludingBlock: block.id, in: writer)
            }
            if draft.id == nil { writer.insert(block) }
            block.startDate = draft.startDate; block.endDate = draft.endDate; block.title = title
            return block.id
        }
    }

    public func deleteBlock(_ id: UUID) throws {
        try transact { writer in
            writer.delete(try find(id, in: writer, type: Unavailability.self, name: "Indisponibilità"))
        }
    }

    private func recordAdjustment(originalID: UUID, kind: LedgerKind, amountCents: Int64,
                                  date: Date, notes: String) throws -> UUID {
        try transact { writer in
            try BusinessRules.amount(amountCents, positive: true); try BusinessRules.date(date)
            let original = try find(originalID, in: writer, type: LedgerEntry.self, name: "Movimento")
            guard original.kind == (kind == .refund ? .payment : .charge), date >= original.date else {
                throw BusinessError.invalidInput("Tipo o data del movimento originale non validi.")
            }
            let entries = try writer.fetch(FetchDescriptor<LedgerEntry>())
            let originalIDs = Set(entries.filter { $0.sourceKey.lowercased() == original.sourceKey.lowercased() }.map(\.id))
            let previous = try BusinessReports.canonicalEntries(entries)
                .filter { $0.kind == kind && $0.originalEntryID.map(originalIDs.contains) == true }
                .reduce(Int64(0)) { try BusinessRules.add($0, $1.amountCents) }
            guard amountCents <= original.amountCents - previous else { throw BusinessError.amountExceeded }
            let entry = LedgerEntry(clientID: original.clientID, clientName: original.clientName, date: date,
                kind: kind, amountCents: amountCents, method: original.method,
                notes: notes.trimmingCharacters(in: .whitespacesAndNewlines), originalEntryID: original.id)
            entry.sourceKey = "\(kind.rawValue):\(entry.id.uuidString.lowercased())"
            writer.insert(entry)
            return entry.id
        }
    }

    private func checkPackage(_ package: LessonPackage, clientID: UUID, date: Date, in writer: ModelContext) throws {
        guard package.clientID == clientID else {
            throw BusinessError.invalidInput("Il pacchetto non appartiene al cliente selezionato.")
        }
        try BusinessArchive().checkExpiry(package.expiresOn, sessionDate: date)
        let uses = try writer.fetch(FetchDescriptor<PackageUse>())
        guard BusinessReports.remaining(package: package, uses: uses) > 0 else { throw BusinessError.packageExhausted }
    }

    private func checkOverlap(start: Date, end: Date, excludingSession: UUID? = nil,
                              excludingBlock: UUID? = nil, in writer: ModelContext) throws {
        let sessions = try writer.fetch(FetchDescriptor<TrainingSession>())
        let blocks = try writer.fetch(FetchDescriptor<Unavailability>())
        if sessions.contains(where: {
            $0.id != excludingSession && ($0.status == .planned || $0.status == .completed)
                && $0.startDate < end && $0.endDate > start
        }) || blocks.contains(where: {
            $0.id != excludingBlock && $0.startDate < end && $0.endDate > start
        }) {
            throw BusinessError.overlap
        }
    }

    private func client(_ id: UUID, in writer: ModelContext, requireActive: Bool = false) throws -> Client {
        guard let client = try writer.fetch(FetchDescriptor<Client>()).first(where: { $0.id == id }) else {
            throw BusinessError.notFound("Cliente")
        }
        if requireActive && client.isArchived { throw BusinessError.invalidInput("Il cliente selezionato è archiviato.") }
        return client
    }

    private func find<T: PersistentModel>(_ id: UUID, in writer: ModelContext, type: T.Type, name: String) throws -> T {
        let matches = try writer.fetch(FetchDescriptor<T>()).filter { model in
            switch model {
            case let value as TrainingService: return value.id == id
            case let value as TrainingSession: return value.id == id
            case let value as LessonPackage: return value.id == id
            case let value as LedgerEntry: return value.id == id
            case let value as Unavailability: return value.id == id
            default: return false
            }
        }
        guard matches.count == 1, let found = matches.first else { throw BusinessError.notFound(name) }
        return found
    }

    private func transact<T>(_ operation: (ModelContext) throws -> T) throws -> T {
        // Keep failed saves and SwiftData rollback invalidation away from observed UI instances.
        let writer = ModelContext(context.container)
        writer.autosaveEnabled = false
        let clients = try writer.fetch(FetchDescriptor<Client>())
        let clientIDs = Set(clients.map(\.id))
        guard clientIDs.count == clients.count else { throw BusinessError.inconsistentData("Clienti duplicati.") }
        let warnings = BusinessReports.integrityWarnings(
            entries: try writer.fetch(FetchDescriptor<LedgerEntry>()),
            packages: try writer.fetch(FetchDescriptor<LessonPackage>()),
            uses: try writer.fetch(FetchDescriptor<PackageUse>()))
        guard warnings.isEmpty else {
            throw BusinessError.inconsistentData("Operazione sospesa per dati incoerenti. " + warnings.joined(separator: " "))
        }
        try BusinessArchive.capture(context: writer).validate(clientIDs: clientIDs)
        let result = try operation(writer)
        guard writer.hasChanges else { return result }
        try BusinessArchive.capture(context: writer).validate(clientIDs: clientIDs)
        try saveChanges(writer)
        do {
            _ = try context.fetch(FetchDescriptor<TrainingService>())
            _ = try context.fetch(FetchDescriptor<ServiceRate>())
            _ = try context.fetch(FetchDescriptor<ClientAppointmentPreference>())
            _ = try context.fetch(FetchDescriptor<TrainingSession>())
            _ = try context.fetch(FetchDescriptor<SessionParticipant>())
            _ = try context.fetch(FetchDescriptor<LessonPackage>())
            _ = try context.fetch(FetchDescriptor<PackageUse>())
            _ = try context.fetch(FetchDescriptor<LedgerEntry>())
            _ = try context.fetch(FetchDescriptor<Unavailability>())
        } catch {
            throw ClientPersistenceError.refreshAfterSaveFailed(error)
        }
        return result
    }
}
