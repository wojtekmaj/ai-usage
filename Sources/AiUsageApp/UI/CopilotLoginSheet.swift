import SwiftUI
import WebKit

@MainActor
private final class CopilotLoginController: ObservableObject {
    let webView: WKWebView
    private let targetURL = URL(string: "https://github.com/settings/billing/premium_requests_usage")!

    init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/146.0.0.0 Safari/537.36"
        self.webView = webView
        reload()
    }

    func reload() {
        webView.load(URLRequest(url: targetURL))
    }

    func captureSession() async -> CopilotSessionState {
        let cookies = await withCheckedContinuation { continuation in
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }

        return CopilotSessionState(
            cookies: cookies
                .filter { $0.domain.contains("github.com") }
                .map(StoredCookie.init(cookie:))
        )
    }
}

struct CopilotLoginSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var controller = CopilotLoginController()
    @State private var isSaving = false
    @State private var errorMessage: String?

    let localizer: Localizer
    let onSave: (CopilotSessionState) async throws -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(localizer.text(.openGitHubCopilotAndSignIn))
                .font(.headline)

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            WebViewContainer(webView: controller.webView)
                .frame(minWidth: 760, minHeight: 560)

            HStack {
                Button(localizer.text(.reload)) {
                    controller.reload()
                }

                Spacer()

                Button(localizer.text(.cancel)) {
                    dismiss()
                }

                Button(localizer.text(.saveSession)) {
                    Task {
                        isSaving = true
                        defer { isSaving = false }

                        let session = await controller.captureSession()
                        guard session.cookies.isEmpty == false else {
                            errorMessage = localizer.text(.noGitHubCopilotSessionFound)
                            return
                        }

                        do {
                            try await onSave(session)
                            dismiss()
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isSaving)
            }
        }
        .padding(16)
    }
}
