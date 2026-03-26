import XCTest
@testable import UniOS

final class UniOSAppModelTests: XCTestCase {
    @MainActor
    func testSendingMessageAppendsOutgoingMessage() throws {
        let model = UniOSAppModel(seed: .preview)
        let targetChatID = try XCTUnwrap(model.chats.first?.id)
        let initialMessageCount = model.chat(for: targetChatID)?.messages.count ?? 0

        model.sendMessage("Shipping the IPA build after lunch.", to: targetChatID)

        let updatedChat = model.chat(for: targetChatID)
        XCTAssertEqual(updatedChat?.messages.count, initialMessageCount + 1)
        XCTAssertEqual(updatedChat?.messages.last?.text, "Shipping the IPA build after lunch.")
        XCTAssertEqual(updatedChat?.messages.last?.direction, .outgoing)
        XCTAssertEqual(updatedChat?.summary, "Shipping the IPA build after lunch.")
    }

    @MainActor
    func testMarkChatReadClearsUnreadCount() throws {
        let model = UniOSAppModel(seed: .preview)
        let unreadChatID = try XCTUnwrap(model.chats.first(where: { $0.unreadCount > 0 })?.id)

        model.markChatRead(unreadChatID)

        XCTAssertEqual(model.chat(for: unreadChatID)?.unreadCount, 0)
    }
}
