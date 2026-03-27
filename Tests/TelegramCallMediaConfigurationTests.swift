import XCTest
import TDLibKit
@testable import UniOS

final class TelegramCallMediaConfigurationTests: XCTestCase {
    func testBuildMapsReflectorsAndWebRTCServers() throws {
        let selectedVersion = TelegramCallMediaConfigurationBuilder.supportedLibraryVersions().first ?? "2.4.4"
        let reflectorPeerTag = Data(repeating: 0xAB, count: 16)
        let readyState = CallStateReady(
            allowP2p: true,
            config: "{\"foo\":1}",
            customParameters: "{\"network_use_tcponly\":false}",
            emojis: ["😀", "🎧", "📞", "🔒"],
            encryptionKey: Data([0x01, 0x02, 0x03]),
            isGroupCallSupported: true,
            protocol: CallProtocol(
                libraryVersions: [selectedVersion],
                maxLayer: 92,
                minLayer: 65,
                udpP2p: true,
                udpReflector: true
            ),
            servers: [
                CallServer(
                    id: 1,
                    ipAddress: "149.154.167.51",
                    ipv6Address: "2001:db8::10",
                    port: 443,
                    type: .callServerTypeTelegramReflector(
                        CallServerTypeTelegramReflector(
                            isTcp: false,
                            peerTag: reflectorPeerTag
                        )
                    )
                ),
                CallServer(
                    id: 2,
                    ipAddress: "149.154.167.91",
                    ipv6Address: "",
                    port: 443,
                    type: .callServerTypeTelegramReflector(
                        CallServerTypeTelegramReflector(
                            isTcp: true,
                            peerTag: Data(repeating: 0xCD, count: 16)
                        )
                    )
                ),
                CallServer(
                    id: 3,
                    ipAddress: "203.0.113.10",
                    ipv6Address: "",
                    port: 3478,
                    type: .callServerTypeWebrtc(
                        CallServerTypeWebrtc(
                            password: "password",
                            supportsStun: true,
                            supportsTurn: true,
                            username: "telegram"
                        )
                    )
                )
            ]
        )

        let configuration = try XCTUnwrap(
            TelegramCallMediaConfigurationBuilder.build(
                for: readyState,
                isOutgoing: true,
                isVideo: true
            )
        )

        XCTAssertEqual(configuration.version, selectedVersion)
        XCTAssertTrue(configuration.allowTCP)
        XCTAssertEqual(configuration.connections.count, 3)
        XCTAssertEqual(configuration.connections.first?.username, "reflector")
        XCTAssertEqual(configuration.connections.first?.password, "abababababababababababababababab")
        XCTAssertEqual(configuration.connections.last?.username, "telegram")
        XCTAssertTrue(configuration.connections.last?.hasStun ?? false)
        XCTAssertTrue(configuration.connections.last?.hasTurn ?? false)
    }

    func testBuildNormalizesEmptyCustomParametersToNil() throws {
        let selectedVersion = TelegramCallMediaConfigurationBuilder.supportedLibraryVersions().first ?? "2.4.4"
        let readyState = CallStateReady(
            allowP2p: false,
            config: "{}",
            customParameters: "   ",
            emojis: [],
            encryptionKey: Data([0x0F]),
            isGroupCallSupported: false,
            protocol: CallProtocol(
                libraryVersions: [selectedVersion],
                maxLayer: 92,
                minLayer: 65,
                udpP2p: true,
                udpReflector: true
            ),
            servers: []
        )

        let configuration = try XCTUnwrap(
            TelegramCallMediaConfigurationBuilder.build(
                for: readyState,
                isOutgoing: false,
                isVideo: false
            )
        )

        XCTAssertNil(configuration.customParameters)
    }
}
