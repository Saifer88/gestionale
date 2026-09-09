import CryptoKit
import Foundation
import PaolaCore
import XCTest

final class BackupCipherTests: XCTestCase {
    private let password = "Una password sicura 🔐"

    func testRoundTripPreservesUnicodeAndBinaryPayloads() throws {
        let payload = Data("Paola, José e 美玲 🏋🏽‍♀️\n\u{0000}".utf8) + Data([0, 127, 128, 255])
        let archive = try BackupCipher.encrypt(payload, password: password)

        XCTAssertEqual(try BackupCipher.decrypt(archive, password: password), payload)
        let fields = try object(in: archive)
        XCTAssertEqual(fields["version"] as? Int, 1)
        XCTAssertNotNil(fields["createdAt"])
        XCTAssertEqual(try fieldData("saltData", in: fields).count, 32)
        XCTAssertEqual(try fieldData("combinedData", in: fields).count, payload.count + 28)
        XCTAssertNil(fields["password"])
        XCTAssertNil(fields["rounds"])
        XCTAssertFalse(String(decoding: archive, as: UTF8.self).contains("José"))
    }

    func testEmptyPayloadIsAuthenticated() throws {
        let archive = try BackupCipher.encrypt(Data(), password: password)
        XCTAssertEqual(try BackupCipher.decrypt(archive, password: password), Data())
    }

    func testVersionOneUsesTheExpectedPBKDF2SHA256Key() throws {
        // Independently calculated with Python hashlib.pbkdf2_hmac, 600000 rounds, 32 bytes.
        let referenceKey = SymmetricKey(data: Data([
            0x9c, 0x83, 0x7f, 0xb4, 0xd3, 0x04, 0xce, 0x32,
            0xa7, 0xd8, 0xd2, 0xe5, 0x86, 0x28, 0xd1, 0xac,
            0x75, 0xae, 0x82, 0xdb, 0xdb, 0xc8, 0xda, 0xe5,
            0x16, 0x98, 0x0f, 0x7e, 0x32, 0x6d, 0x3e, 0xd2
        ]))
        var fields: [String: Any] = [
            "version": 1,
            "createdAt": 1_700_000_000,
            "saltData": Data(0..<32).base64EncodedString()
        ]
        var authenticatedData = Data("PaolaGestionale.BackupCipher.v1\u{0000}".utf8)
        authenticatedData.append(try JSONSerialization.data(withJSONObject: fields, options: .sortedKeys))
        let payload = Data("Fixture interoperabile".utf8)
        let sealedBox = try AES.GCM.seal(
            payload,
            using: referenceKey,
            nonce: AES.GCM.Nonce(data: Data(0..<12)),
            authenticating: authenticatedData
        )
        fields["combinedData"] = try XCTUnwrap(sealedBox.combined).base64EncodedString()
        let archive = try JSONSerialization.data(withJSONObject: fields)

        XCTAssertEqual(
            try BackupCipher.decrypt(archive, password: "Una password di prova"),
            payload
        )
    }

    func testRepeatedEncryptionUsesDifferentSaltsAndNonces() throws {
        let payload = Data("Lo stesso contenuto".utf8)
        let first = try BackupCipher.encrypt(payload, password: password)
        let second = try BackupCipher.encrypt(payload, password: password)
        let firstFields = try object(in: first)
        let secondFields = try object(in: second)

        XCTAssertNotEqual(first, second)
        XCTAssertNotEqual(
            try fieldData("saltData", in: firstFields),
            try fieldData("saltData", in: secondFields)
        )
        XCTAssertNotEqual(
            try fieldData("combinedData", in: firstFields).prefix(12),
            try fieldData("combinedData", in: secondFields).prefix(12)
        )
        XCTAssertEqual(try BackupCipher.decrypt(first, password: password), payload)
        XCTAssertEqual(try BackupCipher.decrypt(second, password: password), payload)
    }

    func testWrongPasswordAndTamperedEncryptedFieldsHaveTheSameError() throws {
        let archive = try BackupCipher.encrypt(Data("Riservato".utf8), password: password)
        assertFailure(.authenticationFailed) {
            try BackupCipher.decrypt(archive, password: "Una password diversa 🔐")
        }
        assertFailure(.authenticationFailed) {
            try BackupCipher.decrypt(archive, password: "corta")
        }
        let fields = try object(in: archive)

        for field in ["saltData", "combinedData"] {
            let bytes = try fieldData(field, in: fields)
            let indexes = field == "combinedData" ? [0, 12, bytes.count - 1] : [0]
            for index in indexes {
                var changedBytes = bytes
                changedBytes[index] ^= 1
                var changedFields = fields
                changedFields[field] = changedBytes.base64EncodedString()
                let tampered = try JSONSerialization.data(withJSONObject: changedFields)
                assertFailure(.authenticationFailed) {
                    try BackupCipher.decrypt(tampered, password: password)
                }
            }
        }
    }

    func testCreationDateIsAuthenticated() throws {
        let archive = try BackupCipher.encrypt(Data("Riservato".utf8), password: password)
        var fields = try object(in: archive)
        let createdAt = try XCTUnwrap(fields["createdAt"] as? Double)
        fields["createdAt"] = createdAt + 1
        let changedDate = try JSONSerialization.data(withJSONObject: fields)
        assertFailure(.authenticationFailed) {
            try BackupCipher.decrypt(changedDate, password: password)
        }
        fields.removeValue(forKey: "createdAt")
        let removedDate = try JSONSerialization.data(withJSONObject: fields)
        assertFailure(.authenticationFailed) {
            try BackupCipher.decrypt(removedDate, password: password)
        }
    }

    func testVersionIsRejectedBeforeDecodingEncryptedFields() {
        for version in [0, 2, -1, Int.max] {
            let archive = Data("{\"version\":\(version),\"saltData\":false,\"combinedData\":null}".utf8)
            assertFailure(.unsupportedVersion(version)) {
                try BackupCipher.decrypt(archive, password: password)
            }
        }
    }

    func testEncryptionRequiresTwelveCharactersWithoutTrimming() throws {
        assertFailure(.emptyPassword) {
            try BackupCipher.encrypt(Data(), password: "")
        }
        for short in ["12345678901", String(repeating: "🔐", count: 11)] {
            assertFailure(.passwordTooShort) {
                try BackupCipher.encrypt(Data(), password: short)
            }
        }
        let exactPassword = " 1234567890 "
        let archive = try BackupCipher.encrypt(Data(), password: exactPassword)
        XCTAssertEqual(try BackupCipher.decrypt(archive, password: exactPassword), Data())
        assertFailure(.authenticationFailed) {
            try BackupCipher.decrypt(archive, password: "1234567890")
        }
        assertFailure(.emptyPassword) {
            try BackupCipher.decrypt(archive, password: "")
        }
    }

    func testPasswordLengthIsBoundedByUTF8Bytes() throws {
        for tooLong in [
            String(repeating: "a", count: BackupCipher.maximumPasswordBytes + 1),
            String(repeating: "🔐", count: BackupCipher.maximumPasswordBytes / 4 + 1)
        ] {
            assertFailure(.passwordTooLong) {
                try BackupCipher.encrypt(Data(), password: tooLong)
            }
            assertFailure(.passwordTooLong) {
                try BackupCipher.decrypt(Data("{}".utf8), password: tooLong)
            }
        }
        let longestPassword = String(repeating: "a", count: BackupCipher.maximumPasswordBytes)
        let archive = try BackupCipher.encrypt(Data(), password: longestPassword)
        XCTAssertEqual(try BackupCipher.decrypt(archive, password: longestPassword), Data())
    }

    func testEmbeddedNullInPasswordIsNotATerminator() throws {
        let exactPassword = "Dodici caratteri\u{0000}e altro 🔐"
        let archive = try BackupCipher.encrypt(Data(), password: exactPassword)
        XCTAssertEqual(try BackupCipher.decrypt(archive, password: exactPassword), Data())
        assertFailure(.authenticationFailed) {
            try BackupCipher.decrypt(archive, password: "Dodici caratteri")
        }
    }

    func testOversizedPayloadIsRejectedBeforeEncryption() {
        let payload = Data(count: BackupCipher.maximumPayloadSize + 1)
        assertFailure(.payloadTooLarge) {
            try BackupCipher.encrypt(payload, password: password)
        }
    }

    func testOversizedArchiveIsRejectedBeforeDecoding() {
        let archive = Data(count: BackupCipher.maximumArchiveSize + 1)
        assertFailure(.archiveTooLarge) {
            try BackupCipher.decrypt(archive, password: password)
        }
    }

    func testDecodedCiphertextHasAnIndependentSizeLimit() throws {
        let fields: [String: Any] = [
            "version": 1,
            "saltData": Data(count: 32).base64EncodedString(),
            "combinedData": Data(count: BackupCipher.maximumPayloadSize + 29).base64EncodedString()
        ]
        let archive = try JSONSerialization.data(withJSONObject: fields)
        XCTAssertLessThan(archive.count, BackupCipher.maximumArchiveSize)
        assertFailure(.archiveTooLarge) {
            try BackupCipher.decrypt(archive, password: password)
        }
    }

    func testMalformedFilesAreRejected() throws {
        for text in ["", "not JSON", "[]", "{}", "{\"version\":1}", "{\"version\":\"1\"}"] {
            assertFailure(.invalidArchive) {
                try BackupCipher.decrypt(Data(text.utf8), password: password)
            }
        }
        let validFields: [String: Any] = [
            "version": 1,
            "saltData": Data(count: 32).base64EncodedString(),
            "combinedData": Data(count: 28).base64EncodedString()
        ]
        for (field, value) in [
            ("saltData", Data(count: 31).base64EncodedString()),
            ("saltData", Data(count: 33).base64EncodedString()),
            ("saltData", ""),
            ("saltData", "*invalid base64*"),
            ("combinedData", Data(count: 27).base64EncodedString()),
            ("combinedData", ""),
            ("combinedData", "*invalid base64*")
        ] {
            var changedFields = validFields
            changedFields[field] = value
            let archive = try JSONSerialization.data(withJSONObject: changedFields)
            assertFailure(.invalidArchive) {
                try BackupCipher.decrypt(archive, password: password)
            }
        }
    }

    func testErrorsHaveItalianDescriptions() {
        let errors: [BackupCipherError] = [
            .emptyPassword, .passwordTooShort, .passwordTooLong, .payloadTooLarge,
            .archiveTooLarge, .invalidArchive, .unsupportedVersion(2), .authenticationFailed,
            .randomGenerationFailed(-1), .keyDerivationFailed, .encryptionFailed
        ]
        for error in errors {
            XCTAssertNotNil(error.errorDescription)
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
    }

    private func object(in archive: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: archive) as? [String: Any])
    }

    private func fieldData(_ name: String, in object: [String: Any]) throws -> Data {
        let encoded = try XCTUnwrap(object[name] as? String)
        return try XCTUnwrap(Data(base64Encoded: encoded))
    }

    private func assertFailure(
        _ expected: BackupCipherError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () throws -> Data
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) {
            XCTAssertEqual($0 as? BackupCipherError, expected, file: file, line: line)
        }
    }
}
