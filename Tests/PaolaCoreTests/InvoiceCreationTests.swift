import Foundation
@testable import PaolaCore
import SwiftData
import XCTest

@MainActor
final class InvoiceCreationTests: XCTestCase {

    private func sessionDraft(_ client: Client, price: Int64, method: PaymentMethod,
                              packageID: UUID? = nil) -> SessionDraft {
        var draft = SessionDraft()
        draft.startDate = BusinessTestStore.date.addingTimeInterval(86400 + 10 * 3600)
        draft.durationMinutes = 60
        draft.serviceName = "Allenamento"
        draft.participants = [ParticipantDraft(clientID: client.id, priceCents: price,
                                               packageID: packageID, paymentMethod: method)]
        return draft
    }

    private func packageDraft(_ client: Client, price: Int64, method: PaymentMethod) -> PackageDraft {
        var draft = PackageDraft()
        draft.clientID = client.id; draft.priceCents = price
        draft.purchasedOn = BusinessTestStore.date; draft.paymentMethod = method
        return draft
    }

    func testInvoiceForCompletedCardSessionCreatesDraftWithForfettarioBreakdown() throws {
        let store = try BusinessTestStore.make()
        let context = store.mainContext
        let client = try BusinessTestStore.addClient(context)
        let repo = BusinessRepository(context: context)
        let sessionID = try repo.saveSession(sessionDraft(client, price: 6000, method: .card))
        try repo.setSessionStatus(sessionID, to: .completed)

        let invoiceDate = BusinessTestStore.date.addingTimeInterval(5 * 86400)
        let id = try repo.createInvoiceForSession(sessionID: sessionID, clientID: client.id, issueDate: invoiceDate)

        let invoices = try context.fetch(FetchDescriptor<Invoice>())
        let invoice = try XCTUnwrap(invoices.first { $0.id == id })
        XCTAssertEqual(invoice.totalCents, 6000)
        XCTAssertEqual(invoice.taxableCents, 5769)
        XCTAssertEqual(invoice.contributionCents, 231)
        XCTAssertEqual(invoice.status, .draft)
        XCTAssertEqual(invoice.paymentMethod, .card)
        XCTAssertEqual(invoice.sourceKey, Invoice.sessionSourceKey(sessionID: sessionID, clientID: client.id))

        let session = try XCTUnwrap(context.fetch(FetchDescriptor<TrainingSession>()).first { $0.id == sessionID })
        XCTAssertEqual(session.invoiceDate, invoiceDate)
    }

    func testSecondInvoiceForSameSessionIsRejected() throws {
        let store = try BusinessTestStore.make()
        let context = store.mainContext
        let client = try BusinessTestStore.addClient(context)
        let repo = BusinessRepository(context: context)
        let sessionID = try repo.saveSession(sessionDraft(client, price: 6000, method: .bankTransfer))
        try repo.setSessionStatus(sessionID, to: .completed)
        _ = try repo.createInvoiceForSession(sessionID: sessionID, clientID: client.id, issueDate: BusinessTestStore.date)
        XCTAssertThrowsError(try repo.createInvoiceForSession(sessionID: sessionID, clientID: client.id, issueDate: BusinessTestStore.date)) {
            guard case BusinessError.alreadyInvoiced = $0 else { return XCTFail("Atteso alreadyInvoiced, ricevuto \($0)") }
        }
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Invoice>()), 1)
    }

    func testCashSessionCannotBeInvoiced() throws {
        let store = try BusinessTestStore.make()
        let context = store.mainContext
        let client = try BusinessTestStore.addClient(context)
        let repo = BusinessRepository(context: context)
        let sessionID = try repo.saveSession(sessionDraft(client, price: 6000, method: .cash))
        try repo.setSessionStatus(sessionID, to: .completed)
        XCTAssertThrowsError(try repo.createInvoiceForSession(sessionID: sessionID, clientID: client.id, issueDate: BusinessTestStore.date))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Invoice>()), 0)
    }

    func testPlannedSessionCanBeInvoiced() throws {
        // La fattura è consentita in qualsiasi stato dell'appuntamento, anche programmato.
        let store = try BusinessTestStore.make()
        let context = store.mainContext
        let client = try BusinessTestStore.addClient(context)
        let repo = BusinessRepository(context: context)
        let sessionID = try repo.saveSession(sessionDraft(client, price: 6000, method: .card))
        let id = try repo.createInvoiceForSession(sessionID: sessionID, clientID: client.id, issueDate: BusinessTestStore.date)
        let invoice = try XCTUnwrap(context.fetch(FetchDescriptor<Invoice>()).first { $0.id == id })
        XCTAssertEqual(invoice.totalCents, 6000)
        let session = try XCTUnwrap(context.fetch(FetchDescriptor<TrainingSession>()).first { $0.id == sessionID })
        XCTAssertEqual(session.status, .planned)
        XCTAssertEqual(session.invoiceDate, BusinessTestStore.date)
    }

    func testInvoiceForCardPackageCreatesDraft() throws {
        let store = try BusinessTestStore.make()
        let context = store.mainContext
        let client = try BusinessTestStore.addClient(context)
        let repo = BusinessRepository(context: context)
        let packageID = try repo.savePackage(packageDraft(client, price: 40000, method: .card))
        let id = try repo.createInvoiceForPackage(packageID: packageID, issueDate: BusinessTestStore.date)
        let invoice = try XCTUnwrap(context.fetch(FetchDescriptor<Invoice>()).first { $0.id == id })
        XCTAssertEqual(invoice.totalCents, 40000)
        XCTAssertEqual(invoice.taxableCents + invoice.contributionCents, 40000)
        XCTAssertEqual(invoice.sourceKey, Invoice.packageSourceKey(packageID))
        let package = try XCTUnwrap(context.fetch(FetchDescriptor<LessonPackage>()).first { $0.id == packageID })
        XCTAssertEqual(package.invoiceDate, BusinessTestStore.date)
    }

    func testCashPackageAndSecondPackageInvoiceRejected() throws {
        let store = try BusinessTestStore.make()
        let context = store.mainContext
        let client = try BusinessTestStore.addClient(context)
        let repo = BusinessRepository(context: context)
        let cashPackage = try repo.savePackage(packageDraft(client, price: 40000, method: .cash))
        XCTAssertThrowsError(try repo.createInvoiceForPackage(packageID: cashPackage, issueDate: BusinessTestStore.date))

        let cardPackage = try repo.savePackage(packageDraft(client, price: 40000, method: .card))
        _ = try repo.createInvoiceForPackage(packageID: cardPackage, issueDate: BusinessTestStore.date)
        XCTAssertThrowsError(try repo.createInvoiceForPackage(packageID: cardPackage, issueDate: BusinessTestStore.date)) {
            guard case BusinessError.alreadyInvoiced = $0 else { return XCTFail("Atteso alreadyInvoiced, ricevuto \($0)") }
        }
    }

    func testPackageWithPackageLessonSessionCannotBeInvoicedAsSession() throws {
        let store = try BusinessTestStore.make()
        let context = store.mainContext
        let client = try BusinessTestStore.addClient(context)
        let repo = BusinessRepository(context: context)
        let packageID = try repo.savePackage(packageDraft(client, price: 40000, method: .card))
        let sessionID = try repo.saveSession(sessionDraft(client, price: 0, method: .card, packageID: packageID))
        try repo.setSessionStatus(sessionID, to: .completed)
        // La lezione è coperta dal pacchetto: non fatturabile come singola lezione.
        XCTAssertThrowsError(try repo.createInvoiceForSession(sessionID: sessionID, clientID: client.id, issueDate: BusinessTestStore.date))
    }
}
