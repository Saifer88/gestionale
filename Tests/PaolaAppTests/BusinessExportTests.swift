import Foundation
import PDFKit
@testable import PaolaApp
import XCTest

final class BusinessExportTests: XCTestCase {
    func testCSVRetainsEveryRowAndEscapesPersonalText() throws {
        let report = fixture(count: 250)
        let csv = try XCTUnwrap(String(data: BusinessExport.csv(report), encoding: .utf8))
        let rows = try parseCSV(csv)
        XCTAssertTrue(rows.allSatisfy { $0.count == 9 })
        let movements = rows.filter { $0.first == "Movimento" }
        XCTAssertEqual(movements.count, report.movements.count)
        for (index, row) in movements.enumerated() {
            XCTAssertEqual(row[2], "'=Nome; Jos\u{00E9}")
            XCTAssertEqual(row[6], "Nota \"citata\";\nSeconda riga \(index)")
            XCTAssertEqual(row[7], report.movements[index].id.uuidString)
            XCTAssertEqual(row[4], "50,00")
        }
        XCTAssertTrue(csv.contains("DOCUMENTO NON FISCALE"))
        for value in ["=1+1", "+SUM(A1)", "-1", "@formula", " \t=1", "\u{200B}=1"] {
            XCTAssertTrue(BusinessExport.csvCell(value, untrusted: true).hasPrefix("\"'"))
        }
    }

    func testPDFPaginatesAndKeepsEveryMovementAndAccentedName() throws {
        let report = fixture(count: 250)
        let document = try XCTUnwrap(PDFDocument(data: BusinessExport.pdf(report)))
        XCTAssertGreaterThan(document.pageCount, 2)
        let text = try XCTUnwrap(document.string)
        XCTAssertTrue(text.contains("DOCUMENTO NON FISCALE"))
        XCTAssertTrue(text.contains("Jos\u{00E9}"))
        for movement in report.movements {
            XCTAssertTrue(text.contains(movement.id.uuidString), "Movimento mancante nel PDF: \(movement.id)")
        }
        XCTAssertTrue(text.contains("Seconda riga 249"))
    }

    private func fixture(count: Int) -> BusinessReportSnapshot {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let movements = (0..<count).map { index in
            BusinessReportSnapshot.Movement(
                id: UUID(), date: date, client: "=Nome; Jos\u{00E9}", kind: "Pagamento",
                amountCents: 5000, method: "Contanti",
                notes: "Nota \"citata\";\nSeconda riga \(index)", originalID: nil
            )
        }
        return BusinessReportSnapshot(
            clientLabel: "Tutti i clienti", from: date, through: date, generatedAt: date,
            openingBalance: 0, closingBalance: -Int64(count) * 5000, chargedCents: 0,
            paidCents: Int64(count) * 5000, refundedCents: 0, creditedCents: 0,
            workedMinutes: 60, completedSessions: 1, popularHours: [10: 1],
            hourlyIncomeCents: Double(count * 5000), movements: movements, unpaid: []
        )
    }

    private func parseCSV(_ source: String) throws -> [[String]] {
        let characters = Array(source.trimmingCharacters(in: CharacterSet(charactersIn: "\u{FEFF}")))
        var rows: [[String]] = []
        var row: [String] = []
        var value = ""
        var quoted = false
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character == "\"" {
                if quoted && index + 1 < characters.count && characters[index + 1] == "\"" {
                    value.append("\"")
                    index += 1
                } else { quoted.toggle() }
            } else if !quoted && character == ";" {
                row.append(value)
                value = ""
            } else if !quoted && (character == "\r\n" || character == "\n" || character == "\r") {
                row.append(value)
                rows.append(row)
                row = []
                value = ""
            } else {
                value.append(character)
            }
            index += 1
        }
        XCTAssertFalse(quoted, "CSV con virgolette non terminate")
        if !value.isEmpty || !row.isEmpty { row.append(value); rows.append(row) }
        return rows
    }
}
