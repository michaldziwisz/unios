import SwiftUI

struct SignInView: View {
    private enum SignInField: Hashable {
        case phone
        case code
        case password
        case demoName
    }

    @EnvironmentObject private var appModel: UniOSAppModel
    @FocusState private var focusedField: SignInField?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                heroSection
                telegramSection
                demoSection
                featureSection
            }
            .padding(20)
            .padding(.bottom, 40)
        }
        .background(UniOSTheme.canvas.ignoresSafeArea())
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                focusedField = appModel.canUseTelegram ? .phone : .demoName
            }
        }
        .onChange(of: appModel.telegramSignInState) { _, state in
            switch state {
            case .waitingForPhone:
                focusedField = .phone
            case .waitingForCode:
                focusedField = .code
            case .waitingForPassword:
                focusedField = .password
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

            Text("Accessible Sign In")
                .font(.title2.weight(.bold))
            Text("This build keeps the demo workspace, and can also use TDLibKit for real Telegram authentication when local API credentials are configured.")
                .foregroundStyle(UniOSTheme.quietText)
        }
    }

    private var telegramSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Telegram")
                .font(.title3.weight(.bold))

            Text(appModel.canUseTelegram ? "Real Telegram sign in is enabled in this build through TDLibKit." : "Telegram sign in becomes available after generating `Config/TelegramSecrets.xcconfig` from your local Postmaster credentials.")
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

    private var demoSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Demo Workspace")
                .font(.title3.weight(.bold))

            Text("The demo path keeps sample conversations so focus order, spoken labels, and VoiceOver behavior can be validated even without Telegram credentials.")
                .foregroundStyle(UniOSTheme.quietText)

            VStack(alignment: .leading, spacing: 8) {
                Text("Display Name")
                    .font(.headline)
                TextField("VoiceOver Pilot", text: $appModel.signInName)
                    .textContentType(.name)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color(uiColor: .systemBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(UniOSTheme.tint.opacity(0.18), lineWidth: 1)
                    )
                    .focused($focusedField, equals: .demoName)
                    .accessibilityHint("Enter the name used in outgoing demo messages.")
            }

            Button {
                appModel.signInDemo()
            } label: {
                Label("Continue To Demo Workspace", systemImage: "arrow.right.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .accessibilityHint("Loads the sample account and opens the accessible chat interface.")
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
                description: "When credentials are present, Telegram auth, chat list sync, message history, and text sending use TDLibKit."
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

    private var shouldShowPasswordField: Bool {
        appModel.telegramSignInState.acceptsPassword || (!appModel.signInPassword.isEmpty && appModel.canUseTelegram)
    }

    private var primaryTelegramActionTitle: String {
        switch appModel.telegramSignInState {
        case .waitingForPhone, .unavailable:
            return "Continue With Telegram"
        case .waitingForCode:
            return "Verify Telegram Code"
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
            if shouldShowCodeField {
                return "Retry Telegram Code"
            }
            return "Retry Telegram Sign In"
        }
    }

    private var primaryTelegramActionIcon: String {
        switch appModel.telegramSignInState {
        case .waitingForCode:
            return "number"
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
        case .waitingForCode:
            return "Checks the Telegram verification code."
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
        case .waitingForCode:
            return appModel.signInVerificationCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
        case .waitingForCode:
            return "number.square.fill"
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

        if shouldShowCodeField && (appModel.telegramSignInState.acceptsCode || !appModel.signInVerificationCode.isEmpty) {
            appModel.submitTelegramCode()
            return
        }

        appModel.submitTelegramPhoneNumber()
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
