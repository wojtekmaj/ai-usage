import SwiftUI

struct ClaudeConnectionView: View {
    @ObservedObject var environment: AppEnvironment

    private var titleKey: L10nKey {
        if environment.claudeSignInError == .claudeCredentialAccessRequired {
            return .claudeCredentialAccessTitle
        }

        return switch environment.claudeReconnectPhase {
        case .checkingCredentials: .claudeReconnecting
        case .signingIn: .claudeSignInWaiting
        case nil: .claudeSignInRequired
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(environment.localizer.text(titleKey))
                .font(.subheadline.weight(.medium))

            Text(environment.localizer.text(.claudeReconnectHelp))
                .font(.footnote)
                .foregroundStyle(.secondary)

            if let error = environment.claudeSignInError {
                Text(environment.localizer.text(error))
                    .font(.footnote)
                    .foregroundStyle(.red)

                if error == .claudeNotInstalled {
                    Link(environment.localizer.text(.installClaudeCode), destination: URL(string: "https://code.claude.com/docs/en/setup")!)
                }
            }

            if environment.isReconnectingClaude {
                HStack {
                    ProgressView().controlSize(.small)
                    Button(environment.localizer.text(.cancel)) {
                        environment.cancelClaudeSignIn()
                    }
                }
            } else if environment.claudeSignInError == .claudeCredentialAccessRequired {
                Button(environment.localizer.text(.allowClaudeCredentialAccess)) {
                    environment.reconnectClaude()
                }
            } else {
                Button(environment.localizer.text(.reconnectClaude)) {
                    environment.reconnectClaude()
                }
            }
        }
    }
}
