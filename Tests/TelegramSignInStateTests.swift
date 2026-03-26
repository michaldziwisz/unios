import XCTest
@testable import UniOS

final class TelegramSignInStateTests: XCTestCase {
    func testEmailAddressStateAcceptsEmailAddress() {
        let state = TelegramSignInState.waitingForEmailAddress(
            message: "Enter the email address linked to your Telegram account."
        )

        XCTAssertTrue(state.acceptsEmailAddress)
        XCTAssertFalse(state.acceptsEmailCode)
        XCTAssertNil(state.confirmationLink)
    }

    func testEmailCodeStateAcceptsEmailCode() {
        let state = TelegramSignInState.waitingForEmailCode(
            message: "Enter the Telegram code sent to j***@example.com.",
            emailPattern: "j***@example.com",
            codeLength: 6
        )

        XCTAssertFalse(state.acceptsEmailAddress)
        XCTAssertTrue(state.acceptsEmailCode)
        XCTAssertEqual(state.statusMessage, "Enter the Telegram code sent to j***@example.com.")
    }

    func testOtherDeviceConfirmationExposesLink() {
        let link = "tg://login?token=example"
        let state = TelegramSignInState.waitingForOtherDeviceConfirmation(
            message: "Confirm this sign in from another device.",
            link: link
        )

        XCTAssertEqual(state.confirmationLink, link)
        XCTAssertEqual(state.statusMessage, "Confirm this sign in from another device.")
    }
}
