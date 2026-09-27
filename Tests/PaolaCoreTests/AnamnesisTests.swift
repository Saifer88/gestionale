import Foundation
import PaolaCore
import XCTest

final class AnamnesisTests: XCTestCase {
    func testHistoryRoundTripsAttachments() {
        let attachment = AnamnesisAttachment(fileName: "referto.pdf", contentType: "com.adobe.pdf",
                                             data: Data([0, 1, 2, 255]))
        var history = AnamnesisHistory()
        history.upsert(Anamnesis(title: "Prima visita", attachments: [attachment]))

        let restored = AnamnesisHistory.parse(history.serialized())

        XCTAssertEqual(restored, history)
        XCTAssertEqual(restored.current?.attachments.first?.data, attachment.data)
    }

    func testHistoryDecodesVersionsWithoutAttachments() {
        let id = UUID()
        let json = "[{\"id\":\"\(id.uuidString)\",\"date\":0,\"title\":\"Storica\",\"values\":{\"height\":\"170\"}}]"

        let history = AnamnesisHistory.parse(json)

        XCTAssertEqual(history.current?.id, id)
        XCTAssertEqual(history.current?.value(.height), "170")
        XCTAssertTrue(history.current?.attachments.isEmpty == true)
    }
}