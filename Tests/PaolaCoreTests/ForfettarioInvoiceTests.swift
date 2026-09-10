import PaolaCore
import XCTest

final class ForfettarioInvoiceTests: XCTestCase {

    func testExampleSixtyEuros() throws {
        // 60,00 € -> imponibile 57,69 €, rivalsa 2,31 €.
        let b = try ForfettarioBreakdown.from(totalCents: 6000)
        XCTAssertEqual(b.taxableCents, 5769)
        XCTAssertEqual(b.contributionCents, 231)
        XCTAssertEqual(b.totalCents, 6000)
    }

    func testTaxablePlusContributionAlwaysEqualsTotal() throws {
        for total in stride(from: Int64(0), through: 20000, by: 1) {
            let b = try ForfettarioBreakdown.from(totalCents: total)
            XCTAssertEqual(b.taxableCents + b.contributionCents, total, "totale \(total)")
            XCTAssertGreaterThanOrEqual(b.taxableCents, 0)
            XCTAssertGreaterThanOrEqual(b.contributionCents, 0)
        }
    }

    func testZeroTotal() throws {
        let b = try ForfettarioBreakdown.from(totalCents: 0)
        XCTAssertEqual(b.taxableCents, 0)
        XCTAssertEqual(b.contributionCents, 0)
        XCTAssertEqual(b.totalCents, 0)
    }

    func testRoundingHalfUp() throws {
        // 50,00 € / 1,04 = 48,0769... -> 48,08 (arrotondato), rivalsa 1,92.
        let b = try ForfettarioBreakdown.from(totalCents: 5000)
        XCTAssertEqual(b.taxableCents, 4808)
        XCTAssertEqual(b.contributionCents, 192)
    }

    func testContributionIsApproximatelyFourPercentOfTaxable() throws {
        // La rivalsa deve essere ~4% dell'imponibile (entro l'arrotondamento al centesimo).
        for total in [Int64(6000), 5000, 10000, 12345, 99999] {
            let b = try ForfettarioBreakdown.from(totalCents: total)
            let expected = Int64((Double(b.taxableCents) * 0.04).rounded())
            XCTAssertLessThanOrEqual(abs(b.contributionCents - expected), 1, "totale \(total)")
        }
    }

    func testNegativeTotalIsRejected() {
        XCTAssertThrowsError(try ForfettarioBreakdown.from(totalCents: -1))
    }

    func testFixedFiscalConstants() {
        XCTAssertEqual(ForfettarioTax.naturaCode, "N2.2")
        XCTAssertEqual(ForfettarioTax.cassaType, "TC22")
        XCTAssertEqual(ForfettarioTax.cassaPercent, 4)
        XCTAssertEqual(ForfettarioTax.defaultRecipientCode, "0000000")
        XCTAssertFalse(ForfettarioTax.riferimentoNormativo.isEmpty)
    }
}
