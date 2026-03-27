import Foundation
import TDLibKit

#if canImport(UIKit)
import UIKit
#endif

#if canImport(AVFoundation)
import AVFoundation
#endif

#if canImport(Network)
import Network
#endif

#if canImport(TgVoipWebrtc)
import TgVoipWebrtc
#endif

enum TelegramCallMediaTransportState: Hashable {
    case unavailable(reason: String)
    case initializing
    case connected
    case reconnecting
    case failed(message: String)
    case stopped

    var summary: String {
        switch self {
        case let .unavailable(reason):
            return reason
        case .initializing:
            return "Telegram media engine is preparing the call transport."
        case .connected:
            return "Telegram media engine is carrying the call media."
        case .reconnecting:
            return "Telegram media engine is reconnecting."
        case let .failed(message):
            return message
        case .stopped:
            return "Telegram media engine stopped."
        }
    }

    var isReady: Bool {
        if case .connected = self {
            return true
        }
        return false
    }
}

enum TelegramCallRemoteVideoState: Hashable {
    case inactive
    case active
    case paused

    var summary: String {
        switch self {
        case .inactive:
            return "Remote video inactive"
        case .active:
            return "Remote video active"
        case .paused:
            return "Remote video paused"
        }
    }
}

struct TelegramCallMediaStatus: Hashable {
    var transportState: TelegramCallMediaTransportState
    var isMuted = false
    var speakerEnabled = false
    var localVideoEnabled = false
    var remoteVideoState: TelegramCallRemoteVideoState = .inactive
    var remoteAudioMuted = false
    var signalBars: Int? = nil

    var nativeMediaEngineReady: Bool {
        transportState.isReady
    }
}

struct TelegramCallPreparedConnection: Hashable {
    var reflectorId: UInt8
    var hasStun: Bool
    var hasTurn: Bool
    var hasTCP: Bool
    var ipAddress: String
    var port: Int32
    var username: String
    var password: String
}

struct TelegramCallMediaConfiguration: Hashable {
    var version: String
    var customParameters: String?
    var encryptionKey: Data
    var isOutgoing: Bool
    var isVideo: Bool
    var allowP2P: Bool
    var allowTCP: Bool
    var enableStunMarking: Bool
    var maxLayer: Int32
    var serverConfig: String
    var connections: [TelegramCallPreparedConnection]
}

enum TelegramCallMediaConfigurationBuilder {
    private static let disabledFallbackVersions = ["2.4.4"]
    private static let enabledFallbackVersions = ["13.0.0", "12.0.0", "9.0.0", "8.0.0", "7.0.0"]

    static func supportedLibraryVersions() -> [String] {
#if canImport(TgVoipWebrtc)
        let versions = OngoingCallThreadLocalContextWebrtc.versions(withIncludeReference: true)
        return versions.sorted { lhs, rhs in
            compareVersionsDescending(lhs: lhs, rhs: rhs)
        }
#else
        return disabledFallbackVersions
#endif
    }

    static func build(for call: TDLibKit.Call) -> TelegramCallMediaConfiguration? {
        guard case let .callStateReady(readyState) = call.state else {
            return nil
        }

        return build(
            for: readyState,
            isOutgoing: call.isOutgoing,
            isVideo: call.isVideo
        )
    }

    static func build(
        for readyState: CallStateReady,
        isOutgoing: Bool,
        isVideo: Bool
    ) -> TelegramCallMediaConfiguration? {
        let supportedVersions = supportedLibraryVersions()
        let selectedVersion = readyState.protocol.libraryVersions.first(where: supportedVersions.contains)
            ?? supportedVersions.first(where: readyState.protocol.libraryVersions.contains)
            ?? readyState.protocol.libraryVersions.first
            ?? enabledFallbackVersions.first

        guard let selectedVersion else {
            return nil
        }

        let reflectorIDs = readyState.servers.compactMap { server -> TdInt64? in
            if case .callServerTypeTelegramReflector = server.type {
                return server.id
            }
            return nil
        }
        .sorted()

        let reflectorMapping: [TdInt64: UInt8] = Dictionary(
            uniqueKeysWithValues: reflectorIDs.enumerated().map { offset, id in
                (id, UInt8((offset + 1) & 0xff))
            }
        )

        var preparedConnections: [TelegramCallPreparedConnection] = []
        preparedConnections.reserveCapacity(readyState.servers.count * 2)

        var allowTCP = false

        for server in readyState.servers {
            switch server.type {
            case let .callServerTypeTelegramReflector(reflector):
                if reflector.isTcp {
                    allowTCP = true
                    continue
                }

                guard let reflectorID = reflectorMapping[server.id] else {
                    continue
                }

                if !server.ipAddress.isEmpty {
                    preparedConnections.append(
                        TelegramCallPreparedConnection(
                            reflectorId: reflectorID,
                            hasStun: false,
                            hasTurn: true,
                            hasTCP: false,
                            ipAddress: server.ipAddress,
                            port: Int32(server.port),
                            username: "reflector",
                            password: hexEncoded(reflector.peerTag)
                        )
                    )
                }

                if !server.ipv6Address.isEmpty {
                    preparedConnections.append(
                        TelegramCallPreparedConnection(
                            reflectorId: reflectorID,
                            hasStun: false,
                            hasTurn: true,
                            hasTCP: false,
                            ipAddress: server.ipv6Address,
                            port: Int32(server.port),
                            username: "reflector",
                            password: hexEncoded(reflector.peerTag)
                        )
                    )
                }

            case let .callServerTypeWebrtc(webRTC):
                if !server.ipAddress.isEmpty {
                    preparedConnections.append(
                        TelegramCallPreparedConnection(
                            reflectorId: 0,
                            hasStun: webRTC.supportsStun,
                            hasTurn: webRTC.supportsTurn,
                            hasTCP: false,
                            ipAddress: server.ipAddress,
                            port: Int32(server.port),
                            username: webRTC.username,
                            password: webRTC.password
                        )
                    )
                }

                if !server.ipv6Address.isEmpty {
                    preparedConnections.append(
                        TelegramCallPreparedConnection(
                            reflectorId: 0,
                            hasStun: webRTC.supportsStun,
                            hasTurn: webRTC.supportsTurn,
                            hasTCP: false,
                            ipAddress: server.ipv6Address,
                            port: Int32(server.port),
                            username: webRTC.username,
                            password: webRTC.password
                        )
                    )
                }
            }
        }

        return TelegramCallMediaConfiguration(
            version: selectedVersion,
            customParameters: normalizedCustomParameters(readyState.customParameters),
            encryptionKey: readyState.encryptionKey,
            isOutgoing: isOutgoing,
            isVideo: isVideo,
            allowP2P: readyState.allowP2p,
            allowTCP: allowTCP,
            enableStunMarking: true,
            maxLayer: Int32(readyState.protocol.maxLayer),
            serverConfig: readyState.config,
            connections: preparedConnections
        )
    }

    private static func normalizedCustomParameters(_ rawValue: String) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func compareVersionsDescending(lhs: String, rhs: String) -> Bool {
        let lhsParts = versionComponents(from: lhs)
        let rhsParts = versionComponents(from: rhs)
        let maxCount = max(lhsParts.count, rhsParts.count)

        for index in 0 ..< maxCount {
            let lhsValue = index < lhsParts.count ? lhsParts[index] : 0
            let rhsValue = index < rhsParts.count ? rhsParts[index] : 0
            if lhsValue != rhsValue {
                return lhsValue > rhsValue
            }
        }

        return lhs > rhs
    }

    private static func versionComponents(from value: String) -> [Int] {
        value
            .split(separator: ".")
            .map { Int($0) ?? 0 }
    }

    private static func hexEncoded(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}

#if canImport(TgVoipWebrtc) && canImport(UIKit) && canImport(AVFoundation) && canImport(Network)
private final class TelegramCallQueueBridge: NSObject, OngoingCallThreadLocalContextQueueWebrtc {
    private let dispatchQueue: DispatchQueue
    private let queueKey = DispatchSpecificKey<UInt8>()
    private let queueToken: UInt8 = 1

    init(label: String) {
        dispatchQueue = DispatchQueue(label: label)
        super.init()
        dispatchQueue.setSpecific(key: queueKey, value: queueToken)
    }

    func dispatch(_ f: @escaping () -> Void) {
        dispatchQueue.async(execute: f)
    }

    func isCurrent() -> Bool {
        DispatchQueue.getSpecific(key: queueKey) == queueToken
    }

    func scheduleBlock(_ f: @escaping () -> Void, after timeout: Double) -> GroupCallDisposable {
        let item = DispatchWorkItem(block: f)
        dispatchQueue.asyncAfter(deadline: .now() + timeout, execute: item)
        return GroupCallDisposable(block: {
            item.cancel()
        })
    }
}

final class TelegramCallMediaEngine {
    static var isAvailable: Bool { true }

    static var supportedLibraryVersions: [String] {
        TelegramCallMediaConfigurationBuilder.supportedLibraryVersions()
    }

    var onStatusChanged: ((TelegramCallMediaStatus) -> Void)?

    private let queueBridge: TelegramCallQueueBridge
    private let networkMonitor = NWPathMonitor()
    private let networkMonitorQueue = DispatchQueue(label: "net.dziwisz.unios.voip.network")
    private let signalingSender: @Sendable (Data) -> Void
    private let logPath: String
    private let statsLogPath: String
    private let supportsVideo: Bool

    private var currentStatus = TelegramCallMediaStatus(
        transportState: .initializing,
        speakerEnabled: true
    )
    private var currentConfiguration: TelegramCallMediaConfiguration?
    private var context: OngoingCallThreadLocalContextWebrtc?
    private var audioDevice: SharedCallAudioDevice?
    private var videoCapturer: OngoingCallThreadLocalContextVideoCapturer?

    init(
        callID: Int,
        supportsVideo: Bool,
        signalingSender: @escaping @Sendable (Data) -> Void
    ) {
        self.queueBridge = TelegramCallQueueBridge(label: "net.dziwisz.unios.voip.call.\(callID)")
        self.signalingSender = signalingSender
        self.supportsVideo = supportsVideo

        let logsDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("UniOSVoIPLogs", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: logsDirectory,
            withIntermediateDirectories: true
        )
        self.logPath = logsDirectory.appendingPathComponent("call-\(callID).log").path
        self.statsLogPath = logsDirectory.appendingPathComponent("call-\(callID)-stats.json").path

        Self.prepareAudioSession()
        startNetworkMonitoring()
    }

    deinit {
        networkMonitor.cancel()
        stop()
    }

    func configure(with call: TDLibKit.Call) {
        guard let configuration = TelegramCallMediaConfigurationBuilder.build(for: call) else {
            return
        }

        if currentConfiguration == configuration, context != nil {
            return
        }

        currentConfiguration = configuration
        updateStatus {
            $0.transportState = .initializing
            $0.localVideoEnabled = configuration.isVideo
        }

        queueBridge.dispatch { [weak self] in
            self?.instantiateContext(configuration)
        }
    }

    func addSignalingData(_ data: Data) {
        queueBridge.dispatch { [weak self] in
            self?.context?.addSignalingData(data)
        }
    }

    func beginTermination() {
        queueBridge.dispatch { [weak self] in
            self?.context?.beginTermination()
        }
    }

    func stop() {
        queueBridge.dispatch { [weak self] in
            guard let self else {
                return
            }

            guard let context = self.context else {
                self.updateStatus {
                    $0.transportState = .stopped
                }
                return
            }

            context.beginTermination()
            context.stop { [weak self] _, _, _, _, _ in
                guard let self else {
                    return
                }

                self.context = nil
                self.videoCapturer = nil
                self.audioDevice?.setManualAudioSessionIsActive(false)
                try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])

                self.updateStatus {
                    $0.transportState = .stopped
                    $0.localVideoEnabled = false
                    $0.remoteVideoState = .inactive
                }
            }
        }
    }

    func setMuted(_ isMuted: Bool) {
        queueBridge.dispatch { [weak self] in
            self?.context?.setIsMuted(isMuted)
        }
        updateStatus {
            $0.isMuted = isMuted
        }
    }

    func setSpeakerEnabled(_ enabled: Bool) {
        do {
            try AVAudioSession.sharedInstance().overrideOutputAudioPort(enabled ? .speaker : .none)
            updateStatus {
                $0.speakerEnabled = enabled
            }
        } catch {
            updateStatus {
                $0.transportState = .failed(message: error.localizedDescription)
            }
        }
    }

    func setLocalVideoEnabled(_ enabled: Bool) {
        guard supportsVideo else {
            return
        }

        queueBridge.dispatch { [weak self] in
            guard let self else {
                return
            }

            self.videoCapturer?.setIsVideoEnabled(enabled)
            if enabled {
                self.context?.requestVideo(self.videoCapturer)
            } else {
                self.context?.disableVideo()
            }
        }

        updateStatus {
            $0.localVideoEnabled = enabled
        }
    }

    func makeIncomingVideoView(completion: @escaping (UIView?) -> Void) {
        queueBridge.dispatch { [weak self] in
            guard let context = self?.context else {
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }

            context.makeIncomingVideoView { view in
                DispatchQueue.main.async {
                    completion(view)
                }
            }
        }
    }

    func makeOutgoingVideoView(completion: @escaping (UIView?) -> Void) {
        queueBridge.dispatch { [weak self] in
            guard let videoCapturer = self?.videoCapturer else {
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }

            videoCapturer.makeOutgoingVideoView(false) { mainView, _ in
                DispatchQueue.main.async {
                    completion(mainView)
                }
            }
        }
    }

    private func instantiateContext(_ configuration: TelegramCallMediaConfiguration) {
        guard context == nil else {
            return
        }

        OngoingCallThreadLocalContextWebrtc.applyServerConfig(configuration.serverConfig)

        let audioDevice = SharedCallAudioDevice(
            disableRecording: false,
            enableSystemMute: false
        )
        self.audioDevice = audioDevice
        let videoCapturer = configuration.isVideo
            ? OngoingCallThreadLocalContextVideoCapturer(deviceId: "", keepLandscape: false)
            : nil
        self.videoCapturer = videoCapturer

        let preparedConnections = configuration.connections.map { connection in
            OngoingCallConnectionDescriptionWebrtc(
                reflectorId: connection.reflectorId,
                hasStun: connection.hasStun,
                hasTurn: connection.hasTurn,
                hasTcp: connection.hasTCP,
                ip: connection.ipAddress,
                port: connection.port,
                username: connection.username,
                password: connection.password
            )
        }

        activateAudioSession(using: audioDevice)

        let context = OngoingCallThreadLocalContextWebrtc(
            version: configuration.version,
            customParameters: configuration.customParameters,
            queue: queueBridge,
            proxy: nil,
            networkType: currentNetworkType(),
            dataSaving: .never,
            derivedState: Data(),
            key: configuration.encryptionKey,
            isOutgoing: configuration.isOutgoing,
            connections: preparedConnections,
            maxLayer: configuration.maxLayer,
            allowP2P: configuration.allowP2P,
            allowTCP: configuration.allowTCP,
            enableStunMarking: configuration.enableStunMarking,
            logPath: logPath,
            statsLogPath: statsLogPath,
            sendSignalingData: { [weak self] data in
                self?.signalingSender(data)
            },
            videoCapturer: videoCapturer,
            preferredVideoCodec: nil,
            audioInputDeviceId: "",
            audioDevice: audioDevice,
            directConnection: nil
        )

        context.stateChanged = { [weak self] state, videoState, remoteVideoState, remoteAudioState, _, _ in
            self?.handleStateChanged(
                state: state,
                videoState: videoState,
                remoteVideoState: remoteVideoState,
                remoteAudioState: remoteAudioState
            )
        }
        context.signalBarsChanged = { [weak self] signalBars in
            self?.updateStatus {
                $0.signalBars = Int(signalBars)
            }
        }

        self.context = context
        if configuration.isVideo {
            context.requestVideo(videoCapturer)
        }
    }

    private func handleStateChanged(
        state: OngoingCallStateWebrtc,
        videoState: OngoingCallVideoStateWebrtc,
        remoteVideoState: OngoingCallRemoteVideoStateWebrtc,
        remoteAudioState: OngoingCallRemoteAudioStateWebrtc
    ) {
        updateStatus { status in
            switch state {
            case .initializing:
                status.transportState = .initializing
            case .connected:
                status.transportState = .connected
            case .reconnecting:
                status.transportState = .reconnecting
            case .failed:
                status.transportState = .failed(message: "Telegram media engine reported a transport failure.")
            @unknown default:
                status.transportState = .failed(message: "Telegram media engine entered an unknown transport state.")
            }

            switch videoState {
            case .active:
                status.localVideoEnabled = true
            case .inactive, .paused:
                status.localVideoEnabled = false
            @unknown default:
                status.localVideoEnabled = false
            }

            switch remoteVideoState {
            case .inactive:
                status.remoteVideoState = .inactive
            case .active:
                status.remoteVideoState = .active
            case .paused:
                status.remoteVideoState = .paused
            @unknown default:
                status.remoteVideoState = .inactive
            }

            switch remoteAudioState {
            case .muted:
                status.remoteAudioMuted = true
            case .active:
                status.remoteAudioMuted = false
            @unknown default:
                status.remoteAudioMuted = false
            }
        }
    }

    private func updateStatus(_ update: (inout TelegramCallMediaStatus) -> Void) {
        var nextStatus = currentStatus
        update(&nextStatus)
        guard nextStatus != currentStatus else {
            return
        }

        currentStatus = nextStatus
        let statusToPublish = currentStatus
        let callback = onStatusChanged
        DispatchQueue.main.async {
            callback?(statusToPublish)
        }
    }

    private func currentNetworkType() -> OngoingCallNetworkTypeWebrtc {
        if #available(iOS 12.0, *) {
            switch networkMonitor.currentPath.status {
            case .satisfied:
                if networkMonitor.currentPath.usesInterfaceType(.wifi) {
                    return .wifi
                }
                if networkMonitor.currentPath.usesInterfaceType(.cellular) {
                    return .cellularLte
                }
                return .wifi
            case .requiresConnection, .unsatisfied:
                return .wifi
            @unknown default:
                return .wifi
            }
        }

        return .wifi
    }

    private func startNetworkMonitoring() {
        if #available(iOS 12.0, *) {
            networkMonitor.pathUpdateHandler = { [weak self] _ in
                guard let self else {
                    return
                }
                let nextType = self.currentNetworkType()
                self.queueBridge.dispatch { [weak self] in
                    self?.context?.setNetworkType(nextType)
                }
            }
            networkMonitor.start(queue: networkMonitorQueue)
        }
    }

    private func activateAudioSession(using audioDevice: SharedCallAudioDevice) {
        let audioSession = AVAudioSession.sharedInstance()

        do {
            try audioSession.setCategory(
                .playAndRecord,
                mode: .voiceChat,
                options: [
                    .allowBluetooth,
                    .allowBluetoothA2DP,
                    .defaultToSpeaker,
                    .mixWithOthers
                ]
            )
            try audioSession.setActive(true)
            try audioSession.overrideOutputAudioPort(.speaker)
            audioDevice.setManualAudioSessionIsActive(true)
            updateStatus {
                $0.speakerEnabled = true
            }
        } catch {
            updateStatus {
                $0.transportState = .failed(message: error.localizedDescription)
            }
        }
    }

    private static func prepareAudioSession() {
        AudioSessionPreparation.once
    }
}

private enum AudioSessionPreparation {
    static let once: Void = {
        SharedCallAudioDevice.setupAudioSession()
        OngoingCallThreadLocalContextWebrtc.setupAudioSession()
    }()
}
#else
final class TelegramCallMediaEngine {
    static var isAvailable: Bool { false }

    static var supportedLibraryVersions: [String] {
        TelegramCallMediaConfigurationBuilder.supportedLibraryVersions()
    }

    var onStatusChanged: ((TelegramCallMediaStatus) -> Void)?

    init(
        callID: Int,
        supportsVideo: Bool,
        signalingSender: @escaping @Sendable (Data) -> Void
    ) {
        let _ = callID
        let _ = supportsVideo
        let _ = signalingSender
    }

    func configure(with call: TDLibKit.Call) {
        let _ = call
    }

    func addSignalingData(_ data: Data) {
        let _ = data
    }

    func beginTermination() {
    }

    func stop() {
    }

    func setMuted(_ isMuted: Bool) {
        let _ = isMuted
    }

    func setSpeakerEnabled(_ enabled: Bool) {
        let _ = enabled
    }

    func setLocalVideoEnabled(_ enabled: Bool) {
        let _ = enabled
    }

#if canImport(UIKit)
    func makeIncomingVideoView(completion: @escaping (UIView?) -> Void) {
        completion(nil)
    }

    func makeOutgoingVideoView(completion: @escaping (UIView?) -> Void) {
        completion(nil)
    }
#endif
}
#endif
