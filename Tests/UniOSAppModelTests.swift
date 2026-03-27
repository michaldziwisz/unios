import CoreGraphics
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
    func testSendingPhotoAppendsOutgoingPhotoMessageInDemoMode() throws {
        let model = UniOSAppModel(seed: .preview)
        let targetChatID = try XCTUnwrap(model.chats.first?.id)
        let photoURL = try temporaryFileURL(named: "test-photo.jpg", contents: Data([0xFF, 0xD8, 0xFF]))

        model.sendPhoto(at: photoURL, size: CGSize(width: 640, height: 480), caption: "Updated mockup", to: targetChatID)

        let updatedChat = try XCTUnwrap(model.chat(for: targetChatID))
        XCTAssertEqual(updatedChat.messages.last?.text, "Updated mockup")

        guard let lastKind = updatedChat.messages.last?.kind else {
            XCTFail("Expected a message kind.")
            return
        }

        XCTAssertEqual(lastKind, .photo(description: "Updated mockup"))
    }

    @MainActor
    func testMarkChatReadClearsUnreadCount() throws {
        let model = UniOSAppModel(seed: .preview)
        let unreadChatID = try XCTUnwrap(model.chats.first(where: { $0.unreadCount > 0 })?.id)

        model.markChatRead(unreadChatID)

        XCTAssertEqual(model.chat(for: unreadChatID)?.unreadCount, 0)
    }

    private func temporaryFileURL(named fileName: String, contents: Data) throws -> URL {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-\(fileName)")
        try contents.write(to: fileURL, options: .atomic)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: fileURL)
        }
        return fileURL
    }
}
