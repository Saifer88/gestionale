import CryptoKit
import Foundation

public enum CloudNamespace {
    public static func directoryName(containerIdentifier: String, accountRecordName: String) throws -> String {
        guard containerIdentifier.hasPrefix("iCloud."), !accountRecordName.isEmpty else {
            throw CocoaError(.fileReadInvalidFileName)
        }
        let identity = try JSONEncoder().encode([containerIdentifier, accountRecordName])
        return SHA256.hash(data: identity).map { String(format: "%02x", $0) }.joined()
    }
}
