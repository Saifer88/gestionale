import Foundation
@testable import PaolaApp
@testable import PaolaCore
import SwiftData
import XCTest

/// Genera un backup cifrato con dati INVENTATI per provare l'app con un archivio grande.
/// Disattivato di default: si attiva con `PAOLA_GENERATE_TEST_BACKUP=1`.
/// Scrive solo in `build/test-backup/` (mai nell'archivio reale né su iCloud).
@MainActor
final class LargeTestBackupGeneratorTests: XCTestCase {
    static let password = "Prova-Backup-2025-xK9!"
    static let fileName = "Paola-backup-TEST-grande.paolabackup"

    private struct Rng {
        var state: UInt64
        mutating func next(_ upper: Int) -> Int {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Int((state >> 33) % UInt64(upper))
        }
    }

    private struct Counts: Equatable {
        var clients = 0, services = 0, rates = 0, sessions = 0, participants = 0
        var packages = 0, timedPackages = 0, exhaustedPackages = 0, uses = 0, ledger = 0, blocks = 0
        var completed = 0, planned = 0, cancelled = 0, noShow = 0, provisional = 0, multi = 0
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: PaolaSchemaV16.self)
        return try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
    }

    // MARK: - Generatore

    private func populate(_ context: ModelContext) throws {
        context.autosaveEnabled = false
        let calendar = SchedulingSuggestions.calendar
        let now = Date()
        var rng = Rng(state: 2025)
        let currentMonday = calendar.dateInterval(of: .weekOfYear, for: now)!.start
        let weeks = 22, pastWeeks = 18 // 18 passate + settimana corrente + 3 future
        let firstMonday = calendar.date(byAdding: .weekOfYear, value: -pastWeeks, to: currentMonday)!

        // 40 clienti inventati.
        let firstNames = ["Anna", "Bruno", "Carla", "Dario", "Elena", "Fabio", "Giulia", "Hugo", "Irene", "Luca"]
        let lastNames = ["Rossi", "Bianchi", "Verdi", "Neri", "Gallo", "Conti", "Greco", "Fontana"]
        var clients: [Client] = []
        for index in 0..<40 {
            let client = Client(firstName: firstNames[index % 10], lastName: "\(lastNames[(index / 10 + index) % 8]) Prova\(index + 1)",
                                phone: "300000\(String(format: "%04d", index))", email: "cliente\(index + 1)@example.com",
                                joinedOn: calendar.date(byAdding: .day, value: -30, to: firstMonday)!)
            context.insert(client)
            clients.append(client)
        }

        // 30 servizi, 2-5 tariffe nominate ciascuno.
        let serviceNames = ["Personal training", "Allenamento funzionale", "Pilates matwork", "Stretching guidato", "Yoga base",
            "Yoga avanzato", "Postura e mobilità", "Circuito metabolico", "Preparazione atletica", "Ginnastica dolce",
            "Total body", "Core stability", "Allenamento over 60", "Dimagrimento", "Tonificazione", "Boxe fitness",
            "Kettlebell", "TRX", "Corsa guidata", "Mobilità articolare", "Allenamento a coppie", "Small group",
            "Pre-parto fitness", "Allenamento giovani", "Cardio coach", "Forza base", "Ipertrofia", "Respirazione e rilassamento",
            "Valutazione iniziale", "Lezione di prova"]
        let rateNames = ["Standard", "Ridotta", "Coppia", "Studenti", "Gruppo", "Over 60"]
        var services: [TrainingService] = []
        var ratesByService: [UUID: [ServiceRate]] = [:]
        var counts = Counts()
        for (index, name) in serviceNames.enumerated() {
            let base = Int64(3000 + index * 150)
            let service = TrainingService(name: name, durationMinutes: [30, 45, 60, 60, 90][index % 5], priceCents: base)
            context.insert(service)
            services.append(service)
            for order in 0..<(2 + index % 4) {
                let rate = ServiceRate(serviceID: service.id, name: rateNames[order],
                                       priceCents: base - Int64(order) * 250, sortOrder: order)
                context.insert(rate)
                ratesByService[service.id, default: []].append(rate)
                counts.rates += 1
            }
        }

        // Pacchetti.
        var lessonPackages: [UUID: (package: LessonPackage, assigned: Int)] = [:]
        var timedPackages: [UUID: LessonPackage] = [:]
        func addPackage(_ client: Client, on date: Date, price: Int64, capacity: Int, kind: PackageKind,
                        months: Int = 0) -> LessonPackage {
            let expiry = kind == .timed
                ? Calendar.current.date(byAdding: .month, value: months, to: Calendar.current.startOfDay(for: date)) : nil
            let package = LessonPackage(clientID: client.id, clientName: client.fullName, purchasedOn: date,
                priceCents: price, capacity: capacity, expiresOn: expiry,
                notes: kind == .timed ? "Pacchetto a tempo \(months) mesi" : "Pacchetto \(capacity) lezioni",
                paymentMethod: .bankTransfer, kind: kind)
            context.insert(package)
            context.insert(LedgerEntry(clientID: client.id, clientName: client.fullName, date: date, kind: .charge,
                amountCents: price, notes: package.notes, sourceKey: BusinessRules.packageSource(package.id)))
            context.insert(LedgerEntry(clientID: client.id, clientName: client.fullName, date: date, kind: .payment,
                amountCents: price, method: .bankTransfer, notes: package.notes,
                sourceKey: BusinessRules.packageIncomeSource(package.id)))
            counts.packages += 1; counts.ledger += 2
            if kind == .timed { counts.timedPackages += 1 }
            return package
        }

        // Slot: lunedì-sabato, ogni ora dalle 7:00 alle 19:00.
        let allSlots = (0..<6).flatMap { day in stride(from: 7 * 60, to: 20 * 60, by: 60).map { (day: day, minutes: $0) } }

        for week in 0..<weeks {
            let weekStart = calendar.date(byAdding: .weekOfYear, value: week, to: firstMonday)!
            var slots = allSlots
            for index in stride(from: slots.count - 1, to: 0, by: -1) { slots.swapAt(index, rng.next(index + 1)) }
            slots = Array(slots.prefix(34 + rng.next(5))).sorted { ($0.day, $0.minutes) < ($1.day, $1.minutes) }
            for (index, slot) in slots.enumerated() {
                let day = calendar.date(byAdding: .day, value: slot.day, to: weekStart)!
                let shift = index % 17 == 0 ? 30 : 0 // sovrapposizioni
                let start = calendar.date(byAdding: .minute, value: slot.minutes + shift, to: day)!
                let service = services[rng.next(services.count)]
                let rates = ratesByService[service.id] ?? []
                let rate = rates[rng.next(rates.count)]
                var status: SessionStatus = .planned
                if start < now {
                    let roll = rng.next(100)
                    status = roll < 85 ? .completed : roll < 92 ? .cancelled : roll < 97 ? .noShow : .planned
                } else if rng.next(100) < 8 {
                    status = .provisional
                }
                let session = TrainingSession(startDate: start, durationMinutes: service.durationMinutes,
                    serviceID: service.id, serviceName: service.name, status: status, isBlack: rng.next(100) < 40)
                context.insert(session)
                counts.sessions += 1
                switch status {
                case .completed: counts.completed += 1
                case .cancelled: counts.cancelled += 1
                case .noShow: counts.noShow += 1
                case .provisional: counts.provisional += 1
                default: counts.planned += 1
                }
                let people = index % 7 == 0 ? 2 : 1
                if people == 2 { counts.multi += 1 }
                var chosen = Set<Int>()
                while chosen.count < people { chosen.insert(rng.next(clients.count)) }
                for clientIndex in chosen.sorted() {
                    let client = clients[clientIndex]
                    var packageID: UUID?
                    if status != .cancelled, status != .noShow, rng.next(100) < 55 {
                        if clientIndex < 24 { // pacchetti a lezioni (10), poi esauriti e rinnovati
                            var state = lessonPackages[client.id]
                            if state == nil || state!.assigned >= state!.package.capacity {
                                let purchase = calendar.date(byAdding: .day, value: -1, to: start)!
                                state = (addPackage(client, on: purchase, price: 40_000, capacity: 10, kind: .lessons), 0)
                            }
                            state!.assigned += 1
                            lessonPackages[client.id] = state
                            packageID = state!.package.id
                        } else if clientIndex < 32 { // pacchetti a tempo (3 mesi)
                            var package = timedPackages[client.id]
                            if package == nil || start >= package!.expiresOn! {
                                let purchase = calendar.date(byAdding: .day, value: -1, to: start)!
                                package = addPackage(client, on: purchase, price: 25_000, capacity: 1, kind: .timed, months: 3)
                                timedPackages[client.id] = package
                            }
                            packageID = package!.id
                        }
                    }
                    let price = people == 2 ? rates.last!.priceCents : rate.priceCents
                    let method: PaymentMethod = rng.next(100) < 70 ? .cash : .bankTransfer
                    let paysNow = status == .completed && packageID == nil && rng.next(100) < 85
                    context.insert(SessionParticipant(sessionID: session.id, clientID: client.id,
                        clientName: client.fullName, priceCents: price, packageID: packageID,
                        paymentMethod: method, isPaid: paysNow))
                    counts.participants += 1
                    guard status == .completed else { continue }
                    let source = BusinessRules.sessionSource(sessionID: session.id, clientID: client.id)
                    if let packageID {
                        context.insert(PackageUse(packageID: packageID, sessionID: session.id,
                                                  clientID: client.id, sourceKey: source))
                        counts.uses += 1
                    } else {
                        context.insert(LedgerEntry(clientID: client.id, clientName: client.fullName, date: start,
                            kind: .charge, amountCents: price, notes: service.name, sourceKey: source))
                        counts.ledger += 1
                        if paysNow {
                            context.insert(LedgerEntry(clientID: client.id, clientName: client.fullName, date: start,
                                kind: .payment, amountCents: price, method: method, notes: service.name,
                                sourceKey: BusinessRules.sessionIncomeSource(sessionID: session.id, clientID: client.id)))
                            counts.ledger += 1
                        }
                    }
                }
            }
            // Indisponibilità: pausa ogni 4 settimane, ferie di 3 giorni ogni 9.
            if week % 4 == 3 {
                let from = calendar.date(byAdding: .hour, value: 13, to: calendar.date(byAdding: .day, value: 2, to: weekStart)!)!
                context.insert(Unavailability(startDate: from, endDate: from.addingTimeInterval(7200), title: "Pausa pranzo lunga"))
                counts.blocks += 1
            }
            if week % 9 == 8 {
                let from = calendar.date(byAdding: .hour, value: 7, to: calendar.date(byAdding: .day, value: 4, to: weekStart)!)!
                context.insert(Unavailability(startDate: from, endDate: from.addingTimeInterval(3 * 86_400), title: "Ferie"))
                counts.blocks += 1
            }
        }
        counts.clients = clients.count
        counts.services = services.count
        try context.save()
    }

    private func summary(_ snapshot: ArchiveSnapshot) -> [String: Int] {
        let archive = snapshot.business
        let exhausted = archive.packages.filter { package in
            package.kindRaw == "lessons"
                && archive.packageUses.filter { $0.packageID == package.id }.count >= package.capacity
        }.count
        func sessions(_ status: SessionStatus) -> Int { archive.sessions.filter { $0.statusRaw == status.rawValue }.count }
        let participantsBySession = Dictionary(grouping: archive.participants, by: \.sessionID)
        return [
            "clienti": snapshot.clients.count, "servizi": archive.services.count, "tariffe": archive.rates.count,
            "appuntamenti": archive.sessions.count, "partecipanti": archive.participants.count,
            "appuntamenti con più partecipanti": participantsBySession.values.filter { $0.count > 1 }.count,
            "completati": sessions(.completed), "programmati": sessions(.planned), "annullati": sessions(.cancelled),
            "assenze": sessions(.noShow), "provvisori": sessions(.provisional),
            "pacchetti": archive.packages.count,
            "pacchetti a tempo": archive.packages.filter { $0.kindRaw == "timed" }.count,
            "pacchetti a lezioni esauriti": exhausted,
            "utilizzi pacchetto": archive.packageUses.count, "movimenti": archive.ledgerEntries.count,
            "indisponibilità": archive.blocks.count, "record totali": snapshot.recordCount,
        ]
    }

    // MARK: - Test

    func testGenerateLargeEncryptedBackup() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["PAOLA_GENERATE_TEST_BACKUP"] == "1",
                          "Impostare PAOLA_GENERATE_TEST_BACKUP=1 per generare il backup di prova.")
        let container = try makeContainer()
        let context = ModelContext(container)
        try populate(context)

        // Validazione di dominio e integrità sui dati generati.
        let snapshot = try ArchiveSnapshot.capture(context: context)
        try snapshot.validate()
        XCTAssertTrue(BusinessReports.integrityWarnings(
            entries: try context.fetch(FetchDescriptor<LedgerEntry>()),
            packages: try context.fetch(FetchDescriptor<LessonPackage>()),
            uses: try context.fetch(FetchDescriptor<PackageUse>())).isEmpty)

        let encrypted = try BackupCipher.encrypt(try snapshot.encoded(), password: Self.password)
        let directory = URL(fileURLWithPath: "/Users/pirrima001/coding/personal/paola_gestionale/build/test-backup", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(Self.fileName)
        try encrypted.write(to: url, options: [.atomic])

        // Rilettura con le stesse API del ripristino, in una cartella temporanea.
        let data = try Data(contentsOf: url)
        let decoded = try ArchiveSnapshot.decode(try BackupCipher.decrypt(data, password: Self.password))
        XCTAssertThrowsError(try BackupCipher.decrypt(data, password: "password-sbagliata-123"))
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("paola-test-backup-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        try decoded.restore(toNewStoreAt: temp.appendingPathComponent("Clienti-v1.store"))
        XCTAssertEqual(summary(decoded), summary(snapshot))

        XCTAssertEqual(decoded.clients.count, 40)
        XCTAssertEqual(decoded.business.services.count, 30)
        XCTAssertGreaterThan(decoded.business.sessions.count / 22, 30)
        XCTAssertGreaterThan(decoded.business.packages.filter { $0.kindRaw == "timed" }.count, 0)
        print("[backup] file: \(url.path) (\(data.count) byte)")
        print("[backup] password: \(Self.password)")
        for (key, value) in summary(decoded).sorted(by: { $0.key < $1.key }) { print("[backup] \(key): \(value)") }
    }
}
