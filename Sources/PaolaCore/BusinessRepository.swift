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
            // Stato finale: per una nuova sessione si usa lo stato richiesto dalla bozza
            // (programmato di default, o provvisorio); in modifica si conserva lo stato
            // corrente se la bozza non lo cambia.
            let targetStatus = draft.status ?? (draft.id == nil ? .planned : session.status)
            // La sovrapposizione è bloccante solo per gli appuntamenti programmati.
            // Un appuntamento provvisorio è una prenotazione tentativa: non blocca.
            if !allowOverlap, targetStatus == .planned {
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
            // Applica lo stato solo tra provvisorio e programmato: gli stati economici
            // (completata) o di chiusura (annullata/assenza) si gestiscono da setSessionStatus.
            if targetStatus == .provisional || targetStatus == .planned {
                session.status = targetStatus
            }
            // Ripartizione bianco/nero: se la bozza la specifica la applica; per un nuovo
            // appuntamento senza indicazione deriva dal metodo del primo partecipante
            // (contanti/PayPal = nero); in modifica senza indicazione resta invariata.
            if let isBlack = draft.isBlack {
                session.isBlack = isBlack
            } else if draft.id == nil {
                session.isBlack = draft.participants.first?.paymentMethod.defaultsToBlack ?? false
            }
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
                            // Spesa automatica (commissione) per incassi Stripe/carta.
                            let feeName = "Spesa \(BusinessRules.feeLabel(participant.paymentMethod)) appuntamento "
                                + "\(participant.clientName) \(BusinessRules.dateTimeLabel(session.startDate))"
                            try addTransactionFeeExpense(method: participant.paymentMethod, priceCents: participant.priceCents,
                                name: feeName, date: completionDate,
                                sourceKey: Expense.sessionFeeSourceKey(sessionID: id, clientID: participant.clientID),
                                in: writer)
                        }
                    }
                }
            }
            session.status = status
            session.updatedAt = Date()
        }
    }

    /// Elimina un appuntamento, anche se completato, rimuovendo tutti gli effetti
    /// economici collegati: addebiti e incassi (charge/payment) dei partecipanti senza
    /// pacchetto, consumi di pacchetto (PackageUse), commissioni automatiche (Expense-fee)
    /// e gli eventuali storni (refund/credit) che li referenziano. Rimuove infine i
    /// partecipanti e la sessione. Operazione unica e transazionale.
    ///
    /// Nota di prodotto: le sedute completate sono normalmente "congelate", ma
    /// l'eliminazione è un'azione esplicita dell'utente che disfa l'intera prestazione
    /// (non una modifica retroattiva silenziosa dei valori).
    public func deleteSession(_ id: UUID) throws {
        try transact { writer in
            let session = try find(id, in: writer, type: TrainingSession.self, name: "Lezione")
            let participants = try writer.fetch(FetchDescriptor<SessionParticipant>())
                .filter { $0.sessionID == id }

            // sourceKey dei movimenti generati dal completamento, per ciascun partecipante.
            var chargeSources = Set<String>()      // addebito lezione singola
            var incomeSources = Set<String>()       // incasso lezione singola
            var feeSources = Set<String>()          // commissione automatica (Expense)
            for participant in participants {
                chargeSources.insert(BusinessRules.sessionSource(sessionID: id, clientID: participant.clientID).lowercased())
                incomeSources.insert(BusinessRules.sessionIncomeSource(sessionID: id, clientID: participant.clientID).lowercased())
                feeSources.insert(Expense.sessionFeeSourceKey(sessionID: id, clientID: participant.clientID).lowercased())
            }

            let allEntries = try writer.fetch(FetchDescriptor<LedgerEntry>())
            // Movimenti diretti (charge/payment) generati dalla sessione.
            let directIDs = Set(allEntries.filter {
                let key = $0.sourceKey.lowercased()
                return chargeSources.contains(key) || incomeSources.contains(key)
            }.map(\.id))
            // Storni (refund/credit) che referenziano quei movimenti: senza l'origine
            // non hanno più significato, quindi vanno rimossi anch'essi.
            for entry in allEntries {
                let key = entry.sourceKey.lowercased()
                let isDirect = chargeSources.contains(key) || incomeSources.contains(key)
                let isAdjustmentOfDirect = entry.originalEntryID.map(directIDs.contains) == true
                if isDirect || isAdjustmentOfDirect {
                    writer.delete(entry)
                }
            }

            // Consumi di pacchetto della sessione.
            for use in try writer.fetch(FetchDescriptor<PackageUse>()) where use.sessionID == id {
                writer.delete(use)
            }

            // Commissioni automatiche della sessione (bypassa il blocco manuale: qui
            // stiamo eliminando l'origine, che è lo scenario ammesso).
            for expense in try writer.fetch(FetchDescriptor<Expense>())
            where feeSources.contains(expense.sourceKey.lowercased()) {
                writer.delete(expense)
            }

            // Fatture collegate all'appuntamento (documenti informativi).
            for participant in participants {
                let invoiceSource = Invoice.sessionSourceKey(sessionID: id, clientID: participant.clientID).lowercased()
                for invoice in try writer.fetch(FetchDescriptor<Invoice>())
                where invoice.sourceKey.lowercased() == invoiceSource {
                    writer.delete(invoice)
                }
            }

            for participant in participants { writer.delete(participant) }
            writer.delete(session)
        }
    }

    /// Sposta un appuntamento a un nuovo orario di inizio mantenendone la durata.
    /// Usato dal trascinamento (drag & drop) nel calendario.
    ///
    /// - Le lezioni completate sono congelate e non si spostano (regola di prodotto).
    /// - La sovrapposizione è bloccante solo per gli appuntamenti programmati; per i
    ///   provvisori è ammessa (prenotazione tentativa). Con `allowOverlap` si forza.
    public func rescheduleSession(_ id: UUID, to startDate: Date, allowOverlap: Bool = false) throws {
        try transact { writer in
            let session = try find(id, in: writer, type: TrainingSession.self, name: "Lezione")
            guard session.status != .completed else { throw BusinessError.completedSessionLocked }
            try BusinessRules.date(startDate)
            let end = startDate.addingTimeInterval(Double(session.durationMinutes) * 60)
            try BusinessRules.date(end)
            // Niente da fare se l'orario non cambia (evita salvataggi inutili).
            if session.startDate == startDate { return }
            if !allowOverlap, session.status == .planned {
                try checkOverlap(start: startDate, end: end, excludingSession: id, in: writer)
            }
            session.startDate = startDate
            session.updatedAt = Date()
        }
    }

    /// Imposta il contrassegno manuale "pagato" su un singolo partecipante. Non genera
    /// né modifica movimenti economici: è solo un promemoria per il trainer. Senza
    /// effetto sui partecipanti con pacchetto (il pagamento è gestito dal pacchetto).
    public func setParticipantPaid(_ id: UUID, _ paid: Bool) throws {
        try transact { writer in
            let participant = try find(id, in: writer, type: SessionParticipant.self, name: "Partecipante")
            guard participant.packageID == nil else { return }
            if participant.isPaid == paid { return }
            participant.isPaid = paid
            if let session = try? find(participant.sessionID, in: writer, type: TrainingSession.self, name: "Lezione") {
                session.updatedAt = Date()
            }
        }
    }

    /// Imposta il contrassegno "pagato" sulla quota di un cliente in più appuntamenti,
    /// in un'unica transazione. Usato per saldare in blocco le lezioni non pagate di un
    /// cliente: aggiorna solo i partecipanti di quel cliente (senza pacchetto), non gli
    /// altri partecipanti eventualmente presenti nelle stesse sessioni.
    public func setSessionsPaid(_ sessionIDs: [UUID], clientID: UUID, _ paid: Bool) throws {
        guard !sessionIDs.isEmpty else { return }
        try transact { writer in
            let now = Date()
            let ids = Set(sessionIDs)
            let participants = try writer.fetch(FetchDescriptor<SessionParticipant>())
                .filter { ids.contains($0.sessionID) && $0.clientID == clientID && $0.packageID == nil }
            for participant in participants where participant.isPaid != paid {
                participant.isPaid = paid
            }
            for id in sessionIDs {
                if let session = try? find(id, in: writer, type: TrainingSession.self, name: "Lezione") {
                    session.updatedAt = now
                }
            }
        }
    }

    /// Imposta la ripartizione contabile "bianco/nero" (true = nero) di un appuntamento.
    public func setSessionBlack(_ id: UUID, _ black: Bool) throws {
        try transact { writer in
            let session = try find(id, in: writer, type: TrainingSession.self, name: "Lezione")
            if session.isBlack == black { return }
            session.isBlack = black
            session.updatedAt = Date()
        }
    }

    /// Imposta la ripartizione contabile "bianco/nero" (true = nero) di un pacchetto.
    public func setPackageBlack(_ id: UUID, _ black: Bool) throws {
        try transact { writer in
            let package = try find(id, in: writer, type: LessonPackage.self, name: "Pacchetto")
            if package.isBlack == black { return }
            package.isBlack = black
        }
    }

    // MARK: - Spese

    /// Crea o aggiorna una spesa inserita a mano (una tantum o ricorrente mensile).
    @discardableResult
    public func saveExpense(_ draft: ExpenseDraft) throws -> UUID {
        try transact { writer in
            let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { throw BusinessError.invalidInput("Inserire il nome della spesa.") }
            try BusinessRules.date(draft.date); try BusinessRules.amount(draft.amountCents)
            let expense: Expense
            if let id = draft.id {
                expense = try find(id, in: writer, type: Expense.self, name: "Spesa")
            } else {
                expense = Expense()
                writer.insert(expense)
            }
            expense.name = name
            expense.date = draft.date
            expense.amountCents = draft.amountCents
            expense.kind = draft.kind
            expense.isPersonal = draft.isPersonal
            expense.updatedAt = Date()
            return expense.id
        }
    }

    public func deleteExpense(_ id: UUID) throws {
        try transact { writer in
            let expense = try find(id, in: writer, type: Expense.self, name: "Spesa")
            // Le commissioni automatiche (Stripe/carta) sono idempotenti rispetto
            // all'incasso di origine: si eliminano solo modificando o eliminando
            // l'appuntamento (o il pacchetto), mai a mano.
            guard !expense.isAutomaticFee else {
                throw BusinessError.invalidInput(
                    "Questa spesa è la commissione di un pagamento elettronico e non può essere eliminata direttamente. Modifica o elimina l'appuntamento (o il pacchetto) collegato.")
            }
            writer.delete(expense)
        }
    }

    /// Crea la spesa automatica (commissione) per un incasso Stripe/carta, se non già
    /// presente per la stessa origine (idempotente via `sourceKey`). Nessun effetto per
    /// altri metodi o importi non positivi.
    private func addTransactionFeeExpense(method: PaymentMethod, priceCents: Int64,
                                          name: String, date: Date, sourceKey: String,
                                          in writer: ModelContext) throws {
        guard TransactionFee.applies(to: method), priceCents > 0,
              let fee = TransactionFee.cents(for: priceCents, method: method), fee > 0 else { return }
        let key = sourceKey.lowercased()
        let existing = try writer.fetch(FetchDescriptor<Expense>())
        if existing.contains(where: { $0.sourceKey.lowercased() == key }) { return }
        writer.insert(Expense(name: name, date: date, amountCents: fee, kind: .oneTime, sourceKey: sourceKey))
    }

    @discardableResult
    public func savePackage(_ draft: PackageDraft) throws -> UUID {
        try transact { writer in
            try BusinessRules.date(draft.purchasedOn); try BusinessRules.amount(draft.priceCents)
            // Scadenza: per un pacchetto a tempo è calcolata dalla durata in mesi (1/3/6)
            // a partire dall'acquisto; per uno a lezioni resta quella eventualmente scelta.
            var effectiveExpiry = draft.expiresOn
            if draft.kind == .timed {
                let months = draft.durationMonths ?? 1
                effectiveExpiry = Calendar.current.date(byAdding: .month, value: months,
                                                        to: Calendar.current.startOfDay(for: draft.purchasedOn))
                guard effectiveExpiry != nil else {
                    throw BusinessError.invalidInput("Durata del pacchetto a tempo non valida.")
                }
            } else {
                // I pacchetti a lezioni validano la capienza.
                try BusinessRules.packageCapacity(draft.capacity)
            }
            if let expiry = effectiveExpiry {
                try BusinessRules.date(expiry)
                guard Calendar.current.startOfDay(for: expiry) >= Calendar.current.startOfDay(for: draft.purchasedOn) else {
                    throw BusinessError.invalidInput("La scadenza non può precedere l'acquisto.")
                }
            }
            // Capienza memorizzata: per i pacchetti a tempo non è significativa; usiamo 1
            // solo per rispettare i vincoli storici, ma non viene applicata (illimitato).
            let effectiveCapacity = draft.kind == .timed ? max(1, draft.capacity) : draft.capacity
            let notes = draft.notes.trimmingCharacters(in: .whitespacesAndNewlines)

            if let id = draft.id {
                // Modifica di un pacchetto esistente. Il cliente non cambia (i movimenti
                // economici restano associati allo stesso cliente).
                let package = try find(id, in: writer, type: LessonPackage.self, name: "Pacchetto")
                let uses = try writer.fetch(FetchDescriptor<PackageUse>())
                if draft.kind == .lessons {
                    let used = BusinessReports.used(package: package, uses: uses)
                    guard effectiveCapacity >= used else { throw BusinessError.packageCapacityBelowUsage }
                }

                package.purchasedOn = draft.purchasedOn
                package.priceCents = draft.priceCents
                package.capacity = effectiveCapacity
                package.expiresOn = effectiveExpiry
                package.kind = draft.kind
                package.notes = notes
                package.paymentMethod = draft.paymentMethod
                if let isBlack = draft.isBlack { package.isBlack = isBlack }

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
                // Riconcilia la spesa automatica (commissione) col nuovo metodo/prezzo.
                let feeKey = Expense.packageFeeSourceKey(package.id).lowercased()
                let feeExpenses = try writer.fetch(FetchDescriptor<Expense>())
                    .filter { $0.sourceKey.lowercased() == feeKey }
                let expectedFee = draft.priceCents > 0
                    ? TransactionFee.cents(for: draft.priceCents, method: draft.paymentMethod) : nil
                if let expectedFee, expectedFee > 0 {
                    let feeName = "Spesa \(BusinessRules.feeLabel(draft.paymentMethod)) pacchetto \(package.clientName)"
                    if let expense = feeExpenses.first {
                        expense.amountCents = expectedFee; expense.date = draft.purchasedOn
                        expense.name = feeName; expense.updatedAt = Date()
                        for extra in feeExpenses.dropFirst() { writer.delete(extra) }
                    } else {
                        writer.insert(Expense(name: feeName, date: draft.purchasedOn, amountCents: expectedFee,
                            kind: .oneTime, sourceKey: Expense.packageFeeSourceKey(package.id)))
                    }
                } else {
                    for expense in feeExpenses { writer.delete(expense) }
                }
                return package.id
            }

            let client = try client(draft.clientID, in: writer, requireActive: true)
            // Bianco/nero: se non indicato nella bozza, deriva dal metodo di pagamento.
            let packageIsBlack = draft.isBlack ?? draft.paymentMethod.defaultsToBlack
            let packageNote = draft.kind == .timed
                ? "Pacchetto \(draft.durationMonths ?? 1) mes\((draft.durationMonths ?? 1) == 1 ? "e" : "i")"
                : "Pacchetto \(effectiveCapacity) lezioni"
            let package = LessonPackage(clientID: client.id, clientName: client.fullName,
                purchasedOn: draft.purchasedOn, priceCents: draft.priceCents, capacity: effectiveCapacity,
                expiresOn: effectiveExpiry, notes: notes, paymentMethod: draft.paymentMethod,
                kind: draft.kind, isBlack: packageIsBlack)
            writer.insert(package)
            writer.insert(LedgerEntry(clientID: client.id, clientName: client.fullName, date: draft.purchasedOn,
                kind: .charge, amountCents: draft.priceCents, notes: packageNote,
                sourceKey: BusinessRules.packageSource(package.id)))
            if draft.priceCents > 0 {
                writer.insert(LedgerEntry(clientID: client.id, clientName: client.fullName, date: draft.purchasedOn,
                    kind: .payment, amountCents: draft.priceCents, method: draft.paymentMethod,
                    notes: packageNote,
                    sourceKey: BusinessRules.packageIncomeSource(package.id)))
                // Spesa automatica (commissione) per incassi Stripe/carta.
                let feeName = "Spesa \(BusinessRules.feeLabel(draft.paymentMethod)) pacchetto \(client.fullName)"
                try addTransactionFeeExpense(method: draft.paymentMethod, priceCents: draft.priceCents,
                    name: feeName, date: draft.purchasedOn,
                    sourceKey: Expense.packageFeeSourceKey(package.id), in: writer)
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
            let feeKey = Expense.packageFeeSourceKey(id).lowercased()
            for expense in try writer.fetch(FetchDescriptor<Expense>())
            where expense.sourceKey.lowercased() == feeKey {
                writer.delete(expense)
            }
            writer.delete(package)
        }
    }

    // MARK: - Fatturazione elettronica

    /// Metodi di pagamento per cui è ammessa l'emissione della fattura elettronica.
    /// Esclusi i contanti (e "Altro" storico).
    public static let invoiceableMethods: Set<PaymentMethod> = [.stripe, .card, .bankTransfer]

    /// Crea (in stato bozza) la fattura per l'incasso della lezione singola di un partecipante.
    /// Richiede: sessione completata, partecipante senza pacchetto, metodo ammesso, importo > 0,
    /// nessuna fattura già presente per lo stesso incasso (idempotenza). Imposta la data di
    /// fatturazione sull'appuntamento. Non altera i movimenti economici.
    @discardableResult
    public func createInvoiceForSession(sessionID: UUID, clientID: UUID, issueDate: Date) throws -> UUID {
        try transact { writer in
            try BusinessRules.date(issueDate)
            // La fattura può essere emessa in qualsiasi stato dell'appuntamento
            // (programmato, completato, annullato, assenza).
            let session = try find(sessionID, in: writer, type: TrainingSession.self, name: "Lezione")
            let participants = try writer.fetch(FetchDescriptor<SessionParticipant>())
                .filter { $0.sessionID == sessionID && $0.clientID == clientID }
            guard let participant = participants.first else {
                throw BusinessError.notFound("Partecipante")
            }
            guard participant.packageID == nil else {
                throw BusinessError.notInvoiceable("La lezione è coperta da un pacchetto: fattura il pacchetto, non la singola lezione.")
            }
            guard Self.invoiceableMethods.contains(participant.paymentMethod) else {
                throw BusinessError.notInvoiceable("La fattura elettronica è disponibile solo per incassi con Stripe, carta o bonifico.")
            }
            guard participant.priceCents > 0 else {
                throw BusinessError.notInvoiceable("Non è possibile fatturare un importo pari a zero.")
            }
            let sourceKey = Invoice.sessionSourceKey(sessionID: sessionID, clientID: clientID)
            try ensureNotAlreadyInvoiced(sourceKey, in: writer)

            let breakdown = try ForfettarioBreakdown.from(totalCents: participant.priceCents)
            let invoice = Invoice(clientID: clientID, clientName: participant.clientName,
                issueDate: issueDate, taxableCents: breakdown.taxableCents,
                contributionCents: breakdown.contributionCents, totalCents: breakdown.totalCents,
                paymentMethod: participant.paymentMethod, sourceKey: sourceKey, status: .draft)
            writer.insert(invoice)
            session.invoiceDate = issueDate
            session.updatedAt = Date()
            return invoice.id
        }
    }

    /// Crea (in stato bozza) la fattura per l'incasso dell'acquisto di un pacchetto.
    /// Richiede: metodo ammesso, importo > 0, nessuna fattura già presente (idempotenza).
    @discardableResult
    public func createInvoiceForPackage(packageID: UUID, issueDate: Date) throws -> UUID {
        try transact { writer in
            try BusinessRules.date(issueDate)
            let package = try find(packageID, in: writer, type: LessonPackage.self, name: "Pacchetto")
            guard Self.invoiceableMethods.contains(package.paymentMethod) else {
                throw BusinessError.notInvoiceable("La fattura elettronica è disponibile solo per incassi con Stripe, carta o bonifico.")
            }
            guard package.priceCents > 0 else {
                throw BusinessError.notInvoiceable("Non è possibile fatturare un importo pari a zero.")
            }
            let sourceKey = Invoice.packageSourceKey(packageID)
            try ensureNotAlreadyInvoiced(sourceKey, in: writer)

            let breakdown = try ForfettarioBreakdown.from(totalCents: package.priceCents)
            let invoice = Invoice(clientID: package.clientID, clientName: package.clientName,
                issueDate: issueDate, taxableCents: breakdown.taxableCents,
                contributionCents: breakdown.contributionCents, totalCents: breakdown.totalCents,
                paymentMethod: package.paymentMethod, sourceKey: sourceKey, status: .draft)
            writer.insert(invoice)
            package.invoiceDate = issueDate
            return invoice.id
        }
    }

    private func ensureNotAlreadyInvoiced(_ sourceKey: String, in writer: ModelContext) throws {
        let key = sourceKey.lowercased()
        let existing = try writer.fetch(FetchDescriptor<Invoice>())
        if existing.contains(where: { $0.sourceKey.lowercased() == key }) {
            throw BusinessError.alreadyInvoiced
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

    // MARK: - Corsi

    /// Crea o aggiorna un corso ricorrente e i suoi partecipanti. I partecipanti devono
    /// essere clienti attivi con un pacchetto a tempo che appartiene a loro. Non genera
    /// movimenti economici: la partecipazione è coperta dal pacchetto a tempo.
    @discardableResult
    public func saveCourse(_ draft: CourseDraft) throws -> UUID {
        try transact { writer in
            let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { throw BusinessError.invalidInput("Inserire il titolo del corso.") }
            guard !draft.weekdays.isEmpty else { throw BusinessError.invalidInput("Seleziona almeno un giorno della settimana.") }
            guard draft.weekdays.allSatisfy({ (1...7).contains($0) }) else {
                throw BusinessError.invalidInput("Giorni della settimana non validi.")
            }
            guard (0...23).contains(draft.startHour), (0...59).contains(draft.startMinute) else {
                throw BusinessError.invalidInput("Orario del corso non valido.")
            }
            try BusinessRules.duration(draft.durationMinutes)

            let course: Course
            if let id = draft.id {
                course = try find(id, in: writer, type: Course.self, name: "Corso")
            } else {
                course = Course()
                writer.insert(course)
            }
            course.title = title
            course.weekdays = draft.weekdays
            course.startHour = draft.startHour
            course.startMinute = draft.startMinute
            course.durationMinutes = draft.durationMinutes
            course.updatedAt = Date()

            // Sostituisce l'elenco partecipanti. Ogni partecipante è un cliente con un
            // pacchetto a tempo che gli appartiene.
            for previous in try writer.fetch(FetchDescriptor<CourseParticipant>()) where previous.courseID == course.id {
                writer.delete(previous)
            }
            var seen = Set<UUID>()
            for person in draft.participants {
                guard let clientID = person.clientID else { continue }
                guard seen.insert(clientID).inserted else {
                    throw BusinessError.invalidInput("Partecipante duplicato nel corso.")
                }
                let client = try client(clientID, in: writer, requireActive: true)
                if let packageID = person.packageID {
                    let package = try find(packageID, in: writer, type: LessonPackage.self, name: "Pacchetto")
                    guard package.clientID == clientID else {
                        throw BusinessError.invalidInput("Il pacchetto non appartiene al partecipante.")
                    }
                    guard package.kind == .timed else {
                        throw BusinessError.invalidInput("I partecipanti al corso devono avere un pacchetto a tempo.")
                    }
                }
                writer.insert(CourseParticipant(courseID: course.id, clientID: clientID,
                    clientName: client.fullName, packageID: person.packageID))
            }
            return course.id
        }
    }

    /// Elimina un corso e i suoi partecipanti. Non tocca movimenti economici.
    public func deleteCourse(_ id: UUID) throws {
        try transact { writer in
            let course = try find(id, in: writer, type: Course.self, name: "Corso")
            for participant in try writer.fetch(FetchDescriptor<CourseParticipant>()) where participant.courseID == id {
                writer.delete(participant)
            }
            writer.delete(course)
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
        // I pacchetti a tempo sono illimitati entro la validità: solo la scadenza conta.
        guard package.kind != .timed else { return }
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
            case let value as SessionParticipant: return value.id == id
            case let value as LessonPackage: return value.id == id
            case let value as LedgerEntry: return value.id == id
            case let value as Unavailability: return value.id == id
            case let value as Invoice: return value.id == id
            case let value as Expense: return value.id == id
            case let value as Course: return value.id == id
            case let value as CourseParticipant: return value.id == id
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
