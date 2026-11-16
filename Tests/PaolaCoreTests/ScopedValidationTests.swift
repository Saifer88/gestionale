import Foundation
@testable import PaolaCore
import SwiftData
import XCTest

/// Validazione mirata del completamento (`Validation.scoped`): stessi esiti economici della
/// validazione completa, idempotenza e rifiuto dei dati incoerenti.
@MainActor
final class ScopedValidationTests: XCTestCase {
    private struct Env {
        let container: ModelContainer
        let context: ModelContext
        let repository: BusinessRepository
    }

    private func makeEnv(forceFull: Bool = false) throws -> Env {
        let container = try StoreFactory.makeContainer(inMemory: true)
        let context = container.mainContext
        let repository = BusinessRepository(context: context)
        repository.forceFullValidation = forceFull
        return Env(container: container, context: context, repository: repository)
    }

    private func count<T: PersistentModel>(_ type: T.Type, _ env: Env) throws -> Int {
        try ModelContext(env.container).fetchCount(FetchDescriptor<T>())
    }

    private func counts(_ env: Env) throws -> [Int] {
        [try count(LedgerEntry.self, env), try count(PackageUse.self, env), try count(Expense.self, env)]
    }

    private func newSession(_ env: Env, _ participants: [ParticipantDraft], day: Int) throws -> UUID {
        var draft = BusinessTestStore.session(try XCTUnwrap(env.context.fetch(FetchDescriptor<Client>()).first), day: day)
        draft.participants = participants
        return try env.repository.saveSession(draft)
    }

    private func participantID(_ env: Env, session: UUID, client: UUID) throws -> SessionParticipant {
        try XCTUnwrap(ModelContext(env.container).fetch(FetchDescriptor<SessionParticipant>(
            predicate: #Predicate { $0.sessionID == session && $0.clientID == client })).first)
    }

    // MARK: 1. Doppio completamento

    func testDoubleCompletionKeepsEveryRecordCount() throws {
        let env = try makeEnv()
        let clients = try ["Anna", "Bruno", "Carlo"].map { try BusinessTestStore.addClient(env.context, name: $0) }
        let packageID = try env.repository.savePackage(BusinessTestStore.package(clients[1]))
        let single = try newSession(env, [ParticipantDraft(clientID: clients[0].id, priceCents: 5000)], day: 1)
        let packaged = try newSession(env, [ParticipantDraft(clientID: clients[1].id, priceCents: 4000, packageID: packageID)], day: 2)
        let group = try newSession(env, [
            ParticipantDraft(clientID: clients[0].id, priceCents: 5000, paymentMethod: .stripe),
            ParticipantDraft(clientID: clients[1].id, priceCents: 4000, packageID: packageID),
            ParticipantDraft(clientID: clients[2].id, priceCents: 3500)], day: 3)
        for id in [single, packaged, group] {
            try env.repository.setSessionStatus(id, to: .completed)
            let first = try counts(env)
            let archive = try BusinessArchive.capture(context: ModelContext(env.container))
            try env.repository.setSessionStatus(id, to: .completed)
            XCTAssertEqual(try counts(env), first)
            XCTAssertEqual(try BusinessArchive.capture(context: ModelContext(env.container)), archive)
        }
        XCTAssertEqual(try count(PackageUse.self, env), 2)
        // Le sourceKey dei movimenti restano univoche.
        let keys = try ModelContext(env.container).fetch(FetchDescriptor<LedgerEntry>()).map { $0.sourceKey.lowercased() }
        XCTAssertEqual(Set(keys).count, keys.count)
    }

    // MARK: 2. Saldi identici tra validazione completa e mirata

    private struct Outcome: Equatable {
        var balances: [Int64]
        var totals: [Int64]
        var charges: Int
        var payments: Int
        var uses: Int
        var remaining: Int
        var fees: Int64
    }

    private func runScenario(forceFull: Bool) throws -> Outcome {
        let env = try makeEnv(forceFull: forceFull)
        let clients = try ["Anna", "Bruno", "Carlo"].map { try BusinessTestStore.addClient(env.context, name: $0) }
        var package = BusinessTestStore.package(clients[0], price: 30000)
        package.capacity = 2
        let packageID = try env.repository.savePackage(package)
        let sessions = [
            try newSession(env, [ParticipantDraft(clientID: clients[0].id, priceCents: 5000, packageID: packageID)], day: 1),
            try newSession(env, [ParticipantDraft(clientID: clients[1].id, priceCents: 4999, paymentMethod: .stripe)], day: 2),
            try newSession(env, [
                ParticipantDraft(clientID: clients[0].id, priceCents: 5000, packageID: packageID),
                ParticipantDraft(clientID: clients[1].id, priceCents: 3333, paymentMethod: .card),
                ParticipantDraft(clientID: clients[2].id, priceCents: 0)], day: 3)
        ]
        for id in sessions { try env.repository.setSessionStatus(id, to: .completed) }
        let reader = ModelContext(env.container)
        let entries = try reader.fetch(FetchDescriptor<LedgerEntry>())
        let packages = try reader.fetch(FetchDescriptor<LessonPackage>())
        let uses = try reader.fetch(FetchDescriptor<PackageUse>())
        try BusinessArchive.capture(context: reader).validate(clientIDs: Set(clients.map(\.id)))
        XCTAssertTrue(BusinessReports.integrityWarnings(entries: entries, packages: packages, uses: uses).isEmpty)
        let canonical = try BusinessReports.canonicalEntries(entries)
        func total(_ kind: LedgerKind) -> Int64 { canonical.filter { $0.kind == kind }.reduce(0) { $0 + $1.amountCents } }
        return Outcome(
            balances: clients.map { BusinessReports.balance(clientID: $0.id, entries: entries) },
            totals: [total(.charge), total(.payment)],
            charges: canonical.filter { $0.kind == .charge }.count,
            payments: canonical.filter { $0.kind == .payment }.count,
            uses: uses.count,
            remaining: BusinessReports.remaining(package: packages[0], uses: uses),
            fees: try reader.fetch(FetchDescriptor<Expense>()).reduce(0) { $0 + $1.amountCents })
    }

    func testBalancesAreIdenticalBetweenFullAndScopedValidation() throws {
        let full = try runScenario(forceFull: true)
        let scoped = try runScenario(forceFull: false)
        XCTAssertEqual(full, scoped)
        XCTAssertEqual(scoped.uses, 2)
        XCTAssertEqual(scoped.remaining, 0)
        // Anna: pacchetto 30000 pagato, lezioni a pacchetto senza addebito. Bruno e Carlo: lezioni pagate.
        XCTAssertEqual(scoped.balances, [0, 0, 0])
    }

    // MARK: 3-4. Pacchetto esaurito, scaduto, di altro cliente

    func testExhaustedPackageIsRejectedWithoutPartialWrites() throws {
        let env = try makeEnv()
        let client = try BusinessTestStore.addClient(env.context)
        var package = BusinessTestStore.package(client)
        package.capacity = 1
        let packageID = try env.repository.savePackage(package)
        let first = try newSession(env, [ParticipantDraft(clientID: client.id, priceCents: 5000, packageID: packageID)], day: 1)
        let second = try newSession(env, [ParticipantDraft(clientID: client.id, priceCents: 5000, packageID: packageID)], day: 2)
        try env.repository.setSessionStatus(first, to: .completed)
        let before = try counts(env)
        XCTAssertThrowsError(try env.repository.setSessionStatus(second, to: .completed)) {
            guard case BusinessError.packageExhausted = $0 else { return XCTFail("\($0)") }
        }
        XCTAssertEqual(try counts(env), before)
        let status = try XCTUnwrap(ModelContext(env.container).fetch(FetchDescriptor<TrainingSession>(
            predicate: #Predicate { $0.id == second })).first).status
        XCTAssertEqual(status, .planned)
    }

    func testExpiredPackageIsRejected() throws {
        let env = try makeEnv()
        let client = try BusinessTestStore.addClient(env.context)
        var package = BusinessTestStore.package(client)
        package.expiresOn = BusinessTestStore.date.addingTimeInterval(10 * 86_400)
        let packageID = try env.repository.savePackage(package)
        let session = try newSession(env, [ParticipantDraft(clientID: client.id, priceCents: 5000, packageID: packageID)], day: 5)
        let writer = ModelContext(env.container)
        let stored = try XCTUnwrap(writer.fetch(FetchDescriptor<LessonPackage>(predicate: #Predicate { $0.id == packageID })).first)
        stored.expiresOn = BusinessTestStore.date.addingTimeInterval(2 * 86_400)
        try writer.save()
        let before = try counts(env)
        XCTAssertThrowsError(try env.repository.setSessionStatus(session, to: .completed))
        XCTAssertEqual(try counts(env), before)
    }

    func testPackageOfAnotherClientIsRejected() throws {
        let env = try makeEnv()
        let owner = try BusinessTestStore.addClient(env.context, name: "Anna")
        let other = try BusinessTestStore.addClient(env.context, name: "Bruno")
        let packageID = try env.repository.savePackage(BusinessTestStore.package(owner))
        let session = try newSession(env, [ParticipantDraft(clientID: other.id, priceCents: 5000)], day: 1)
        let writer = ModelContext(env.container)
        let participant = try XCTUnwrap(writer.fetch(FetchDescriptor<SessionParticipant>(
            predicate: #Predicate { $0.sessionID == session })).first)
        participant.packageID = packageID
        try writer.save()
        let before = try counts(env)
        XCTAssertThrowsError(try env.repository.setSessionStatus(session, to: .completed))
        XCTAssertEqual(try counts(env), before)
    }

    // MARK: 5. Partecipanti multipli

    func testFailedMultiParticipantCompletionLeavesNothingBehind() throws {
        let env = try makeEnv()
        let clients = try ["Anna", "Bruno"].map { try BusinessTestStore.addClient(env.context, name: $0) }
        let session = try newSession(env, [
            ParticipantDraft(clientID: clients[0].id, priceCents: 5000),
            ParticipantDraft(clientID: clients[1].id, priceCents: 4000)], day: 1)
        let writer = ModelContext(env.container)
        let archivedID = clients[1].id
        let archived = try XCTUnwrap(writer.fetch(FetchDescriptor<Client>(
            predicate: #Predicate { $0.id == archivedID })).first)
        archived.isArchived = true
        try writer.save()
        XCTAssertThrowsError(try env.repository.setSessionStatus(session, to: .completed))
        XCTAssertEqual(try counts(env), [0, 0, 0])
        let status = try XCTUnwrap(ModelContext(env.container).fetch(FetchDescriptor<TrainingSession>(
            predicate: #Predicate { $0.id == session })).first).status
        XCTAssertEqual(status, .planned)
    }

    // MARK: 6. Corruzioni seminate

    private func seedCharge(_ env: Env, session: UUID, client: Client, amount: Int64) throws {
        let writer = ModelContext(env.container)
        writer.insert(LedgerEntry(clientID: client.id, clientName: client.fullName, date: BusinessTestStore.date,
            kind: .charge, amountCents: amount, notes: "seed",
            sourceKey: BusinessRules.sessionSource(sessionID: session, clientID: client.id)))
        try writer.save()
    }

    func testChargeForPackageLessonIsRejected() throws {
        let env = try makeEnv()
        let client = try BusinessTestStore.addClient(env.context)
        let packageID = try env.repository.savePackage(BusinessTestStore.package(client))
        let session = try newSession(env, [ParticipantDraft(clientID: client.id, priceCents: 5000, packageID: packageID)], day: 1)
        try seedCharge(env, session: session, client: client, amount: 5000)
        let before = try counts(env)
        XCTAssertThrowsError(try env.repository.setSessionStatus(session, to: .completed)) {
            guard case BusinessError.inconsistentData = $0 else { return XCTFail("\($0)") }
        }
        XCTAssertEqual(try counts(env), before)
    }

    func testSameSourceKeyWithDifferentAmountIsRejected() throws {
        let env = try makeEnv()
        let client = try BusinessTestStore.addClient(env.context)
        let session = try newSession(env, [ParticipantDraft(clientID: client.id, priceCents: 5000)], day: 1)
        try seedCharge(env, session: session, client: client, amount: 4000)
        XCTAssertThrowsError(try env.repository.setSessionStatus(session, to: .completed)) {
            guard case BusinessError.inconsistentData = $0 else { return XCTFail("\($0)") }
        }
    }

    // MARK: 7. Parità delle regole (corpus di mutazioni)

    func testScopedAndFullValidationAgreeOnMutationCorpus() throws {
        typealias Mutation = (name: String, apply: (Env, UUID, Client, UUID) throws -> Void)
        let mutations: [Mutation] = [
            ("nessuna", { _, _, _, _ in }),
            ("addebito diverso", { env, session, client, _ in try self.seedCharge(env, session: session, client: client, amount: 4000) }),
            ("addebito uguale", { env, session, client, _ in try self.seedCharge(env, session: session, client: client, amount: 5000) }),
            ("incasso con importo diverso", { env, session, client, _ in
                let writer = ModelContext(env.container)
                writer.insert(LedgerEntry(clientID: client.id, clientName: client.fullName, date: BusinessTestStore.date,
                    kind: .payment, amountCents: 100, notes: "seed",
                    sourceKey: BusinessRules.sessionIncomeSource(sessionID: session, clientID: client.id)))
                try writer.save()
            }),
            ("utilizzo di un altro pacchetto", { env, session, client, packageID in
                let writer = ModelContext(env.container)
                writer.insert(PackageUse(packageID: packageID, sessionID: session, clientID: client.id,
                    sourceKey: BusinessRules.sessionSource(sessionID: session, clientID: client.id)))
                try writer.save()
            }),
            ("prezzo partecipante negativo", { env, session, _, _ in
                let writer = ModelContext(env.container)
                try writer.fetch(FetchDescriptor<SessionParticipant>(predicate: #Predicate { $0.sessionID == session }))
                    .forEach { $0.priceCents = -1 }
                try writer.save()
            })
        ]
        for mutation in mutations {
            var outcomes: [Bool] = []
            for forceFull in [true, false] {
                let env = try makeEnv(forceFull: forceFull)
                let client = try BusinessTestStore.addClient(env.context)
                let packageID = try env.repository.savePackage(BusinessTestStore.package(client))
                let session = try newSession(env, [ParticipantDraft(clientID: client.id, priceCents: 5000)], day: 1)
                try mutation.apply(env, session, client, packageID)
                do { try env.repository.setSessionStatus(session, to: .completed); outcomes.append(true) } catch { outcomes.append(false) }
            }
            XCTAssertEqual(outcomes[0], outcomes[1], "Esiti diversi per: \(mutation.name)")
        }
    }

    // MARK: 8. Incoerenza non correlata

    func testUnrelatedCorruptionDoesNotBlockScopedButIsReportedByHealthChecker() async throws {
        let env = try makeEnv()
        let client = try BusinessTestStore.addClient(env.context)
        let session = try newSession(env, [ParticipantDraft(clientID: client.id, priceCents: 5000)], day: 1)
        let writer = ModelContext(env.container)
        writer.insert(Expense(name: "Spesa seminata", amountCents: -500, sourceKey: "seed:unrelated"))
        try writer.save()
        // La validazione mirata completa comunque la lezione.
        try env.repository.setSessionStatus(session, to: .completed)
        XCTAssertEqual(try count(LedgerEntry.self, env), 2)
        // Quella completa rifiuta l'operazione (comportamento precedente) e lo segnala all'health checker.
        let strict = BusinessRepository(context: env.context)
        strict.forceFullValidation = true
        let second = try newSession(env, [ParticipantDraft(clientID: client.id, priceCents: 5000)], day: 2)
        XCTAssertThrowsError(try strict.setSessionStatus(second, to: .completed))
        let message = try await ArchiveHealthChecker(modelContainer: env.container).fullValidation()
        XCTAssertNotNil(message)
    }

    // MARK: 9. Sedute completate congelate, deleteSession ancora completa

    func testCompletedSessionStaysFrozenAndDeleteSessionRemovesItsEffects() throws {
        let env = try makeEnv()
        let client = try BusinessTestStore.addClient(env.context)
        let packageID = try env.repository.savePackage(BusinessTestStore.package(client))
        let single = try newSession(env, [ParticipantDraft(clientID: client.id, priceCents: 5000, paymentMethod: .stripe)], day: 1)
        let packaged = try newSession(env, [ParticipantDraft(clientID: client.id, priceCents: 5000, packageID: packageID)], day: 2)
        try env.repository.setSessionStatus(single, to: .completed)
        try env.repository.setSessionStatus(packaged, to: .completed)
        XCTAssertThrowsError(try env.repository.rescheduleSession(single, to: BusinessTestStore.date.addingTimeInterval(9 * 86_400))) {
            guard case BusinessError.completedSessionLocked = $0 else { return XCTFail("\($0)") }
        }
        XCTAssertThrowsError(try env.repository.setSessionStatus(single, to: .cancelled)) {
            guard case BusinessError.completedSessionLocked = $0 else { return XCTFail("\($0)") }
        }
        try env.repository.deleteSession(single)
        try env.repository.deleteSession(packaged)
        // Restano solo addebito e incasso del pacchetto; la commissione Stripe è stata rimossa.
        XCTAssertEqual(try count(LedgerEntry.self, env), 2)
        XCTAssertEqual(try count(PackageUse.self, env), 0)
        XCTAssertEqual(try count(Expense.self, env), 0)
        try BusinessArchive.capture(context: ModelContext(env.container)).validate(clientIDs: [client.id])
    }
}
