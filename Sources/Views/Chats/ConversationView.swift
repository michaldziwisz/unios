import SwiftUI
import AVFoundation
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
    @State private var showCameraCapture = false
    @State private var isPreparingAttachment = false
    @State private var attachmentAlertMessage: String?
    @State private var attachmentPreviewItem: AttachmentPreviewItem?
    @State private var loadingAttachmentMessageIDs: Set<UUID> = []
    @StateObject private var voiceNoteRecorder = VoiceNoteRecorder()
    @StateObject private var audioPlayer = ConversationAudioPlayer()
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
        .sheet(isPresented: $showCameraCapture) {
            #if canImport(UIKit)
            MediaCapturePicker(
                onCapture: { capturedMedia in
                    Task {
                        await prepareAndSendCapturedMedia(capturedMedia)
                    }
                },
                onCancel: {},
                onError: { message in
                    presentAttachmentError(message)
                }
            )
            .ignoresSafeArea()
            #endif
        }
        .sheet(item: $attachmentPreviewItem) { item in
            AttachmentPreviewSheet(item: item)
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
        .onDisappear {
            audioPlayer.stop()
            if voiceNoteRecorder.isRecording {
                voiceNoteRecorder.cancelRecording()
            }
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
                            compactMediaDescriptions: appModel.accessibilityPreferences.preferCompactMediaDescriptions,
                            isAttachmentLoading: loadingAttachmentMessageIDs.contains(message.id),
                            isAttachmentActive: audioPlayer.playingMessageID == message.id,
                            attachmentActionLabel: attachmentActionLabel(for: message),
                            attachmentActionHint: attachmentActionHint(for: message),
                            attachmentAction: message.attachment == nil ? nil : {
                                handleAttachmentAction(for: message)
                            }
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
                if voiceNoteRecorder.isRecording {
                    HStack {
                        Label("Recording voice note · \(voiceNoteRecorder.elapsedSeconds)s", systemImage: "waveform.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(UniOSTheme.tint)

                        Spacer()

                        Button("Cancel", role: .destructive) {
                            voiceNoteRecorder.cancelRecording()
                            VoiceOverAnnouncer.post("Voice note recording canceled.")
                        }
                        .buttonStyle(.borderless)
                    }
                }

                if isPreparingAttachment {
                    ProgressView("Preparing attachment")
                        .font(.subheadline)
                        .foregroundStyle(UniOSTheme.quietText)
                        .accessibilityHint("The selected attachment is being prepared before sending.")
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        if cameraAvailable {
                            Button {
                                showCameraCapture = true
                            } label: {
                                Label("Camera", systemImage: "camera.fill")
                                    .font(.headline)
                            }
                            .buttonStyle(.bordered)
                            .disabled(isPreparingAttachment || voiceNoteRecorder.isRecording)
                            .accessibilityHint("Captures a photo or video and sends it with the current draft as its caption.")
                        }

                        PhotosPicker(
                            selection: $selectedPhotoItem,
                            matching: .images,
                            photoLibrary: .shared()
                        ) {
                            Label("Photo", systemImage: "photo.on.rectangle.angled")
                                .font(.headline)
                        }
                        .buttonStyle(.bordered)
                        .disabled(isPreparingAttachment || voiceNoteRecorder.isRecording)
                        .accessibilityHint("Opens Photos and sends the selected image with the current draft as its caption.")

                        Button {
                            showFileImporter = true
                        } label: {
                            Label("File", systemImage: "paperclip")
                                .font(.headline)
                        }
                        .buttonStyle(.bordered)
                        .disabled(isPreparingAttachment || voiceNoteRecorder.isRecording)
                        .accessibilityHint("Imports a file and sends it with the current draft as its caption.")

                        Button {
                            Task {
                                await toggleVoiceNoteRecording()
                            }
                        } label: {
                            Label(voiceNoteRecorder.isRecording ? "Stop Voice" : "Voice Note", systemImage: voiceNoteRecorder.isRecording ? "stop.circle.fill" : "mic.fill")
                                .font(.headline)
                        }
                        .buttonStyle(.bordered)
                        .disabled(isPreparingAttachment)
                        .accessibilityHint(voiceNoteRecorder.isRecording ? "Stops the current voice note recording and sends it." : "Starts recording a voice note.")
                    }
                }

                HStack(alignment: .bottom, spacing: 12) {
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
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isPreparingAttachment || voiceNoteRecorder.isRecording)
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

    private var cameraAvailable: Bool {
        #if canImport(UIKit)
        UIImagePickerController.isSourceTypeAvailable(.camera)
        #else
        false
        #endif
    }

    private func attachmentActionLabel(for message: Message) -> String? {
        guard let attachment = message.attachment else {
            return nil
        }

        if loadingAttachmentMessageIDs.contains(message.id) {
            return nil
        }

        if attachment.kind.supportsInlinePlayback {
            return audioPlayer.playingMessageID == message.id ? "Pause" : (attachment.isAvailableLocally ? "Play" : "Download")
        }

        return attachment.isAvailableLocally ? "Open" : "Download"
    }

    private func attachmentActionHint(for message: Message) -> String? {
        guard let attachment = message.attachment else {
            return nil
        }

        if attachment.kind.supportsInlinePlayback {
            return audioPlayer.playingMessageID == message.id ? "Pauses the current playback." : "Downloads the attachment if needed and starts playback."
        }

        return attachment.isAvailableLocally ? "Opens the attachment preview." : "Downloads the attachment and opens it."
    }

    private func handleAttachmentAction(for message: Message) {
        Task {
            await openAttachment(for: message)
        }
    }

    @MainActor
    private func openAttachment(for message: Message) async {
        guard let attachment = message.attachment else {
            return
        }

        if attachment.kind.supportsInlinePlayback, audioPlayer.playingMessageID == message.id {
            audioPlayer.stop()
            return
        }

        guard !loadingAttachmentMessageIDs.contains(message.id) else {
            return
        }

        loadingAttachmentMessageIDs.insert(message.id)
        defer {
            loadingAttachmentMessageIDs.remove(message.id)
        }

        do {
            let localURL = try await appModel.loadAttachment(for: message.id, in: chatID)

            switch attachment.kind {
            case .audio, .voiceNote:
                try audioPlayer.togglePlayback(for: message.id, url: localURL)
                VoiceOverAnnouncer.post("Playback started.")

            case .photo:
                audioPlayer.stop()
                attachmentPreviewItem = .image(url: localURL, title: message.text)

            case .video, .videoNote:
                audioPlayer.stop()
                attachmentPreviewItem = .video(url: localURL, title: message.text)

            case .document:
                audioPlayer.stop()
                attachmentPreviewItem = .document(
                    url: localURL,
                    title: attachment.fileName ?? message.text
                )
            }
        } catch {
            presentAttachmentError(error.localizedDescription)
        }
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
            sendPreparedAttachment(at: copiedFileURL)
            draft = ""
            composerFocused = true
        } catch {
            presentAttachmentError(error.localizedDescription)
        }
    }

    @MainActor
    private func prepareAndSendCapturedMedia(_ capturedMedia: CapturedMedia) async {
        guard !isPreparingAttachment else {
            return
        }

        isPreparingAttachment = true
        defer {
            isPreparingAttachment = false
        }

        switch capturedMedia {
        case let .photo(url, size):
            let caption = draft
            appModel.sendPhoto(at: url, size: size, caption: caption, to: chatID)

        case let .video(url, size, duration):
            let caption = draft
            appModel.sendVideo(at: url, size: size, duration: duration, caption: caption, to: chatID)
        }

        draft = ""
        composerFocused = true
    }

    @MainActor
    private func toggleVoiceNoteRecording() async {
        if voiceNoteRecorder.isRecording {
            guard let recordedVoiceNote = voiceNoteRecorder.stopRecording() else {
                presentAttachmentError("The recorded voice note could not be prepared.")
                return
            }

            let caption = draft
            appModel.sendVoiceNote(
                at: recordedVoiceNote.url,
                duration: recordedVoiceNote.duration,
                waveform: recordedVoiceNote.waveform,
                caption: caption,
                to: chatID
            )
            draft = ""
            composerFocused = true
            VoiceOverAnnouncer.post("Voice note sent.")
            return
        }

        let hasPermission = await voiceNoteRecorder.requestPermission()
        guard hasPermission else {
            presentAttachmentError("Microphone access is required to record a voice note.")
            return
        }

        do {
            try voiceNoteRecorder.startRecording()
            VoiceOverAnnouncer.post("Voice note recording started.")
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

    private func sendPreparedAttachment(at localURL: URL) {
        let caption = draft

        if isImageFile(localURL) {
            appModel.sendPhoto(
                at: localURL,
                size: imageSize(for: localURL),
                caption: caption,
                to: chatID
            )
            return
        }

        if isVideoFile(localURL) {
            let metadata = videoMetadata(for: localURL)
            appModel.sendVideo(
                at: localURL,
                size: metadata.size,
                duration: metadata.duration,
                caption: caption,
                to: chatID
            )
            return
        }

        if isAudioFile(localURL) {
            appModel.sendAudio(
                at: localURL,
                caption: caption,
                duration: audioDuration(for: localURL),
                title: localURL.deletingPathExtension().lastPathComponent,
                performer: "",
                to: chatID
            )
            return
        }

        appModel.sendDocument(at: localURL, caption: caption, to: chatID)
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
        conforms(url, to: .image)
    }

    private func isVideoFile(_ url: URL) -> Bool {
        conforms(url, to: .movie) || conforms(url, to: .video)
    }

    private func isAudioFile(_ url: URL) -> Bool {
        conforms(url, to: .audio)
    }

    private func conforms(_ url: URL, to type: UTType) -> Bool {
        if
            let resourceValues = try? url.resourceValues(forKeys: [.contentTypeKey]),
            let contentType = resourceValues.contentType
        {
            return contentType.conforms(to: type)
        }

        if let fallbackType = UTType(filenameExtension: url.pathExtension) {
            return fallbackType.conforms(to: type)
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

    private func videoMetadata(for url: URL) -> (size: CGSize?, duration: Int) {
        let asset = AVURLAsset(url: url)
        let duration = max(Int(asset.duration.seconds.rounded()), 0)

        guard let track = asset.tracks(withMediaType: .video).first else {
            return (nil, duration)
        }

        let transformedSize = track.naturalSize.applying(track.preferredTransform)
        let size = CGSize(width: abs(transformedSize.width), height: abs(transformedSize.height))
        return (size, duration)
    }

    private func audioDuration(for url: URL) -> Int {
        let asset = AVURLAsset(url: url)
        return max(Int(asset.duration.seconds.rounded()), 0)
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
