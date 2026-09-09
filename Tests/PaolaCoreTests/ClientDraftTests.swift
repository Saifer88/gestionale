import Foundation
import PaolaCore
import XCTest

final class ClientDraftTests: XCTestCase {
    func testModelAndDraftDefaults() {
        let before = Date()
        let client = Client()
        let second = Client()
        let draft = ClientDraft()

        XCTAssertNotEqual(client.id, second.id)
        XCTAssertEqual(client.firstName, "")
        XCTAssertEqual(client.lastName, "")
        XCTAssertEqual(client.fullName, "")
        XCTAssertEqual(client.phone, "")
        XCTAssertEqual(client.email, "")
        XCTAssertEqual(client.notes, "")
        XCTAssertEqual(client.anamnesis, "")
        XCTAssertEqual(client.physicalAnalysis, "")
        XCTAssertFalse(client.isArchived)
        XCTAssertGreaterThanOrEqual(client.createdAt, before)
        XCTAssertEqual(client.updatedAt, client.createdAt)
        XCTAssertTrue(Calendar.current.isDateInToday(client.joinedOn))
        XCTAssertEqual(draft.firstName, "")
        XCTAssertEqual(draft.lastName, "")
        XCTAssertEqual(draft.phone, "")
        XCTAssertEqual(draft.email, "")
        XCTAssertEqual(draft.notes, "")
        XCTAssertEqual(draft.anamnesis, "")
        XCTAssertEqual(draft.physicalAnalysis, "")
        XCTAssertEqual(draft.joinedOn, Calendar.current.startOfDay(for: Date()))
    }

    func testBothNamesAreRequiredAfterWhitespaceNormalization() {
        for (first, last) in [("", "Rossi"), ("Paola", ""), (" \n\t ", "Rossi"), ("Paola", "\u{00A0} ")] {
            XCTAssertThrowsError(try makeDraft(firstName: first, lastName: last).validated()) {
                XCTAssertEqual($0 as? ClientValidationError, .missingName)
            }
        }
    }

    func testValidationNormalizesWithoutChangingSourceDraft() throws {
        var draft = makeDraft(
            firstName: "  Maria \t José  ",
            lastName: "\nDe  Rossi\u{00A0}",
            phone: "  +39   333 123 4567 \n",
            email: "  MARIA+LAVORO@Example.IT \n",
            notes: "\n  Preferisce il pomeriggio.\nSeconda riga.  \n",
            anamnesis: "\n  Storia clinica: già valutata 🩺\n\n  Secondo paragrafo.\t \n",
            physicalAnalysis: "\t Mobilità: così\n\n第二行  \n"
        )
        draft.joinedOn = Date(timeIntervalSince1970: 1_700_043_210)
        let normalized = try draft.validated()

        XCTAssertEqual(normalized.firstName, "Maria José")
        XCTAssertEqual(normalized.lastName, "De Rossi")
        XCTAssertEqual(normalized.phone, "+39 333 123 4567")
        XCTAssertEqual(normalized.email, "maria+lavoro@example.it")
        XCTAssertEqual(normalized.notes, "Preferisce il pomeriggio.\nSeconda riga.")
        XCTAssertEqual(normalized.anamnesis, "Storia clinica: già valutata 🩺\n\n  Secondo paragrafo.")
        XCTAssertEqual(normalized.physicalAnalysis, "Mobilità: così\n\n第二行")
        XCTAssertTrue(draft.anamnesis.hasPrefix("\n  "))
        XCTAssertTrue(draft.physicalAnalysis.hasPrefix("\t "))
        XCTAssertEqual(normalized.joinedOn, Calendar.current.startOfDay(for: draft.joinedOn))
        XCTAssertEqual(draft.firstName, "  Maria \t José  ")
        XCTAssertEqual(draft.email, "  MARIA+LAVORO@Example.IT \n")
    }

    func testContactsAndNotesAreOptional() throws {
        let normalized = try makeDraft(phone: " \t ", email: "\n ", notes: "  ",
                                       anamnesis: "\n\t", physicalAnalysis: " \n ").validated()
        XCTAssertEqual(normalized.phone, "")
        XCTAssertEqual(normalized.email, "")
        XCTAssertEqual(normalized.notes, "")
        XCTAssertEqual(normalized.anamnesis, "")
        XCTAssertEqual(normalized.physicalAnalysis, "")
    }

    func testBasicEmailValidation() throws {
        for email in [
            "paola@example.it", "paola+studio@example.travel", "o'connor@example.co.uk",
            "josé@esempio.it", "paola@xn--esempio-9za.it", "paola@esempio.città"
        ] {
            XCTAssertNoThrow(try makeDraft(email: email).validated(), email)
        }
        for email in [
            "paola", "@example.it", "paola@", "paola@@example.it", "paola@example",
            "pa ola@example.it", "paola@exam ple.it", "paola@.it", "paola@example..it",
            "paola@example.it.", ".paola@example.it", "paola..rossi@example.it",
            "paola@-example.it", "paola@example!.it", "paola@\nexample.it",
            "paola\u{0000}@example.it"
        ] {
            XCTAssertThrowsError(try makeDraft(email: email).validated(), email) {
                XCTAssertEqual($0 as? ClientValidationError, .invalidEmail, email)
            }
        }
    }

    func testJoinedOnAllowsFutureCalendarDays() throws {
        var draft = makeDraft()
        draft.joinedOn = try XCTUnwrap(Calendar.current.date(byAdding: .year, value: 2, to: Date()))
        let normalized = try draft.validated()
        XCTAssertEqual(normalized.joinedOn, Calendar.current.startOfDay(for: draft.joinedOn))
    }

    func testNonfiniteJoinedOnIsRejected() {
        for interval in [Double.nan, Double.infinity, -Double.infinity] {
            var draft = makeDraft()
            draft.joinedOn = Date(timeIntervalSinceReferenceDate: interval)
            XCTAssertThrowsError(try draft.validated()) {
                XCTAssertEqual($0 as? ClientValidationError, .invalidDate)
            }
        }
    }

    func testFullNameNormalizesSpacingWithoutRemovingAccents() {
        let client = Client(firstName: "  Maria \t José ", lastName: "  De  Rossi ")
        XCTAssertEqual(client.fullName, "Maria José De Rossi")
    }

    func testErrorsHaveItalianDescriptions() {
        for error in [
            ClientValidationError.missingName, .invalidEmail, .possibleDuplicate, .staleRecord, .invalidDate
        ] {
            XCTAssertFalse(error.localizedDescription.isEmpty)
            XCTAssertNotNil(error.errorDescription)
        }
    }
}
