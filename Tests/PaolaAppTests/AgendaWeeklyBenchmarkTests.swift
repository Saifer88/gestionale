import Foundation
@testable import PaolaApp
@testable import PaolaCore
import SwiftData
import XCTest

/// Dataset inventato (in memoria) e benchmark dell'agenda settimanale.
/// 40 clienti, 30 servizi con 2-4 tariffe, 22 settimane (~5 mesi) con 34+ appuntamenti
/// a settimana, pacchetti da 10 lezioni, indisponibilità e sovrapposizioni.
/// Non modifica logica di dominio: misura solo.
@MainActor
final class AgendaWeeklyBenchmarkTests: XCTestCase {
    // MARK: - Generatore

    struct Dataset {
        let clients: [Client]
        let services: [TrainingService]
        /// Inizio (lunedì) della prima settimana.
        let firstMonday: Date
        /// Settimana "corrente": prima di essa gli appuntamenti sono chiusi, da essa in poi programmati.
        let currentWeekStart: Date
        let weeks = 22
        let sessionCount: Int
        let participantCount: Int
        let ledgerCount: Int
        let packageCount: Int
    }

    /// Generatore pseudo-casuale deterministico (LCG).
    struct Rng {
        var state: UInt64
        mutating func next(_ upper: Int) -> Int {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Int((state >> 33) % UInt64(upper))
        }
    }

    private func makeDataset(in context: ModelContext) throws -> Dataset {
        context.autosaveEnabled = false
        let calendar = SchedulingSuggestions.calendar
        var rng = Rng(state: 42)
        let monday = calendar.date(from: DateComponents(year: 2025, month: 1, day: 6))!
        let weeks = 22
        let currentWeek = 17
        let currentWeekStart = calendar.date(byAdding: .weekOfYear, value: currentWeek, to: monday)!

        let clients = (0..<40).map { Client(firstName: "Cliente\($0)", lastName: "Prova") }
        clients.forEach(context.insert)

        // 30 servizi, ciascuno con 2-4 tariffe nominate.
        let rateNames = ["Standard", "Ridotta", "Coppia", "Studenti"]
        var services: [TrainingService] = []
        var ratesByService: [UUID: [ServiceRate]] = [:]
        for index in 0..<30 {
            let base = Int64(3000 + index * 200)
            let service = TrainingService(name: "Servizio\(index)", durationMinutes: [30, 45, 60, 60, 90][index % 5],
                                          priceCents: base)
            context.insert(service)
            services.append(service)
            for order in 0..<(2 + index % 3) {
                let rate = ServiceRate(serviceID: service.id, name: rateNames[order],
                                       priceCents: base - Int64(order) * 300, sortOrder: order)
                context.insert(rate)
                ratesByService[service.id, default: []].append(rate)
            }
        }

        // Slot settimanali: lunedì-sabato, ogni 30 minuti dalle 7:00 alle 19:30.
        struct Slot { let day: Int; let minutes: Int }
        let allSlots = (0..<6).flatMap { day in stride(from: 7 * 60, to: 20 * 60, by: 60).map { Slot(day: day, minutes: $0) } }

        // Pacchetti: i primi 26 clienti ne usano uno alla volta (capienza 10).
        var activePackage: [UUID: (package: LessonPackage, assigned: Int)] = [:]
        var packageCount = 0, participantCount = 0, ledgerCount = 0, sessionCount = 0
        func newPackage(for client: Client, on date: Date) -> LessonPackage {
            let package = LessonPackage(clientID: client.id, clientName: client.fullName, purchasedOn: date,
                                        priceCents: 40_000, capacity: 10, notes: "Pacchetto 10 lezioni",
                                        paymentMethod: .bankTransfer)
            context.insert(package)
            context.insert(LedgerEntry(clientID: client.id, clientName: client.fullName, date: date, kind: .charge,
                amountCents: 40_000, notes: "Pacchetto 10 lezioni", sourceKey: BusinessRules.packageSource(package.id)))
            context.insert(LedgerEntry(clientID: client.id, clientName: client.fullName, date: date, kind: .payment,
                amountCents: 40_000, method: .bankTransfer, notes: "Pacchetto 10 lezioni",
                sourceKey: BusinessRules.packageIncomeSource(package.id)))
            packageCount += 1; ledgerCount += 2
            return package
        }

        for week in 0..<weeks {
            let weekStart = calendar.date(byAdding: .weekOfYear, value: week, to: monday)!
            let closed = week < currentWeek
            // 34-38 appuntamenti a settimana (primo slot distinto; qualche sovrapposizione extra).
            var slots = allSlots.shuffled(using: &rng)
            let target = 34 + rng.next(5)
            slots = Array(slots.prefix(target))
            for (index, slot) in slots.enumerated() {
                let day = calendar.date(byAdding: .day, value: slot.day, to: weekStart)!
                let start = calendar.date(byAdding: .minute, value: slot.minutes, to: day)!
                let service = services[rng.next(services.count)]
                let rates = ratesByService[service.id] ?? []
                let rate = rates[rng.next(rates.count)]
                // Qualche appuntamento sovrapposto di 30 minuti rispetto allo slot orario.
                let overlapShift = index % 17 == 0 ? 30 : 0
                let sessionStart = start.addingTimeInterval(Double(overlapShift) * 60)
                var status: SessionStatus = .planned
                if closed {
                    let roll = rng.next(100)
                    status = roll < 85 ? .completed : roll < 92 ? .cancelled : roll < 97 ? .noShow : .planned
                } else if week == currentWeek, rng.next(100) < 10 {
                    status = .provisional
                }
                let session = TrainingSession(startDate: sessionStart, durationMinutes: service.durationMinutes,
                                              serviceID: service.id, serviceName: service.name, status: status,
                                              isBlack: rng.next(100) < 40)
                context.insert(session)
                sessionCount += 1
                // 1 partecipante; ogni 7 appuntamenti sono in coppia.
                let people = index % 7 == 0 ? 2 : 1
                var chosen = Set<Int>()
                while chosen.count < people { chosen.insert(rng.next(clients.count)) }
                for clientIndex in chosen.sorted() {
                    let client = clients[clientIndex]
                    var packageID: UUID?
                    // I primi 26 clienti usano il pacchetto per metà delle lezioni.
                    if clientIndex < 26, rng.next(100) < 55, status != .cancelled, status != .noShow {
                        var state = activePackage[client.id]
                        if state == nil || state!.assigned >= state!.package.capacity {
                            state = (newPackage(for: client, on: calendar.date(byAdding: .day, value: -1, to: sessionStart)!), 0)
                        }
                        state!.assigned += 1
                        activePackage[client.id] = state
                        packageID = state!.package.id
                    }
                    let price = (people == 2 ? rates.last!.priceCents : rate.priceCents)
                    let method: PaymentMethod = rng.next(100) < 70 ? .cash : .bankTransfer
                    let participant = SessionParticipant(sessionID: session.id, clientID: client.id,
                        clientName: client.fullName, priceCents: price, packageID: packageID,
                        paymentMethod: method, isPaid: packageID == nil && rng.next(100) < 30)
                    context.insert(participant)
                    participantCount += 1
                    guard status == .completed else { continue }
                    let source = BusinessRules.sessionSource(sessionID: session.id, clientID: client.id)
                    if let packageID {
                        context.insert(PackageUse(packageID: packageID, sessionID: session.id,
                                                  clientID: client.id, sourceKey: source))
                    } else {
                        context.insert(LedgerEntry(clientID: client.id, clientName: client.fullName, date: sessionStart,
                            kind: .charge, amountCents: price, notes: service.name, sourceKey: source))
                        context.insert(LedgerEntry(clientID: client.id, clientName: client.fullName, date: sessionStart,
                            kind: .payment, amountCents: price, method: method, notes: service.name,
                            sourceKey: BusinessRules.sessionIncomeSource(sessionID: session.id, clientID: client.id)))
                        ledgerCount += 2
                    }
                }
            }
            // Un blocco di indisponibilità ogni 4 settimane (mercoledì 13:00-15:00 oppure ferie di un giorno).
            if week % 4 == 3 {
                let day = calendar.date(byAdding: .day, value: 2, to: weekStart)!
                let from = calendar.date(byAdding: .hour, value: 13, to: day)!
                context.insert(Unavailability(startDate: from, endDate: from.addingTimeInterval(7200),
                                              title: "Pausa \(week)"))
            }
        }
        try context.save()
        return Dataset(clients: clients, services: services, firstMonday: monday,
                       currentWeekStart: currentWeekStart, sessionCount: sessionCount,
                       participantCount: participantCount, ledgerCount: ledgerCount, packageCount: packageCount)
    }

    // MARK: - Misure

    private struct Stats { let min: Double, median: Double, max: Double }

    private func repeatMeasure(_ runs: Int, setup: (Int) throws -> Void = { _ in },
                               _ block: (Int) throws -> Void) rethrows -> Stats {
        var samples: [Double] = []
        for index in 0..<runs {
            try setup(index)
            let clock = ContinuousClock()
            let elapsed = try clock.measure { try block(index) }
            samples.append(Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18)
        }
        samples.sort()
        return Stats(min: samples.first!, median: samples[samples.count / 2], max: samples.last!)
    }

    private func report(_ label: String, _ validation: String, _ stats: Stats) {
        print(String(format: "[bench] %@ | %@ | min %.4f | med %.4f | max %.4f", label, validation,
                     stats.min, stats.median, stats.max))
    }

    // MARK: - Test

    func testWeeklyAgendaDatasetAndOperations() throws {
        let container = try ModelContainer(
            for: Schema(versionedSchema: PaolaSchemaV16.self),
            configurations: [ModelConfiguration(schema: Schema(versionedSchema: PaolaSchemaV16.self),
                                                isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
        let context = ModelContext(container)
        let generation = Date()
        let data = try makeDataset(in: context)
        print("[bench] dataset generato in \(String(format: "%.2f", Date().timeIntervalSince(generation))) s: "
              + "\(data.clients.count) clienti, \(data.services.count) servizi, \(data.sessionCount) appuntamenti "
              + "(\(data.sessionCount / data.weeks)/settimana), \(data.participantCount) partecipanti, "
              + "\(data.packageCount) pacchetti, \(data.ledgerCount) movimenti")
        XCTAssertGreaterThan(data.sessionCount / data.weeks, 30)

        // Il dataset deve essere coerente per il repository (stesse regole delle scritture).
        let clientIDs = Set(data.clients.map(\.id))
        let archive = try BusinessArchive.uncanonicalizedCapture(context: context)
        try archive.validate(clientIDs: clientIDs)
        XCTAssertTrue(BusinessReports.integrityWarnings(
            entries: try context.fetch(FetchDescriptor<LedgerEntry>()),
            packages: try context.fetch(FetchDescriptor<LessonPackage>()),
            uses: try context.fetch(FetchDescriptor<PackageUse>())).isEmpty)

        try benchmarkWeeklySnapshot(context: context, data: data)
        try benchmarkValidationBaseline(context: context, clientIDs: clientIDs)
        try benchmarkWrites(container: container, context: context, data: data)
    }

    /// Replica fedele di `AgendaContent` (view private, non raggiungibili): query + `makeSnapshot`.
    private func benchmarkWeeklySnapshot(context: ModelContext, data: Dataset) throws {
        let calendar = SchedulingSuggestions.calendar
        let interval = calendar.dateInterval(of: .weekOfYear, for: data.currentWeekStart.addingTimeInterval(86_400))!
        let lower = interval.start.addingTimeInterval(-3 * 86_400)
        let upper = interval.end

        var sessions: [TrainingSession] = []
        let windowFetch = try repeatMeasure(5) { _ in
            sessions = try context.fetch(FetchDescriptor<TrainingSession>(
                predicate: #Predicate { $0.startDate >= lower && $0.startDate < upper },
                sortBy: [SortDescriptor(\.startDate)]))
        }
        report("agenda: fetch sessioni finestra settimana (\(sessions.count))", "-", windowFetch)

        var participants: [SessionParticipant] = [], clients: [Client] = [], blocks: [Unavailability] = []
        var packages: [LessonPackage] = [], courses: [Course] = [], courseParticipants: [CourseParticipant] = []
        let otherFetch = try repeatMeasure(5) { _ in
            participants = try context.fetch(FetchDescriptor<SessionParticipant>())
            clients = try context.fetch(FetchDescriptor<Client>())
            blocks = try context.fetch(FetchDescriptor<Unavailability>())
            packages = try context.fetch(FetchDescriptor<LessonPackage>())
            courses = try context.fetch(FetchDescriptor<Course>())
            courseParticipants = try context.fetch(FetchDescriptor<CourseParticipant>())
        }
        report("agenda: @Query non filtrate (partecipanti \(participants.count), clienti, blocchi, pacchetti, corsi)",
               "-", otherFetch)

        var visibleCount = 0
        let build = try repeatMeasure(10) { _ in
            let visible = CalendarAppointments.visible(sessions, in: interval)
            let allBySession = Dictionary(grouping: participants, by: \.sessionID)
            let visibleIDs = Set(visible.map(\.id))
            var participantsBySession: [UUID: [SessionParticipant]] = [:]
            var needed = Set<UUID>()
            for (sessionID, people) in allBySession where visibleIDs.contains(sessionID) {
                participantsBySession[sessionID] = people
                for person in people { needed.insert(person.clientID) }
            }
            var clientsByID: [UUID: Client] = [:]
            for client in clients where needed.contains(client.id) { clientsByID[client.id] = client }
            let conflicts = Self.conflicts(in: sessions)
            let occurrences = CourseOccurrences.expand(courses: courses, participants: courseParticipants,
                                                       packages: packages, in: interval)
            visibleCount = visible.count + clientsByID.count + conflicts.count + occurrences.count
        }
        XCTAssertGreaterThan(visibleCount, 0)
        report("agenda: makeSnapshot settimana (\(CalendarAppointments.visible(sessions, in: interval).count) visibili)",
               "-", build)

        // Chiave di snapshot: legge 6 conteggi (come `snapshotKey`).
        let key = try repeatMeasure(10) { _ in
            _ = "\(sessions.count)|\(participants.count)|\(packages.count)|\(clients.count)|\(blocks.count)"
        }
        report("agenda: snapshotKey (conteggi array già caricati)", "-", key)
    }

    /// Copia di `AgendaSnapshot.conflicts` (struct private nell'app).
    private static func conflicts(in sessions: [TrainingSession]) -> Set<UUID> {
        let active = sessions.filter { $0.status == .planned || $0.status == .completed }
            .sorted { $0.startDate < $1.startDate }
        var result = Set<UUID>()
        for (index, session) in active.enumerated() {
            let end = session.endDate
            var next = index + 1
            while next < active.count, active[next].startDate < end {
                if active[next].id != session.id { result.insert(session.id); result.insert(active[next].id) }
                next += 1
            }
        }
        return result
    }

    /// Costo isolato della validazione globale (eseguita due volte per ogni scrittura `.archive`).
    private func benchmarkValidationBaseline(context: ModelContext, clientIDs: Set<UUID>) throws {
        let reader = ModelContext(context.container)
        let capture = try repeatMeasure(5) { _ in _ = try BusinessArchive.uncanonicalizedCapture(context: reader) }
        report("validazione: uncanonicalizedCapture (fetch di tutto l'archivio)", ".archive", capture)
        let archive = try BusinessArchive.uncanonicalizedCapture(context: reader)
        let validate = try repeatMeasure(5) { _ in try archive.validate(clientIDs: clientIDs) }
        report("validazione: validate(clientIDs:) su archivio già letto", ".archive", validate)
        let warnings = try repeatMeasure(5) { _ in
            _ = BusinessReports.integrityWarnings(
                entries: try reader.fetch(FetchDescriptor<LedgerEntry>()),
                packages: try reader.fetch(FetchDescriptor<LessonPackage>()),
                uses: try reader.fetch(FetchDescriptor<PackageUse>()))
        }
        report("validazione: integrityWarnings (fetch + calcolo)", ".archive", warnings)
        // Costo spostato (non eliminato): validazione completa su ModelActor, fuori dal percorso del click.
        let checker = ArchiveHealthChecker(modelContainer: context.container)
        let full = try repeatMeasure(5) { _ in
            let done = expectation(description: "fullValidation")
            Task { _ = try? await checker.fullValidation(); done.fulfill() }
            wait(for: [done], timeout: 60)
        }
        report("ArchiveHealthChecker.fullValidation (background, spostato)", "async", full)
    }

    private func benchmarkWrites(container: ModelContainer, context: ModelContext, data: Dataset) throws {
        let repository = BusinessRepository(context: context)
        let runs = 5
        let weekStart = data.currentWeekStart
        // Appuntamenti futuri programmati, classificati per partecipanti/pacchetto.
        let future = try context.fetch(FetchDescriptor<TrainingSession>(
            predicate: #Predicate { $0.statusRaw == "planned" && $0.startDate >= weekStart },
            sortBy: [SortDescriptor(\.startDate)]))
        let allParticipants = Dictionary(grouping: try context.fetch(FetchDescriptor<SessionParticipant>()), by: \.sessionID)
        func pick(_ label: String, _ predicate: ([SessionParticipant]) -> Bool) throws -> [TrainingSession] {
            let found = future.filter { predicate(allParticipants[$0.id] ?? []) }
            XCTAssertGreaterThanOrEqual(found.count, runs, label)
            return Array(found.prefix(runs))
        }
        let single = try pick("singolo senza pacchetto") { $0.count == 1 && $0[0].packageID == nil }
        let singlePackage = try pick("singolo con pacchetto") { $0.count == 1 && $0[0].packageID != nil }
        let multi = try pick("più partecipanti senza pacchetto") { $0.count == 2 && $0.allSatisfy { $0.packageID == nil } }
        let multiPackage = try pick("più partecipanti con pacchetto") { $0.count == 2 && $0.contains { $0.packageID != nil } }
        var usedIDs = Set((single + singlePackage + multi + multiPackage).map(\.id))
        let spare = future.filter { !usedIDs.contains($0.id) && (allParticipants[$0.id]?.count == 1) && allParticipants[$0.id]![0].packageID == nil }
        XCTAssertGreaterThanOrEqual(spare.count, runs * 5)
        func take() -> [TrainingSession] { let chunk = Array(spare.filter { !usedIDs.contains($0.id) }.prefix(runs)); usedIDs.formUnion(chunk.map(\.id)); return chunk }
        let paidTargets = take(), blackTargets = take(), moveTargets = take(), cancelTargets = take()

        func entryCount() throws -> Int { try context.fetchCount(FetchDescriptor<LedgerEntry>()) }
        func useCount() throws -> Int { try context.fetchCount(FetchDescriptor<PackageUse>()) }

        // Completamento (.scoped).
        func complete(_ label: String, _ sessions: [TrainingSession]) throws {
            let stats = try repeatMeasure(runs) { try repository.setSessionStatus(sessions[$0].id, to: .completed) }
            report(label, ".scoped", stats)
        }
        try complete("completa appuntamento (1 partecipante, senza pacchetto)", single)
        try complete("completa appuntamento (1 partecipante, con pacchetto)", singlePackage)
        try complete("completa appuntamento (2 partecipanti, senza pacchetto)", multi)
        try complete("completa appuntamento (2 partecipanti, uno con pacchetto)", multiPackage)

        // Idempotenza: ripetere il completamento sullo stesso appuntamento non duplica nulla.
        let beforeEntries = try entryCount(), beforeUses = try useCount()
        let repeated = try repeatMeasure(runs) { try repository.setSessionStatus(multiPackage[$0].id, to: .completed) }
        report("completamento ripetuto (già completato)", ".scoped", repeated)
        XCTAssertEqual(try entryCount(), beforeEntries, "completamento ripetuto non deve duplicare movimenti")
        XCTAssertEqual(try useCount(), beforeUses, "completamento ripetuto non deve duplicare utilizzi")
        // Idempotenza sui dati scritti: un solo addebito per partecipante/appuntamento.
        for session in multi {
            for participant in allParticipants[session.id] ?? [] {
                let source = BusinessRules.sessionSource(sessionID: session.id, clientID: participant.clientID)
                let charges = try context.fetch(FetchDescriptor<LedgerEntry>(predicate: #Predicate { $0.sourceKey == source }))
                XCTAssertEqual(charges.count, 1)
            }
        }

        // Pagamento: nell'app è il contrassegno "pagato" (.local); recordPayment è disattivato.
        report("segna partecipante pagato (setParticipantPaid)", ".local", try repeatMeasure(runs) {
            let participant = try XCTUnwrap(allParticipants[paidTargets[$0].id]?.first)
            try repository.setParticipantPaid(participant.id, true)
        })
        let target = try XCTUnwrap(allParticipants[paidTargets[0].id]?.first)
        let batchIDs = Array(future.filter { allParticipants[$0.id]?.first?.packageID == nil }.prefix(10).map(\.id))
        let batchClient = try XCTUnwrap(allParticipants[batchIDs[0]]?.first?.clientID)
        report("segna 10 lezioni pagate (setSessionsPaid)", ".local", try repeatMeasure(runs) { _ in
            try repository.setSessionsPaid(batchIDs, clientID: batchClient, true)
        })
        _ = target
        report("bianco/nero appuntamento (setSessionBlack)", ".local", try repeatMeasure(runs) {
            try repository.setSessionBlack(blackTargets[$0].id, true)
        })

        // Rimborso di un incasso (.archive): operazione economica reale sui movimenti.
        let payments = try context.fetch(FetchDescriptor<LedgerEntry>(
            predicate: #Predicate { $0.kindRaw == "payment" && $0.originalEntryID == nil && $0.amountCents > 1000 }))
        report("registra rimborso (recordRefund)", ".archive", try repeatMeasure(runs) {
            _ = try repository.recordRefund(paymentID: payments[$0].id, amountCents: 500,
                                            date: payments[$0].date.addingTimeInterval(60), notes: "Prova")
        })

        // Spostamento (.local): a un orario libero domenicale, lontano da altri appuntamenti.
        report("sposta appuntamento (rescheduleSession)", ".local", try repeatMeasure(runs) {
            let day = SchedulingSuggestions.calendar.date(byAdding: .day, value: 6 + $0 * 7, to: data.currentWeekStart)!
            try repository.rescheduleSession(moveTargets[$0].id, to: day.addingTimeInterval(9 * 3600))
        })

        // Annullamento (.local).
        report("annulla appuntamento (setSessionStatus cancelled)", ".local", try repeatMeasure(runs) {
            try repository.setSessionStatus(cancelTargets[$0].id, to: .cancelled)
        })

        // Creazione appuntamento (.local), in una settimana libera dopo quelle generate.
        let client = data.clients[0]
        let service = data.services[0]
        let created = try repeatMeasure(runs) { index in
            var draft = SessionDraft()
            draft.startDate = SchedulingSuggestions.calendar.date(byAdding: .day, value: 400 + index, to: data.firstMonday)!
                .addingTimeInterval(10 * 3600)
            draft.durationMinutes = 60; draft.serviceID = service.id; draft.serviceName = service.name
            draft.participants = [ParticipantDraft(clientID: client.id, priceCents: service.priceCents)]
            _ = try repository.saveSession(draft)
        }
        report("crea appuntamento (saveSession)", ".local", created)

        // Operazioni .archive su altre entità.
        report("acquisto pacchetto (savePackage)", ".archive", try repeatMeasure(runs) { index in
            var draft = PackageDraft()
            draft.clientID = data.clients[index].id; draft.priceCents = 40_000
            draft.purchasedOn = data.currentWeekStart; draft.capacity = 10
            _ = try repository.savePackage(draft)
        })
        report("crea indisponibilità (saveBlock)", ".archive", try repeatMeasure(runs) { index in
            var draft = BlockDraft()
            let day = SchedulingSuggestions.calendar.date(byAdding: .day, value: 500 + index, to: data.firstMonday)!
            draft.startDate = day.addingTimeInterval(9 * 3600); draft.endDate = day.addingTimeInterval(11 * 3600)
            draft.title = "Ferie \(index)"
            _ = try repository.saveBlock(draft)
        })
    }
}

private extension Array {
    func shuffled(using rng: inout AgendaWeeklyBenchmarkTests.Rng) -> [Element] {
        var copy = self
        for index in stride(from: copy.count - 1, to: 0, by: -1) {
            copy.swapAt(index, rng.next(index + 1))
        }
        return copy
    }
}
