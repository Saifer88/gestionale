@testable import PaolaCore
import SwiftData
import XCTest

@MainActor
final class InvoiceArchiveTests: XCTestCase {

    /// Crea un cliente, un pacchetto pagato con carta e la relativa fattura.
    private func makeStoreWithInvoice() throws -> (ModelContainer, Client, UUID) {
        let store = try BusinessTestStore.make()
        let context = store.mainContext
        let client = try BusinessTestStore.addClient(context)
        let repo = BusinessRepository(context: context)
        var package = PackageDraft()
        package.clientID = client.id; package.priceCents = 40000
        package.purchasedOn = BusinessTestStore.date; package.paymentMethod = .card
        let packageID = try repo.savePackage(package)
        let invoiceID = try repo.createInvoiceForPackage(packageID: packageID, issueDate: BusinessTestStore.date)
        return (store, client, invoiceID)
    }

    func testInvoiceSurvivesBackupJSONRoundTrip() throws {
        let (store, client, invoiceID) = try makeStoreWithInvoice()
        let context = store.mainContext

        let snapshot = try ArchiveSnapshot.capture(context: context)
        XCTAssertEqual(snapshot.business.invoices.count, 1)

        // Round-trip JSON dell'intero snapshot.
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(ArchiveSnapshot.self, from: data)
        let record = try XCTUnwrap(decoded.business.invoices.first)
        XCTAssertEqual(record.id, invoiceID)
        XCTAssertEqual(record.clientID, client.id)
        XCTAssertEqual(record.totalCents, 40000)
        XCTAssertEqual(record.taxableCents + record.contributionCents, 40000)
        XCTAssertEqual(record.statusRaw, InvoiceStatus.draft.rawValue)

        // Il modello ricostruito mantiene i valori.
        let model = record.model()
        XCTAssertEqual(model.id, invoiceID)
        XCTAssertEqual(model.totalCents, 40000)
        XCTAssertEqual(model.paymentMethod, .card)
    }

    func testOldBackupWithoutInvoicesStillDecodes() throws {
        // Un backup precedente all'introduzione delle fatture non ha il campo "invoices".
        let json = """
        {"version":6,"createdAt":0,"clients":[],
         "business":{"services":[],"rates":[],"preferences":[],"sessions":[],"participants":[],
         "packages":[],"packageUses":[],"ledgerEntries":[],"blocks":[]}}
        """
        let decoded = try JSONDecoder().decode(ArchiveSnapshot.self, from: Data(json.utf8))
        XCTAssertTrue(decoded.business.invoices.isEmpty)
    }
}
