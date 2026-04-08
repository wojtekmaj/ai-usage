import SwiftUI
import WebKit

@MainActor
private final class CodexLoginController: ObservableObject {
    let webView: WKWebView
    private let targetURL = URL(string: "https://chatgpt.com/codex/settings/usage")!

    init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 15_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
        self.webView = webView
        reload()
    }

    func reload() {
        webView.load(URLRequest(url: targetURL))
    }

    func captureSession() async -> CodexSessionState {
        let cookies = await withCheckedContinuation { continuation in
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }

        async let localStorage = captureStorage(named: "localStorage")
        async let sessionStorage = captureStorage(named: "sessionStorage")

        return CodexSessionState(
            cookies: cookies
            .filter { cookie in
                cookie.domain.contains("chatgpt.com") || cookie.domain.contains("openai.com")
            }
            .map(StoredCookie.init(cookie:)),
            localStorage: await localStorage,
            sessionStorage: await sessionStorage
        )
    }

    private func captureStorage(named storageName: String) async -> [StoredWebStorageItem] {
        let payload = await javaScriptString("""
        (function() {
            try {
                const storage = window['\(storageName)'];
                const result = {};
                for (let index = 0; index < storage.length; index += 1) {
                    const key = storage.key(index);
                    if (key !== null) {
                        result[key] = storage.getItem(key) ?? '';
                    }
                }
                return JSON.stringify(result);
            } catch (error) {
                return '{}';
            }
        })();
        """)

        guard let data = payload.data(using: .utf8),
              let dictionary = try? JSONDecoder().decode([String: String].self, from: data) else {
            return []
        }

        return dictionary
            .sorted { $0.key < $1.key }
            .map { StoredWebStorageItem(key: $0.key, value: $0.value) }
    }

    private func javaScriptString(_ source: String) async -> String {
        await withCheckedContinuation { continuation in
            webView.evaluateJavaScript(source) { value, _ in
                continuation.resume(returning: value as? String ?? "")
            }
        }
    }
}

struct CodexLoginSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var controller = CodexLoginController()
    @State private var isSaving = false
    @State private var errorMessage: String?

    let localizer: Localizer
    let onSave: (CodexSessionState) async throws -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(localizer.text(.openCodexAndSignIn))
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
                            errorMessage = localizer.text(.noCodexSessionFound)
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
