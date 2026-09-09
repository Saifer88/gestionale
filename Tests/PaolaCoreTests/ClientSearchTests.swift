import PaolaCore
import XCTest

final class ClientSearchTests: XCTestCase {
    func testFiltersAndItalianTitles() {
        let client = Client(firstName: "Paola", lastName: "Rossi")
        XCTAssertTrue(ClientSearch.matches(client, query: "", filter: .active))
        XCTAssertFalse(ClientSearch.matches(client, query: "", filter: .archived))
        XCTAssertTrue(ClientSearch.matches(client, query: "", filter: .all))
        client.isArchived = true
        XCTAssertFalse(ClientSearch.matches(client, query: "", filter: .active))
        XCTAssertTrue(ClientSearch.matches(client, query: "", filter: .archived))
        XCTAssertTrue(ClientSearch.matches(client, query: "", filter: .all))
        XCTAssertEqual(ClientFilter.allCases.map(\.title), ["Attivi", "Archiviati", "Tutti"])
        XCTAssertEqual(ClientFilter.allCases.map(\.id), ["active", "archived", "all"])
    }

    func testSearchHandlesAccentsCaseAndWhitespaceInNamesAndEmail() {
        let client = Client(firstName: "Maria José", lastName: "De Rossi", email: "Maria@Example.IT")
        for query in ["", " \n\t ", "josé", "JOSE", "  maria \t de ROSSI ", "rossi maria", "MARIA@EXAMPLE", "Jose example.it"] {
            XCTAssertTrue(ClientSearch.matches(client, query: query, filter: .active), query)
        }
        for query in ["Giulia", "Verdi", "maria verdi", "absent@example.it"] {
            XCTAssertFalse(ClientSearch.matches(client, query: query, filter: .all), query)
        }
    }

    func testSearchHandlesPhoneSpacingAndFormatting() {
        let client = Client(firstName: "Paola", lastName: "Rossi", phone: "+39 (333) 123-4567")
        for query in ["3331234567", "333 123 4567", "+393331234567", "(333)123-4567", "Paola 333123"] {
            XCTAssertTrue(ClientSearch.matches(client, query: query, filter: .all), query)
        }
        client.phone = "3331234567"
        XCTAssertTrue(ClientSearch.matches(client, query: "333 123 4567", filter: .all))
        XCTAssertFalse(ClientSearch.matches(client, query: "99999", filter: .all))
        XCTAssertFalse(ClientSearch.matches(client, query: "---", filter: .all))
    }

    func testSearchDoesNotIncludeOrganizationalNotes() {
        let client = Client(firstName: "Paola", lastName: "Rossi", notes: "Disponibile pomeriggio")
        XCTAssertFalse(ClientSearch.matches(client, query: "pomeriggio", filter: .all))
    }
}
