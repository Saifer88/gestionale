import PaolaCore
import XCTest

final class CredentialsTests: XCTestCase {

    func testSellerProfileValidationDetectsMissingAndMalformedFields() {
        var p = SellerFiscalProfile()
        XCTAssertFalse(p.isComplete)
        XCTAssertFalse(p.validationIssues.isEmpty)

        p = SellerFiscalProfile(vatNumber: "12345678901", taxCode: "RSSMRA80A01H501U",
                                name: "Mario Rossi", addressStreet: "Via Roma 1",
                                addressPostalCode: "00100", addressCity: "Roma", addressProvince: "RM")
        XCTAssertTrue(p.isComplete, "\(p.validationIssues)")

        XCTAssertFalse(SellerFiscalProfile(vatNumber: "123", taxCode: "X", name: "N",
            addressStreet: "V", addressPostalCode: "0010", addressCity: "R", addressProvince: "ROMA").isComplete)
    }

    func testSellerProfileNormalizationTrimsAndUppercases() {
        let p = SellerFiscalProfile(vatNumber: "  12345678901 ", taxCode: " rssmra80a01h501u ",
                                    name: "  Mario   Rossi ", addressStreet: " Via Roma 1 ",
                                    addressPostalCode: " 00100 ", addressCity: " Roma ", addressProvince: " rm ")
        let n = p.normalized()
        XCTAssertEqual(n.vatNumber, "12345678901")
        XCTAssertEqual(n.taxCode, "RSSMRA80A01H501U")
        XCTAssertEqual(n.name, "Mario Rossi")
        XCTAssertEqual(n.addressProvince, "RM")
    }

    func testSellerProfileStoreRoundTrip() {
        let defaults = UserDefaults(suiteName: "test.seller.\(UUID().uuidString)")!
        let store = SellerProfileStore(defaults: defaults)
        XCTAssertEqual(store.load(), SellerFiscalProfile()) // vuoto di default
        let p = SellerFiscalProfile(vatNumber: "12345678901", taxCode: "RSSMRA80A01H501U",
                                    name: "Mario Rossi", addressStreet: "Via Roma 1",
                                    addressPostalCode: "00100", addressCity: "Roma", addressProvince: "RM")
        store.save(p)
        XCTAssertEqual(store.load(), p.normalized())
    }

    func testArubaCredentialsStoreUsesSecretStoreAndClears() throws {
        let secrets = InMemorySecretStore()
        let store = ArubaCredentialsStore(secrets: secrets)
        XCTAssertFalse(store.load().isComplete)

        try store.save(ArubaCredentials(username: " 123456@aruba.it ", password: "segreta"))
        let loaded = store.load()
        XCTAssertEqual(loaded.username, "123456@aruba.it")
        XCTAssertEqual(loaded.password, "segreta")
        XCTAssertTrue(loaded.isComplete)

        try store.clear()
        XCTAssertFalse(store.load().isComplete)
        XCTAssertNil(secrets.string(for: SecretKey.arubaUsername))
    }
}
