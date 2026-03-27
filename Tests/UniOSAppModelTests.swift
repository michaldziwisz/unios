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
    func testSendingAudioAppendsOutgoingAudioAttachmentInDemoMode() throws {
        let model = UniOSAppModel(seed: .preview)
        let targetChatID = try XCTUnwrap(model.chats.first?.id)
        let audioURL = try temporaryFileURL(named: "standup.m4a", contents: Data([0x00, 0x11, 0x22, 0x33]))

        model.sendAudio(
            at: audioURL,
            caption: "Standup summary",
            duration: 12,
            title: "Standup",
            performer: "Team",
            to: targetChatID
        )

        let updatedChat = try XCTUnwrap(model.chat(for: targetChatID))
        let message = try XCTUnwrap(updatedChat.messages.last)
        XCTAssertEqual(message.kind, .audio(description: "Standup summary", durationSeconds: 12))
        XCTAssertEqual(message.attachment?.kind, .audio)
        XCTAssertEqual(message.attachment?.localPath, audioURL.path)
        XCTAssertEqual(message.attachment?.durationSeconds, 12)
    }

    @MainActor
    func testSendingVoiceNoteAppendsOutgoingVoiceAttachmentInDemoMode() throws {
        let model = UniOSAppModel(seed: .preview)
        let targetChatID = try XCTUnwrap(model.chats.first?.id)
        let voiceURL = try temporaryFileURL(named: "voice.m4a", contents: Data([0xAA, 0xBB, 0xCC]))

        model.sendVoiceNote(
            at: voiceURL,
            duration: 8,
            waveform: Data([0x1F, 0x00, 0x10]),
            caption: "",
            to: targetChatID
        )

        let updatedChat = try XCTUnwrap(model.chat(for: targetChatID))
        let message = try XCTUnwrap(updatedChat.messages.last)
        XCTAssertEqual(message.kind, .voice(transcript: "Voice note", durationSeconds: 8))
        XCTAssertEqual(message.attachment?.kind, .voiceNote)
        XCTAssertEqual(message.attachment?.localPath, voiceURL.path)
        XCTAssertEqual(message.attachment?.durationSeconds, 8)
    }

    @MainActor
    func testLoadAttachmentReturnsExistingLocalFileInDemoMode() async throws {
        let model = UniOSAppModel(seed: .preview)
        let targetChatID = try XCTUnwrap(model.chats.first?.id)
        let documentURL = try temporaryFileURL(named: "brief.pdf", contents: Data([0x25, 0x50, 0x44, 0x46]))

        model.sendDocument(at: documentURL, caption: "Brief", to: targetChatID)

        let updatedChat = try XCTUnwrap(model.chat(for: targetChatID))
        let messageID = try XCTUnwrap(updatedChat.messages.last?.id)
        let resolvedURL = try await model.loadAttachment(for: messageID, in: targetChatID)

        XCTAssertEqual(resolvedURL.path, documentURL.path)
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
