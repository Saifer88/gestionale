import Foundation
import PaolaCore
import XCTest

func makeDraft(
    firstName: String = "Paola",
    lastName: String = "Rossi",
    phone: String = "",
    email: String = "",
    notes: String = "",
    anamnesis: String = "",
    physicalAnalysis: String = ""
) -> ClientDraft {
    var draft = ClientDraft()
    draft.firstName = firstName
    draft.lastName = lastName
    draft.phone = phone
    draft.email = email
    draft.notes = notes
    draft.anamnesis = anamnesis
    draft.physicalAnalysis = physicalAnalysis
    return draft
}

@MainActor
func withStoreFixture(_ body: (URL) throws -> Void) throws {
    let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(".paola-core-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    do {
        try body(directory)
    } catch {
        do {
            try FileManager.default.removeItem(at: directory)
        } catch {
            XCTFail("Impossibile rimuovere l'archivio temporaneo: \(error.localizedDescription)")
        }
        throw error
    }
    try FileManager.default.removeItem(at: directory)
}
