import SwiftUI
#if canImport(CoreImage.CIFilterBuiltins)
import CoreImage
import CoreImage.CIFilterBuiltins
#endif
#if canImport(UIKit)
import UIKit
#endif

struct SignInView: View {
    private enum SignInField: Hashable {
        case phone
        case emailAddress
        case emailCode
        case code
        case password
    }

    @EnvironmentObject private var appModel: UniOSAppModel
    @Environment(\.openURL) private var openURL
    @FocusState private var focusedField: SignInField?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                heroSection
                telegramSection
                featureSection
            }
            .padding(20)
            .padding(.bottom, 40)
        }
        .background(UniOSTheme.canvas.ignoresSafeArea())
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                focusedField = appModel.canUseTelegram ? .phone : nil
            }
        }
        .onChange(of: appModel.telegramSignInState) { _, state in
            switch state {
            case .waitingForPhone:
                focusedField = .phone
            case .waitingForEmailAddress:
                focusedField = .emailAddress
            case .waitingForEmailCode:
                focusedField = .emailCode
            case .waitingForCode:
                focusedField = .code
            case .waitingForPassword:
                focusedField = .password
            case .waitingForOtherDeviceConfirmation:
                focusedField = nil
            case .working, .ready, .failed, .unavailable:
                break
            }
        }
    }

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(UniOSTheme.hero)
                .frame(height: 220)
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("UniOS")
                            .font(.system(size: 42, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text("A native iPhone reading of Unigram, designed for screen-reader confidence first.")
                            .font(.headline)
                            .foregroundStyle(.white.opacity(0.92))
                    }
                    .padding(24)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("UniOS. A native iPhone reading of Unigram, designed for screen reader confidence first.")

            Text("Sign In To Telegram")
                .font(.title2.weight(.bold))
            Text("Use your real Telegram account directly in UniOS. The sign-in flow stays native, accessible, and VoiceOver-first.")
                .foregroundStyle(UniOSTheme.quietText)
        }
    }

    private var telegramSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Telegram")
                .font(.title3.weight(.bold))

            Text(appModel.canUseTelegram ? "Real Telegram sign in is enabled in this build through TDLibKit." : "Telegram sign in is unavailable until `Config/TelegramSecrets.xcconfig` is generated from your local Postmaster credentials.")
                .foregroundStyle(UniOSTheme.quietText)

            statusCard

            if appModel.canUseTelegram {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Phone Number")
                        .font(.headline)
                    TextField("+48 600 000 000", text: $appModel.signInPhoneNumber)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color(uiColor: .systemBackground))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(UniOSTheme.tint.opacity(0.18), lineWidth: 1)
                        )
                        .focused($focusedField, equals: .phone)
                        .disabled(appModel.telegramSignInState.isWorking)
                        .accessibilityHint("Enter the Telegram phone number for sign in.")
                }
            }

            if shouldShowEmailAddressField {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recovery Email Address")
                        .font(.headline)
                    TextField("name@example.com", text: $appModel.signInEmailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .textContentType(.emailAddress)
                        .autocorrectionDisabled()
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color(uiColor: .systemBackground))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(UniOSTheme.tint.opacity(0.18), lineWidth: 1)
                        )
                        .focused($focusedField, equals: .emailAddress)
                        .disabled(appModel.telegramSignInState.isWorking)
                        .accessibilityHint("Enter the email address Telegram asks for during sign in.")
                }
            }

            if shouldShowCodeField {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Verification Code")
                        .font(.headline)
                    TextField("12345", text: $appModel.signInVerificationCode)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color(uiColor: .systemBackground))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(UniOSTheme.tint.opacity(0.18), lineWidth: 1)
                        )
                        .focused($focusedField, equals: .code)
                        .disabled(appModel.telegramSignInState.isWorking)
                        .accessibilityHint("Enter the Telegram verification code.")
                }
            }

            if shouldShowEmailCodeField {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Email Code")
                        .font(.headline)
                    TextField("Email code", text: $appModel.signInEmailCode)
                        .textInputAutocapitalization(.never)
                        .textContentType(.oneTimeCode)
                        .autocorrectionDisabled()
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color(uiColor: .systemBackground))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(UniOSTheme.tint.opacity(0.18), lineWidth: 1)
                        )
                        .focused($focusedField, equals: .emailCode)
                        .disabled(appModel.telegramSignInState.isWorking)
                        .accessibilityHint("Enter the Telegram code sent to the email address linked to this account.")
                }
            }

            if shouldShowPasswordField {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Two-Step Verification Password")
                        .font(.headline)
                    SecureField("Telegram password", text: $appModel.signInPassword)
                        .textContentType(.password)
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color(uiColor: .systemBackground))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(UniOSTheme.tint.opacity(0.18), lineWidth: 1)
                        )
                        .focused($focusedField, equals: .password)
                        .disabled(appModel.telegramSignInState.isWorking)
                        .accessibilityHint("Enter the Telegram two step verification password.")
                }
            }

            if let confirmationLink = appModel.telegramSignInState.confirmationLink {
                otherDeviceConfirmationSection(confirmationLink: confirmationLink)
            }

            if appModel.canUseTelegram {
                Button(action: submitTelegram) {
                    Label(primaryTelegramActionTitle, systemImage: primaryTelegramActionIcon)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isTelegramPrimaryActionDisabled)
                .accessibilityHint(primaryTelegramActionHint)
            }
        }
        .uniosCard()
    }

    private var featureSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("What Is Already Optimized")
                .font(.title3.weight(.bold))

            FeatureCard(
                title: "Screen Reader First",
                description: "Conversation rows expose explicit names, unread counts, mute state, and timestamps."
            )

            FeatureCard(
                title: "TDLibKit Bridge",
                description: "Telegram auth, chat sync, message history, media, and calling are routed through TDLibKit."
            )

            FeatureCard(
                title: "Fast Chat Triage",
                description: "An unread shortcut can jump directly to the next unseen conversation."
            )

            FeatureCard(
                title: "Build Pipeline Ready",
                description: "GitHub-hosted macOS runners generate an unsigned IPA artifact for testing."
            )
        }
    }

    private var statusCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: statusIcon)
                .font(.title3)
                .foregroundStyle(statusColor)

            VStack(alignment: .leading, spacing: 6) {
                Text("Current Status")
                    .font(.headline)
                Text(appModel.telegramSignInState.statusMessage)
                    .foregroundStyle(UniOSTheme.quietText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(uiColor: .systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(statusColor.opacity(0.22), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }

    private var shouldShowCodeField: Bool {
        appModel.telegramSignInState.acceptsCode || (!appModel.signInVerificationCode.isEmpty && appModel.canUseTelegram)
    }

    private var shouldShowEmailAddressField: Bool {
        appModel.telegramSignInState.acceptsEmailAddress || (!appModel.signInEmailAddress.isEmpty && appModel.canUseTelegram)
    }

    private var shouldShowEmailCodeField: Bool {
        appModel.telegramSignInState.acceptsEmailCode || (!appModel.signInEmailCode.isEmpty && appModel.canUseTelegram)
    }

    private var shouldShowPasswordField: Bool {
        appModel.telegramSignInState.acceptsPassword || (!appModel.signInPassword.isEmpty && appModel.canUseTelegram)
    }

    private var primaryTelegramActionTitle: String {
        switch appModel.telegramSignInState {
        case .waitingForPhone, .unavailable:
            return "Continue With Telegram"
        case .waitingForEmailAddress:
            return "Continue With Email"
        case .waitingForEmailCode:
            return "Verify Email Code"
        case .waitingForCode:
            return "Verify Telegram Code"
        case .waitingForOtherDeviceConfirmation:
            return "Awaiting Device Confirmation"
        case .waitingForPassword:
            return "Verify Telegram Password"
        case .working:
            return "Working"
        case .ready:
            return "Connecting To Telegram"
        case .failed:
            if shouldShowPasswordField {
                return "Retry Telegram Password"
            }
            if shouldShowEmailCodeField {
                return "Retry Email Code"
            }
            if shouldShowCodeField {
                return "Retry Telegram Code"
            }
            if shouldShowEmailAddressField {
                return "Retry Email Address"
            }
            return "Retry Telegram Sign In"
        }
    }

    private var primaryTelegramActionIcon: String {
        switch appModel.telegramSignInState {
        case .waitingForEmailAddress, .waitingForEmailCode:
            return "envelope.fill"
        case .waitingForCode:
            return "number"
        case .waitingForOtherDeviceConfirmation:
            return "qrcode.viewfinder"
        case .waitingForPassword:
            return "lock.fill"
        case .working, .ready:
            return "hourglass"
        default:
            return "paperplane.fill"
        }
    }

    private var primaryTelegramActionHint: String {
        switch appModel.telegramSignInState {
        case .waitingForPhone, .unavailable:
            return "Starts Telegram authentication with the current phone number."
        case .waitingForEmailAddress:
            return "Sends the email address Telegram requested for this sign in."
        case .waitingForEmailCode:
            return "Checks the Telegram code sent to the linked email address."
        case .waitingForCode:
            return "Checks the Telegram verification code."
        case .waitingForOtherDeviceConfirmation:
            return "Use the confirmation link or QR code shown below."
        case .waitingForPassword:
            return "Checks the Telegram two step verification password."
        case .working, .ready:
            return "Telegram is currently processing the sign in state."
        case .failed:
            return "Retries the current Telegram sign in step."
        }
    }

    private var isTelegramPrimaryActionDisabled: Bool {
        if !appModel.canUseTelegram {
            return true
        }

        if appModel.telegramSignInState.isWorking || appModel.telegramSignInState == .ready {
            return true
        }

        switch appModel.telegramSignInState {
        case .waitingForEmailAddress:
            return appModel.signInEmailAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .waitingForEmailCode:
            return appModel.signInEmailCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .waitingForCode:
            return appModel.signInVerificationCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .waitingForOtherDeviceConfirmation:
            return true
        case .waitingForPassword:
            return appModel.signInPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        default:
            return appModel.signInPhoneNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private var statusColor: Color {
        switch appModel.telegramSignInState {
        case .failed:
            return .red
        case .ready:
            return .green
        case .working:
            return .orange
        default:
            return UniOSTheme.tint
        }
    }

    private var statusIcon: String {
        switch appModel.telegramSignInState {
        case .failed:
            return "exclamationmark.triangle.fill"
        case .ready:
            return "checkmark.seal.fill"
        case .working:
            return "hourglass"
        case .waitingForEmailAddress, .waitingForEmailCode:
            return "envelope.badge.fill"
        case .waitingForCode:
            return "number.square.fill"
        case .waitingForOtherDeviceConfirmation:
            return "qrcode.viewfinder"
        case .waitingForPassword:
            return "lock.fill"
        case .waitingForPhone, .unavailable:
            return "phone.fill"
        }
    }

    private func submitTelegram() {
        if shouldShowPasswordField && (appModel.telegramSignInState.acceptsPassword || !appModel.signInPassword.isEmpty) {
            appModel.submitTelegramPassword()
            return
        }

        if shouldShowEmailCodeField && (appModel.telegramSignInState.acceptsEmailCode || !appModel.signInEmailCode.isEmpty) {
            appModel.submitTelegramEmailCode()
            return
        }

        if shouldShowCodeField && (appModel.telegramSignInState.acceptsCode || !appModel.signInVerificationCode.isEmpty) {
            appModel.submitTelegramCode()
            return
        }

        if shouldShowEmailAddressField && (appModel.telegramSignInState.acceptsEmailAddress || !appModel.signInEmailAddress.isEmpty) {
            appModel.submitTelegramEmailAddress()
            return
        }

        appModel.submitTelegramPhoneNumber()
    }

    @ViewBuilder
    private func otherDeviceConfirmationSection(confirmationLink: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Confirm On Another Device")
                .font(.headline)

            Text("If Telegram asks for device confirmation, open the link below or scan the QR code with another device that is already signed in.")
                .foregroundStyle(UniOSTheme.quietText)

            if let qrImage = TelegramConfirmationQRCode.makeImage(from: confirmationLink) {
                Image(uiImage: qrImage)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 220, maxHeight: 220)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color(uiColor: .systemBackground))
                    )
                    .accessibilityLabel("QR code for Telegram device confirmation.")
                    .accessibilityHint("Scan this QR code with another device that is already signed in to Telegram.")
            }

            Text(confirmationLink)
                .font(.footnote.monospaced())
                .foregroundStyle(UniOSTheme.quietText)
                .textSelection(.enabled)
                .accessibilityLabel("Telegram confirmation link.")
                .accessibilityValue(confirmationLink)

            HStack(spacing: 12) {
                Button {
                    openTelegramConfirmationLink(confirmationLink)
                } label: {
                    Label("Open Telegram Link", systemImage: "arrow.up.right.square")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityHint("Opens the Telegram confirmation link on this device.")

                Button {
                    copyTelegramConfirmationLink(confirmationLink)
                } label: {
                    Label("Copy Link", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityHint("Copies the Telegram confirmation link to the clipboard.")
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(uiColor: .systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(UniOSTheme.tint.opacity(0.22), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }

    private func openTelegramConfirmationLink(_ confirmationLink: String) {
        guard let url = URL(string: confirmationLink) else {
            VoiceOverAnnouncer.post("Telegram confirmation link is invalid.")
            return
        }

        openURL(url)
        VoiceOverAnnouncer.post("Opened the Telegram confirmation link.")
    }

    private func copyTelegramConfirmationLink(_ confirmationLink: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = confirmationLink
        #endif
        VoiceOverAnnouncer.post("Telegram confirmation link copied.")
    }
}

private struct FeatureCard: View {
    let title: String
    let description: String

    var bodyView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(description)
                .foregroundStyle(UniOSTheme.quietText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .uniosCard()
    }

    var body: some View {
        bodyView
    }
}

private enum TelegramConfirmationQRCode {
    #if canImport(CoreImage.CIFilterBuiltins) && canImport(UIKit)
    private static let context = CIContext()

    static func makeImage(from value: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(value.utf8)
        filter.correctionLevel = "M"

        guard
            let outputImage = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 14, y: 14)),
            let cgImage = context.createCGImage(outputImage, from: outputImage.extent)
        else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }
    #else
    static func makeImage(from value: String) -> UIImage? {
        _ = value
        return nil
    }
    #endif
}
