import XCTest
@testable import UniOS

final class StableIdentifierTests: XCTestCase {
    func testChatUUIDIsDeterministic() {
        XCTAssertEqual(
            StableIdentifier.chatUUID(for: Int64(123456789)),
            StableIdentifier.chatUUID(for: Int64(123456789))
        )
    }

    func testMessageUUIDDiffersPerMessage() {
        XCTAssertNotEqual(
            StableIdentifier.messageUUID(chatID: Int64(100), messageID: Int64(1)),
            StableIdentifier.messageUUID(chatID: Int64(100), messageID: Int64(2))
        )
    }
}
