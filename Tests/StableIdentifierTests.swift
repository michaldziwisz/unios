import XCTest
@testable import UniOS

final class StableIdentifierTests: XCTestCase {
    func testChatUUIDIsDeterministic() {
        XCTAssertEqual(
            StableIdentifier.chatUUID(for: 123456789),
            StableIdentifier.chatUUID(for: 123456789)
        )
    }

    func testMessageUUIDDiffersPerMessage() {
        XCTAssertNotEqual(
            StableIdentifier.messageUUID(chatID: 100, messageID: 1),
            StableIdentifier.messageUUID(chatID: 100, messageID: 2)
        )
    }
}
