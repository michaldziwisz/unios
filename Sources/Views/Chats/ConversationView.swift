import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif

struct ConversationView: View {
    @EnvironmentObject private var appModel: UniOSAppModel

    let chatID: UUID

    @State private var draft = ""
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showFileImporter = false
    @State private var isPreparingAttachment = false
    @State private var attachmentAlertMessage: String?
    @AccessibilityFocusState private var composerFocused: Bool

    var body: some View {
        Group {
            if let chat = appModel.chat(for: chatID) {
                conversationBody(chat: chat)
            } else {
                ContentUnavailableView(
                    "Conversation Unavailable",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("The selected chat could not be loaded.")
                )
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.audio, .movie, .image, .content, .data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case let .success(urls):
                guard let importedFileURL = urls.first else {
                    return
                }
                Task {
                    await prepareAndSendImportedFile(importedFileURL)
                }

            case let .failure(error):
                presentAttachmentError(error.localizedDescription)
            }
        }
        .onChange(of: selectedPhotoItem?.itemIdentifier) { _, _ in
            guard let selectedPhotoItem else {
                return
            }

            Task {
                await prepareAndSendSelectedPhoto(selectedPhotoItem)
            }
        }
        .alert("Attachment Error", isPresented: attachmentAlertBinding) {
            Button("OK", role: .cancel) {
                attachmentAlertMessage = nil
            }
        } message: {
            Text(attachmentAlertMessage ?? "The selected attachment could not be prepared.")
        }
    }

    private func conversationBody(chat: Chat) -> some View {
        let messages = chat.messages.sorted { $0.timestamp < $1.timestamp }

        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    headerCard(chat: chat)

                    ForEach(messages) { message in
                        MessageBubbleView(
                            message: message,
                            speakContext: appModel.accessibilityPreferences.speakMessageContext,
                            compactMediaDescriptions: appModel.accessibilityPreferences.preferCompactMediaDescriptions
                        )
                        .id(message.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 120)
            }
            .background(UniOSTheme.canvas.ignoresSafeArea())
            .navigationTitle(chat.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button(chat.isMuted ? "Unmute" : "Mute", systemImage: chat.isMuted ? "bell.fill" : "bell.slash.fill") {
                        appModel.toggleMuted(chatID: chatID)
                    }

                    Button("Focus Composer", systemImage: "keyboard.fill") {
                        composerFocused = true
                    }
                    .accessibilityHint("Moves VoiceOver focus to the message composer.")
                }
            }
            .safeAreaInset(edge: .bottom) {
                composerBar(chatTitle: chat.title)
            }
            .onAppear {
                appModel.loadConversationIfNeeded(chatID: chatID)
                if let lastID = messages.last?.id {
                    DispatchQueue.main.async {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
                if appModel.accessibilityPreferences.focusComposerOnOpen {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        composerFocused = true
                    }
                }
            }
            .onChange(of: messages.count) { _, _ in
                if let lastID = messages.last?.id {
                    DispatchQueue.main.async {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func headerCard(chat: Chat) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(chat.handle)
                .font(.headline)
                .foregroundStyle(UniOSTheme.tint)

            Text(chat.participantDescription)
                .font(.subheadline)
                .foregroundStyle(UniOSTheme.quietText)

            if !chat.accessibilityStatus.isEmpty {
                Label(chat.accessibilityStatus, systemImage: "eye.fill")
                    .font(.subheadline)
                    .foregroundStyle(UniOSTheme.quietText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .uniosCard()
        .accessibilityElement(children: .combine)
    }

    private func composerBar(chatTitle: String) -> some View {
        VStack(spacing: 0) {
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                if isPreparingAttachment {
                    ProgressView("Preparing attachment")
                        .font(.subheadline)
                        .foregroundStyle(UniOSTheme.quietText)
                        .accessibilityHint("The selected attachment is being prepared before sending.")
                }

                HStack(alignment: .bottom, spacing: 12) {
                    PhotosPicker(
                        selection: $selectedPhotoItem,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        Label("Photo", systemImage: "photo.on.rectangle.angled")
                            .font(.headline)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isPreparingAttachment)
                    .accessibilityHint("Opens Photos and sends the selected image with the current draft as its caption.")

                    Button {
                        showFileImporter = true
                    } label: {
                        Label("File", systemImage: "paperclip")
                            .font(.headline)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isPreparingAttachment)
                    .accessibilityHint("Imports a file and sends it with the current draft as its caption.")

                    TextField("Reply to \(chatTitle)", text: $draft, axis: .vertical)
                        .lineLimit(1 ... 4)
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(Color(uiColor: .systemBackground))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(UniOSTheme.tint.opacity(0.14), lineWidth: 1)
                        )
                        .accessibilityLabel("Message Input")
                        .accessibilityHint("Double tap to type a reply or a caption for the next attachment in \(chatTitle).")
                        .accessibilityFocused($composerFocused)

                    Button {
                        appModel.sendMessage(draft, to: chatID)
                        draft = ""
                        composerFocused = true
                    } label: {
                        Label("Send", systemImage: "paperplane.fill")
                            .font(.headline)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isPreparingAttachment)
                    .accessibilityHint("Sends the current text message.")
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 12)
        }
        .background(.ultraThinMaterial)
    }

    private var attachmentAlertBinding: Binding<Bool> {
        Binding(
            get: { attachmentAlertMessage != nil },
            set: { newValue in
                if !newValue {
                    attachmentAlertMessage = nil
                }
            }
        )
    }

    @MainActor
    private func prepareAndSendSelectedPhoto(_ item: PhotosPickerItem) async {
        guard !isPreparingAttachment else {
            return
        }

        isPreparingAttachment = true
        defer {
            isPreparingAttachment = false
            selectedPhotoItem = nil
        }

        do {
            let preparedPhoto = try await preparePhoto(item)
            let caption = draft
            appModel.sendPhoto(at: preparedPhoto.url, size: preparedPhoto.size, caption: caption, to: chatID)
            draft = ""
            composerFocused = true
        } catch {
            presentAttachmentError(error.localizedDescription)
        }
    }

    @MainActor
    private func prepareAndSendImportedFile(_ importedFileURL: URL) async {
        guard !isPreparingAttachment else {
            return
        }

        isPreparingAttachment = true
        defer {
            isPreparingAttachment = false
        }

        do {
            let copiedFileURL = try copyImportedFileToTemporaryDirectory(importedFileURL)
            let caption = draft

            if isImageFile(copiedFileURL) {
                appModel.sendPhoto(
                    at: copiedFileURL,
                    size: imageSize(for: copiedFileURL),
                    caption: caption,
                    to: chatID
                )
            } else {
                appModel.sendDocument(at: copiedFileURL, caption: caption, to: chatID)
            }

            draft = ""
            composerFocused = true
        } catch {
            presentAttachmentError(error.localizedDescription)
        }
    }

    private func preparePhoto(_ item: PhotosPickerItem) async throws -> (url: URL, size: CGSize?) {
        guard let data = try await item.loadTransferable(type: Data.self) else {
            throw ConversationAttachmentError.unreadablePhoto
        }

        let contentType = item.supportedContentTypes.first(where: { $0.conforms(to: .image) }) ?? .jpeg
        let fileExtension = contentType.preferredFilenameExtension ?? "jpg"
        let temporaryURL = try writeTemporaryData(data, prefix: "photo", pathExtension: fileExtension)

        #if canImport(UIKit)
        let size = UIImage(data: data)?.size
        #else
        let size: CGSize? = nil
        #endif

        return (temporaryURL, size)
    }

    private func copyImportedFileToTemporaryDirectory(_ sourceURL: URL) throws -> URL {
        let shouldStopAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if shouldStopAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let fileManager = FileManager.default
        let destinationDirectory = fileManager.temporaryDirectory.appendingPathComponent("ImportedAttachments", isDirectory: true)
        try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

        let fileName = sourceURL.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeFileName = fileName.isEmpty ? UUID().uuidString : fileName
        let destinationURL = destinationDirectory.appendingPathComponent("\(UUID().uuidString)-\(safeFileName)")

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        do {
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
        } catch {
            throw ConversationAttachmentError.importFailed
        }

        return destinationURL
    }

    private func writeTemporaryData(_ data: Data, prefix: String, pathExtension: String) throws -> URL {
        let fileManager = FileManager.default
        let destinationDirectory = fileManager.temporaryDirectory.appendingPathComponent("PreparedAttachments", isDirectory: true)
        try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

        let trimmedExtension = pathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        let fileName = trimmedExtension.isEmpty ? "\(prefix)-\(UUID().uuidString)" : "\(prefix)-\(UUID().uuidString).\(trimmedExtension)"
        let destinationURL = destinationDirectory.appendingPathComponent(fileName)
        try data.write(to: destinationURL, options: .atomic)
        return destinationURL
    }

    private func isImageFile(_ url: URL) -> Bool {
        if
            let resourceValues = try? url.resourceValues(forKeys: [.contentTypeKey]),
            let contentType = resourceValues.contentType
        {
            return contentType.conforms(to: .image)
        }

        if let fallbackType = UTType(filenameExtension: url.pathExtension) {
            return fallbackType.conforms(to: .image)
        }

        return false
    }

    private func imageSize(for url: URL) -> CGSize? {
        #if canImport(UIKit)
        UIImage(contentsOfFile: url.path)?.size
        #else
        nil
        #endif
    }

    private func presentAttachmentError(_ message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedMessage = trimmed.isEmpty ? "The selected attachment could not be prepared." : trimmed
        attachmentAlertMessage = resolvedMessage
        VoiceOverAnnouncer.post(resolvedMessage)
    }
}

private enum ConversationAttachmentError: LocalizedError {
    case unreadablePhoto
    case importFailed

    var errorDescription: String? {
        switch self {
        case .unreadablePhoto:
            return "The selected photo could not be loaded."
        case .importFailed:
            return "The selected file could not be imported."
        }
    }
}
