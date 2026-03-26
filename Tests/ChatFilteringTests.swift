import XCTest
@testable import UniOS

final class ChatFilteringTests: XCTestCase {
    func testUnreadFolderReturnsOnlyUnreadChats() {
        let result = ChatFiltering.apply(chats: UniOSSeedData.preview.chats, folder: .unread, searchQuery: "")

        XCTAssertFalse(result.isEmpty)
        XCTAssertTrue(result.allSatisfy { $0.unreadCount > 0 })
        XCTAssertEqual(result.map(\.title), ["Aurora Studio", "Kasia Nowak"])
    }

    func testSearchCanMatchMessageText() {
        let result = ChatFiltering.apply(chats: UniOSSeedData.preview.chats, folder: .all, searchQuery: "voiceover")

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.title, "Aurora Studio")
    }
}

