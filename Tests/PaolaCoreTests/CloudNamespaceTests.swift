import PaolaCore
import XCTest

final class CloudNamespaceTests: XCTestCase {
    func testAccountsAndContainersNeverShareTheSameStorePath() throws {
        let first = try CloudNamespace.directoryName(containerIdentifier: "iCloud.prova", accountRecordName: "account-a")
        let second = try CloudNamespace.directoryName(containerIdentifier: "iCloud.prova", accountRecordName: "account-b")
        let third = try CloudNamespace.directoryName(containerIdentifier: "iCloud.altra", accountRecordName: "account-a")
        XCTAssertNotEqual(first, second)
        XCTAssertNotEqual(first, third)
        XCTAssertEqual(first.count, 64)
        XCTAssertTrue(first.allSatisfy(\.isHexDigit))
        XCTAssertFalse(first.contains("account-a"))
        XCTAssertEqual(first, try CloudNamespace.directoryName(
            containerIdentifier: "iCloud.prova", accountRecordName: "account-a"
        ))
    }

    func testInvalidIdentityCannotFallBackToAnotherAccount() {
        XCTAssertThrowsError(try CloudNamespace.directoryName(containerIdentifier: "", accountRecordName: "a"))
        XCTAssertThrowsError(try CloudNamespace.directoryName(containerIdentifier: "iCloud.prova", accountRecordName: ""))
    }
}
