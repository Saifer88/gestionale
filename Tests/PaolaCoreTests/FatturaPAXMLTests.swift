@testable import PaolaCore
import XCTest

final class FatturaPAXMLTests: XCTestCase {

    private func seller() -> FatturaPAParty {
        FatturaPAParty(name: "Mario Rossi", taxCode: "RSSMRA80A01H501U", vatNumber: "12345678901",
                       address: "Via Roma 1", postalCode: "00100", city: "Roma",
                       province: "RM", country: "IT")
    }
    private func buyer() -> FatturaPAParty {
        FatturaPAParty(name: "Anna Bianchi", taxCode: "BNCNNA85M41H501T", vatNumber: nil,
                       address: "Via Milano 2", postalCode: "20100", city: "Milano",
                       province: "MI", country: "IT")
    }
    private func input(method: PaymentMethod = .card) throws -> FatturaPAInput {
        FatturaPAInput(seller: seller(), buyer: buyer(),
                       breakdown: try ForfettarioBreakdown.from(totalCents: 6000),
                       issueDate: Date(timeIntervalSince1970: 1_700_000_000),
                       paymentMethod: method, lineDescription: "Lezione di personal training",
                       transmissionProgressive: "00001")
    }

    func testBuildsWellFormedXMLWithForfettarioFields() throws {
        let xml = try FatturaPAXMLBuilder.build(input())
        XCTAssertTrue(xml.contains("versione=\"FPR12\""))
        XCTAssertTrue(xml.contains("<RegimeFiscale>RF19</RegimeFiscale>"))
        XCTAssertTrue(xml.contains("<Natura>N2.2</Natura>"))
        XCTAssertTrue(xml.contains("<TipoCassa>TC22</TipoCassa>"))
        XCTAssertTrue(xml.contains("<AlCassa>4.00</AlCassa>"))
        XCTAssertTrue(xml.contains("<ImponibileCassa>57.69</ImponibileCassa>"))
        XCTAssertTrue(xml.contains("<ImportoContributoCassa>2.31</ImportoContributoCassa>"))
        XCTAssertTrue(xml.contains("<ImponibileImporto>57.69</ImponibileImporto>"))
        XCTAssertTrue(xml.contains("<Imposta>0.00</Imposta>"))
        XCTAssertTrue(xml.contains("<ImportoPagamento>60.00</ImportoPagamento>"))
        // La dicitura contiene un apostrofo, che nell'XML è escaped in &apos;.
        XCTAssertTrue(xml.contains(FatturaPAXMLBuilder.escape(ForfettarioTax.riferimentoNormativo)))
        XCTAssertTrue(xml.contains("Legge n. 190/2014"))
        XCTAssertTrue(xml.contains("<CodiceDestinatario>0000000</CodiceDestinatario>"))
        // Parseabile come XML valido.
        XCTAssertNoThrow(try XMLDocument(data: Data(xml.utf8)))
    }

    func testPaymentMethodMapping() throws {
        XCTAssertTrue(try FatturaPAXMLBuilder.build(input(method: .card)).contains("<ModalitaPagamento>MP08</ModalitaPagamento>"))
        XCTAssertTrue(try FatturaPAXMLBuilder.build(input(method: .stripe)).contains("<ModalitaPagamento>MP08</ModalitaPagamento>"))
        XCTAssertTrue(try FatturaPAXMLBuilder.build(input(method: .bankTransfer)).contains("<ModalitaPagamento>MP05</ModalitaPagamento>"))
    }

    func testXMLEscapingOfSpecialCharacters() throws {
        var party = buyer()
        party.name = "Studio <A&B> \"Fitness\""
        let inp = FatturaPAInput(seller: seller(), buyer: party,
                                 breakdown: try ForfettarioBreakdown.from(totalCents: 6000),
                                 issueDate: Date(), paymentMethod: .card,
                                 lineDescription: "Lezione", transmissionProgressive: "00001")
        let xml = try FatturaPAXMLBuilder.build(inp)
        XCTAssertTrue(xml.contains("Studio &lt;A&amp;B&gt; &quot;Fitness&quot;"))
        XCTAssertFalse(xml.contains("<A&B>"))
        XCTAssertNoThrow(try XMLDocument(data: Data(xml.utf8)))
    }

    func testRejectsSellerWithoutVat() throws {
        var s = seller()
        s.vatNumber = nil
        let inp = FatturaPAInput(seller: s, buyer: buyer(),
                                 breakdown: try ForfettarioBreakdown.from(totalCents: 6000),
                                 issueDate: Date(), paymentMethod: .card,
                                 lineDescription: "Lezione", transmissionProgressive: "1")
        XCTAssertThrowsError(try FatturaPAXMLBuilder.build(inp))
    }

    func testRejectsBuyerWithoutAddressOrTaxCode() throws {
        var noAddress = buyer(); noAddress.address = ""
        XCTAssertThrowsError(try FatturaPAXMLBuilder.build(FatturaPAInput(
            seller: seller(), buyer: noAddress, breakdown: try ForfettarioBreakdown.from(totalCents: 6000),
            issueDate: Date(), paymentMethod: .card, lineDescription: "L", transmissionProgressive: "1")))

        var noTaxCode = buyer(); noTaxCode.taxCode = ""
        XCTAssertThrowsError(try FatturaPAXMLBuilder.build(FatturaPAInput(
            seller: seller(), buyer: noTaxCode, breakdown: try ForfettarioBreakdown.from(totalCents: 6000),
            issueDate: Date(), paymentMethod: .card, lineDescription: "L", transmissionProgressive: "1")))
    }

    func testAmountFormatting() {
        XCTAssertEqual(FatturaPAXMLBuilder.amount(6000), "60.00")
        XCTAssertEqual(FatturaPAXMLBuilder.amount(5769), "57.69")
        XCTAssertEqual(FatturaPAXMLBuilder.amount(5), "0.05")
        XCTAssertEqual(FatturaPAXMLBuilder.amount(0), "0.00")
    }
}
