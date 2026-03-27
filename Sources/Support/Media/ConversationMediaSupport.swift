import SwiftUI
import AVFoundation
import QuickLook
#if canImport(UIKit)
import UIKit
#endif

enum CapturedMedia {
    case photo(url: URL, size: CGSize)
    case video(url: URL, size: CGSize?, duration: Int)
}

struct RecordedVoiceNote {
    let url: URL
    let duration: Int
    let waveform: Data
}

@MainActor
final class VoiceNoteRecorder: NSObject, ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var elapsedSeconds = 0

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var startedAt: Date?
    private var waveformSamples: [UInt8] = []

    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    func startRecording() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true)

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("VoiceNotes", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let url = directory.appendingPathComponent("voice-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.isMeteringEnabled = true
        recorder.prepareToRecord()

        self.recorder = recorder
        waveformSamples = []
        elapsedSeconds = 0
        startedAt = Date()
        isRecording = recorder.record()

        guard isRecording else {
            throw NSError(
                domain: "UniOS.VoiceNoteRecorder",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Voice note recording could not be started."]
            )
        }

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            guard let self, let recorder = self.recorder else {
                return
            }

            recorder.updateMeters()
            let currentPower = recorder.averagePower(forChannel: 0)
            self.waveformSamples.append(Self.sampleLevel(for: currentPower))

            if let startedAt = self.startedAt {
                self.elapsedSeconds = max(Int(Date().timeIntervalSince(startedAt).rounded(.down)), 0)
            }
        }
    }

    func stopRecording() -> RecordedVoiceNote? {
        guard let recorder else {
            return nil
        }

        recorder.stop()
        timer?.invalidate()
        timer = nil

        let duration = max(Int(recorder.currentTime.rounded()), 1)
        let url = recorder.url
        let waveform = Self.packWaveform(samples: Array(waveformSamples.prefix(96)))

        self.recorder = nil
        startedAt = nil
        isRecording = false
        elapsedSeconds = 0

        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])

        return RecordedVoiceNote(
            url: url,
            duration: duration,
            waveform: waveform
        )
    }

    func cancelRecording() {
        guard let recorder else {
            return
        }

        let url = recorder.url
        recorder.stop()
        timer?.invalidate()
        timer = nil
        self.recorder = nil
        startedAt = nil
        isRecording = false
        elapsedSeconds = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        try? FileManager.default.removeItem(at: url)
    }

    private static func sampleLevel(for averagePower: Float) -> UInt8 {
        let linearPower = powf(10, averagePower / 20)
        let scaled = Int((linearPower * 31).rounded())
        return UInt8(max(0, min(31, scaled)))
    }

    private static func packWaveform(samples: [UInt8]) -> Data {
        let normalizedSamples = samples.isEmpty ? [UInt8](repeating: 0, count: 24) : samples.map { min($0, 31) }
        var data = Data(count: (normalizedSamples.count * 5 + 7) / 8)

        for (index, sample) in normalizedSamples.enumerated() {
            let bitOffset = index * 5
            let byteOffset = bitOffset / 8
            let shift = bitOffset % 8

            let value = UInt16(sample) << shift
            data[byteOffset] |= UInt8(value & 0xFF)

            if byteOffset + 1 < data.count {
                data[byteOffset + 1] |= UInt8((value >> 8) & 0xFF)
            }
        }

        return data
    }
}

@MainActor
final class ConversationAudioPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var playingMessageID: UUID?

    private var player: AVAudioPlayer?

    func togglePlayback(for messageID: UUID, url: URL) throws {
        if playingMessageID == messageID, player?.isPlaying == true {
            stop()
            return
        }

        stop()

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio)
        try session.setActive(true)

        let player = try AVAudioPlayer(contentsOf: url)
        player.delegate = self
        player.prepareToPlay()
        guard player.play() else {
            throw NSError(
                domain: "UniOS.ConversationAudioPlayer",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Audio playback could not be started."]
            )
        }

        self.player = player
        playingMessageID = messageID
    }

    func stop() {
        player?.stop()
        player = nil
        playingMessageID = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        stop()
    }
}

#if canImport(UIKit)
struct MediaCapturePicker: UIViewControllerRepresentable {
    let onCapture: (CapturedMedia) -> Void
    let onCancel: () -> Void
    let onError: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .camera
        picker.mediaTypes = ["public.image", "public.movie"]
        picker.videoQuality = .typeHigh
        picker.cameraCaptureMode = .photo
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let parent: MediaCapturePicker

        init(parent: MediaCapturePicker) {
            self.parent = parent
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
            parent.onCancel()
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            defer {
                picker.dismiss(animated: true)
            }

            if let image = info[.originalImage] as? UIImage {
                do {
                    let url = try Self.writeJPEGImage(image)
                    parent.onCapture(.photo(url: url, size: image.size))
                } catch {
                    parent.onError(error.localizedDescription)
                }
                return
            }

            if let mediaURL = info[.mediaURL] as? URL {
                do {
                    let copiedURL = try Self.copyCapturedVideo(mediaURL)
                    let metadata = Self.videoMetadata(for: copiedURL)
                    parent.onCapture(.video(url: copiedURL, size: metadata.size, duration: metadata.duration))
                } catch {
                    parent.onError(error.localizedDescription)
                }
                return
            }

            parent.onError("The captured media could not be loaded.")
        }

        private static func writeJPEGImage(_ image: UIImage) throws -> URL {
            guard let data = image.jpegData(compressionQuality: 0.92) else {
                throw NSError(
                    domain: "UniOS.MediaCapturePicker",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "The captured image could not be encoded."]
                )
            }

            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CapturedMedia", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("capture-\(UUID().uuidString).jpg")
            try data.write(to: url, options: .atomic)
            return url
        }

        private static func copyCapturedVideo(_ sourceURL: URL) throws -> URL {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CapturedMedia", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let destinationURL = directory.appendingPathComponent("capture-\(UUID().uuidString).mov")
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            return destinationURL
        }

        private static func videoMetadata(for url: URL) -> (size: CGSize?, duration: Int) {
            let asset = AVURLAsset(url: url)
            let duration = max(Int(asset.duration.seconds.rounded()), 0)

            guard
                let track = asset.tracks(withMediaType: .video).first
            else {
                return (nil, duration)
            }

            let transformedSize = track.naturalSize.applying(track.preferredTransform)
            let resolvedSize = CGSize(width: abs(transformedSize.width), height: abs(transformedSize.height))
            return (resolvedSize, duration)
        }
    }
}

struct QuickLookPreviewController: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {}

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        private let url: URL

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            1
        }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}
#endif
