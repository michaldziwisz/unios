import SwiftUI

struct SignInView: View {
    @EnvironmentObject private var appModel: UniOSAppModel
    @FocusState private var phoneFieldFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                heroSection
                formSection
                featureSection
            }
            .padding(20)
            .padding(.bottom, 40)
        }
        .background(UniOSTheme.canvas.ignoresSafeArea())
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                phoneFieldFocused = true
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

            Text("Demo Sign In")
                .font(.title2.weight(.bold))
            Text("The current build uses sample data so the interaction flow, focus order, and VoiceOver speech can be validated before network integration.")
                .foregroundStyle(UniOSTheme.quietText)
        }
    }

    private var formSection: some View {
        VStack(alignment: .leading, spacing: 18) {
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
                    .focused($phoneFieldFocused)
                    .accessibilityHint("Enter a phone number for the demo workspace.")
            }

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
                    .accessibilityHint("Enter the name used in outgoing messages.")
            }

            Button {
                appModel.signInDemo()
            } label: {
                Label("Continue To Demo Workspace", systemImage: "arrow.right.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
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
                title: "Fast Chat Triage",
                description: "An unread shortcut can jump directly to the next unseen conversation."
            )

            FeatureCard(
                title: "Build Pipeline Ready",
                description: "GitHub-hosted macOS runners generate an unsigned IPA artifact for testing."
            )
        }
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
