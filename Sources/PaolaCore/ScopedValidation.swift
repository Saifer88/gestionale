import Foundation
import SwiftData

/// Validazione mirata, eseguita dopo la scrittura del completamento di una lezione.
///
/// Legge con predicati solo ciò che il completamento può toccare (lezioni, partecipanti,
/// clienti, servizi, pacchetti, utilizzi, movimenti e commissioni identificati dalle loro
/// `sourceKey`) e applica le stesse regole per-entità di `BusinessArchive.validate`
/// (`BusinessArchiveRules`). Le regole globali (identificativi duplicati, rettifiche
/// cumulative, fatture, corsi, blocchi) non cambiano con un completamento e restano alla
/// validazione completa (`ArchiveHealthChecker`).
enum ScopedValidation {
    static func validate(sessionIDs: Set<UUID>, in writer: ModelContext) throws {
        guard !sessionIDs.isEmpty else { return }
        let sessionIDList = Array(sessionIDs)
        let sessions = try writer.fetch(FetchDescriptor<TrainingSession>(
            predicate: #Predicate { sessionIDList.contains($0.id) })).map(BusinessArchive.SessionRecord.init)
        let participants = try writer.fetch(FetchDescriptor<SessionParticipant>(
            predicate: #Predicate { sessionIDList.contains($0.sessionID) })).map(BusinessArchive.ParticipantRecord.init)
        try BusinessArchiveRules.require(sessions.count == sessionIDs.count, "Lezione non trovata.")

        let clientIDList = Array(Set(participants.map(\.clientID)))
        let clientIDs = Set(try writer.fetch(FetchDescriptor<Client>(
            predicate: #Predicate { clientIDList.contains($0.id) })).map(\.id))
        let serviceIDList = Array(Set(sessions.compactMap(\.serviceID)))
        let serviceIDs = serviceIDList.isEmpty ? [] : Set(try writer.fetch(FetchDescriptor<TrainingService>(
            predicate: #Predicate { serviceIDList.contains($0.id) })).map(\.id))
        let packageIDList = Array(Set(participants.compactMap(\.packageID)))
        let packages = packageIDList.isEmpty ? [] : try writer.fetch(FetchDescriptor<LessonPackage>(
            predicate: #Predicate { packageIDList.contains($0.id) })).map(BusinessArchive.PackageRecord.init)

        // Utilizzi della lezione (regole complete) e dei pacchetti coinvolti (solo capienza).
        var usesByID: [UUID: BusinessArchive.PackageUseRecord] = [:]
        let sessionUses = try writer.fetch(FetchDescriptor<PackageUse>(
            predicate: #Predicate { sessionIDList.contains($0.sessionID) })).map(BusinessArchive.PackageUseRecord.init)
        for use in sessionUses { usesByID[use.id] = use }
        if !packageIDList.isEmpty {
            for use in try writer.fetch(FetchDescriptor<PackageUse>(
                predicate: #Predicate { packageIDList.contains($0.packageID) })) {
                usesByID[use.id] = BusinessArchive.PackageUseRecord(use)
            }
        }

        // Movimenti e commissioni generati dal completamento (chiavi minuscole).
        var ledgerKeys = Set<String>()
        var feeKeys = Set<String>()
        for participant in participants {
            ledgerKeys.insert(BusinessRules.sessionSource(sessionID: participant.sessionID, clientID: participant.clientID))
            ledgerKeys.insert(BusinessRules.sessionIncomeSource(sessionID: participant.sessionID, clientID: participant.clientID))
            feeKeys.insert(Expense.sessionFeeSourceKey(sessionID: participant.sessionID, clientID: participant.clientID).lowercased())
        }
        let ledgerKeyList = Array(ledgerKeys)
        let feeKeyList = Array(feeKeys)
        let entries = try writer.fetch(FetchDescriptor<LedgerEntry>(
            predicate: #Predicate { ledgerKeyList.contains($0.sourceKey) })).map(BusinessArchive.LedgerRecord.init)
        let expenses = try writer.fetch(FetchDescriptor<Expense>(
            predicate: #Predicate { feeKeyList.contains($0.sourceKey) })).map(BusinessArchive.ExpenseRecord.init)

        // Regole per-entità.
        let sessionMap = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
        let packageMap = Dictionary(uniqueKeysWithValues: packages.map { ($0.id, $0) })
        let participantsBySession = Dictionary(grouping: participants, by: \.sessionID)
        for session in sessions {
            try BusinessArchiveRules.session(session, serviceIDs: serviceIDs,
                                             participants: participantsBySession[session.id] ?? [])
        }
        for package in packages { try BusinessArchiveRules.package(package, clientIDs: clientIDs) }
        for participant in participants {
            try BusinessArchiveRules.participant(participant, session: sessionMap[participant.sessionID],
                package: participant.packageID.flatMap { packageMap[$0] }, clientIDs: clientIDs)
        }
        var useSources: [String: BusinessArchive.PackageUseRecord] = [:]
        for use in usesByID.values {
            let source: String
            if sessionIDs.contains(use.sessionID) {
                source = try BusinessArchiveRules.packageUse(use, session: sessionMap[use.sessionID],
                    package: packageMap[use.packageID], sessionParticipants: participantsBySession[use.sessionID] ?? [])
            } else {
                source = BusinessRules.sessionSource(sessionID: use.sessionID, clientID: use.clientID)
            }
            try BusinessArchiveRules.registerUse(use, source: source, into: &useSources)
        }
        var useCounts: [UUID: Int] = [:]
        for use in useSources.values { useCounts[use.packageID, default: 0] += 1 }
        for package in packages {
            try BusinessArchiveRules.packageCapacity(package, usedCount: useCounts[package.id, default: 0])
        }
        var sources: [String: BusinessArchive.LedgerRecord] = [:]
        for entry in entries {
            let kind = try BusinessArchiveRules.ledgerEntry(entry, clientIDs: clientIDs)
            try BusinessArchiveRules.registerSource(entry, into: &sources)
            try BusinessArchiveRules.adjustmentLink(entry, kind: kind, original: nil)
        }
        for session in sessions {
            try BusinessArchiveRules.sessionEconomics(session: session, participants: participantsBySession[session.id] ?? [],
                                                      sources: sources, useSources: useSources)
        }
        for expense in expenses { try BusinessArchiveRules.expense(expense) }
    }
}
