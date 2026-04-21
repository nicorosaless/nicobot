import XCTest
@testable import Omi_Computer

final class ChatProviderRequestTests: XCTestCase {
    func testChatStreamRequestEncodesSessionIdWhenPresent() throws {
        let data = try ChatStreamRequest(text: "hola", sessionId: "session-123").encodedData()
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["text"] as? String, "hola")
        XCTAssertEqual(json["session_id"] as? String, "session-123")
    }

    func testChatStreamRequestOmitsSessionIdWhenNil() throws {
        let data = try ChatStreamRequest(text: "hola", sessionId: nil).encodedData()
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["text"] as? String, "hola")
        XCTAssertNil(json["session_id"])
    }
}
