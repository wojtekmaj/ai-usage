import Foundation
import WebKit

struct StoredCookie: Codable, Hashable, Sendable {
    var name: String
    var value: String
    var domain: String
    var path: String
    var expiresAtUTC: Date?
    var isSecure: Bool

    init(cookie: HTTPCookie) {
        self.name = cookie.name
        self.value = cookie.value
        self.domain = cookie.domain
        self.path = cookie.path
        self.expiresAtUTC = cookie.expiresDate
        self.isSecure = cookie.isSecure
    }

    var httpCookie: HTTPCookie? {
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: name,
            .value: value,
            .domain: domain,
            .path: path,
        ]

        if let expiresAtUTC {
            properties[.expires] = expiresAtUTC
        }

        if isSecure {
            properties[.secure] = true
        }

        return HTTPCookie(properties: properties)
    }
}

struct StoredWebStorageItem: Codable, Hashable, Sendable {
    var key: String
    var value: String
}

struct CodexSessionState: Codable, Hashable, Sendable {
    var cookies: [StoredCookie]
    var localStorage: [StoredWebStorageItem]
    var sessionStorage: [StoredWebStorageItem]

    init(
        cookies: [StoredCookie],
        localStorage: [StoredWebStorageItem] = [],
        sessionStorage: [StoredWebStorageItem] = []
    ) {
        self.cookies = cookies
        self.localStorage = localStorage
        self.sessionStorage = sessionStorage
    }
}

private struct CodexRequestContext: Sendable {
    let bearerToken: String
    let deviceID: String?
}

@MainActor
final class CodexProvider: UsageProvider {
    let id: ProviderID = .codex
    let sourceDescription = "ChatGPT Codex session"

    private let keychain: KeychainStore
    private let logStore: LogStore
    private let sessionAccount = "codex.session-cookies"
    private let authSessionURL = URL(string: "https://chatgpt.com/api/auth/session")!
    private let usageAPIURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
    private let usagePageURL = URL(string: "https://chatgpt.com/codex/settings/usage")!

    init(keychain: KeychainStore, logStore: LogStore) {
        self.keychain = keychain
        self.logStore = logStore
    }

    func currentAuthState() -> ProviderAuthState {
        let session = (try? loadSession()) ?? nil
        return (session?.cookies.isEmpty == false) ? .configured : .signedOut
    }

    func saveSession(_ session: CodexSessionState) throws {
        let data = try JSONEncoder().encode(session)
        try keychain.save(data: data, account: sessionAccount)
    }

    func clearAuth() throws {
        try keychain.delete(account: sessionAccount)
    }

    func refresh(now: Date) async -> ProviderSnapshot {
        let baseMetrics = [
            UsageMetric(kind: .codexFiveHour, remainingFraction: nil, remainingValue: nil, totalValue: nil, unit: .percentage, resetAtUTC: nil, lastUpdatedAtUTC: now, detailText: nil),
            UsageMetric(kind: .codexWeekly, remainingFraction: nil, remainingValue: nil, totalValue: nil, unit: .percentage, resetAtUTC: nil, lastUpdatedAtUTC: now, detailText: nil),
            UsageMetric(kind: .codexCredits, remainingFraction: nil, remainingValue: nil, totalValue: nil, unit: .credits, resetAtUTC: nil, lastUpdatedAtUTC: now, detailText: nil),
        ]

        let storedSession = (try? loadSession()) ?? nil
        guard let session = storedSession, session.cookies.isEmpty == false else {
            logStore.append(level: .warning, category: "codex", message: "Refresh skipped because no Codex cookies are configured.")
            return ProviderSnapshot(provider: id, authState: .signedOut, fetchState: .missingAuth, fetchedAtUTC: nil, metrics: baseMetrics, errorDescription: nil, sourceDescription: sourceDescription)
        }

        logStore.append(
            category: "codex",
            message: "Starting refresh with \(session.cookies.count) stored cookies, \(session.localStorage.count) localStorage keys, and \(session.sessionStorage.count) sessionStorage keys: \(session.cookies.map(\.name).sorted().joined(separator: ", "))"
        )

        do {
            let requestContext = try await resolveRequestContext(session: session)
            logStore.append(category: "codex", message: "Resolved Codex request context from ChatGPT session.")

            let apiPayload = try await fetchJSON(
                url: usageAPIURL,
                cookies: session.cookies,
                requestContext: requestContext,
                includeWHAMHeaders: true
            )
            if let dictionary = apiPayload as? [String: Any] {
                logStore.append(category: "codex", message: "WHAM payload keys: \(dictionary.keys.sorted().joined(separator: ", "))")
            }

            let metrics = try CodexHTMLParser.parse(apiPayload: apiPayload, now: now)
            logStore.append(category: "codex", message: "Parsed WHAM usage payload successfully.")

            return ProviderSnapshot(provider: id, authState: .authenticated, fetchState: .ok, fetchedAtUTC: now, metrics: metrics, errorDescription: nil, sourceDescription: sourceDescription)
        } catch {
            logStore.append(level: .warning, category: "codex", message: "WHAM usage fetch failed, falling back to rendered WebKit page. Error: \(error.localizedDescription)")
            do {
                let extraction = try await CodexPageExtractor(url: usagePageURL, logStore: logStore).extract(session: session)
                try? saveSession(extraction.session)

                if let usagePayload = extraction.usagePayload {
                    let metrics = try CodexHTMLParser.parse(apiPayload: usagePayload, now: now)
                    logStore.append(category: "codex", message: "Parsed WHAM usage payload successfully through WebKit session context.")

                    return ProviderSnapshot(provider: id, authState: .authenticated, fetchState: .ok, fetchedAtUTC: now, metrics: metrics, errorDescription: nil, sourceDescription: sourceDescription)
                }

                if extraction.page.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   extraction.session.localStorage.isEmpty,
                   extraction.session.sessionStorage.isEmpty {
                    throw CodexProviderError.incompleteSessionContext
                }

                logStore.append(category: "codex", message: "Rendered usage page title: \(extraction.page.title)")
                let metrics = try CodexHTMLParser.parse(text: extraction.page.text, html: extraction.page.html, now: now)
                logStore.append(category: "codex", message: "Parsed rendered Codex usage page successfully.")

                return ProviderSnapshot(provider: id, authState: .authenticated, fetchState: .ok, fetchedAtUTC: now, metrics: metrics, errorDescription: nil, sourceDescription: sourceDescription)
            } catch {
                logStore.append(level: .error, category: "codex", message: "Refresh failed after API and WebKit fallback: \(error.localizedDescription)")
                return ProviderSnapshot(provider: id, authState: .configured, fetchState: .failed, fetchedAtUTC: now, metrics: baseMetrics, errorDescription: error.localizedDescription, sourceDescription: sourceDescription)
            }
        }
    }

    private func loadSession() throws -> CodexSessionState? {
        guard let data = try keychain.loadData(account: sessionAccount) else {
            return nil
        }

        if let session = try? JSONDecoder().decode(CodexSessionState.self, from: data) {
            return session
        }

        let cookies = try JSONDecoder().decode([StoredCookie].self, from: data)
        return CodexSessionState(cookies: cookies)
    }

    private func fetchJSON(
        url: URL,
        cookies: [StoredCookie],
        accept: String = "application/json",
        requestContext: CodexRequestContext? = nil,
        includeWHAMHeaders: Bool = false
    ) async throws -> Any {
        let data = try await executeRequest(
            url: url,
            cookies: cookies,
            accept: accept,
            requestContext: requestContext,
            includeWHAMHeaders: includeWHAMHeaders
        )
        do {
            return try JSONSerialization.jsonObject(with: data)
        } catch {
            logStore.append(level: .warning, category: "codex", message: "WHAM endpoint returned non-JSON or unexpected body: \(preview(of: data))")
            throw error
        }
    }

    private func resolveRequestContext(session: CodexSessionState) async throws -> CodexRequestContext {
        let payload = try await fetchJSON(url: authSessionURL, cookies: session.cookies)
        guard let bearerToken = findString(in: payload, candidateKeys: ["accessToken", "access_token"]) else {
            throw CodexProviderError.missingAccessToken
        }

        let deviceID = session.cookies.first(where: { $0.name == "oai-did" })?.value
            ?? session.localStorage.first(where: { $0.key == "oai-did" })?.value

        return CodexRequestContext(bearerToken: bearerToken, deviceID: deviceID)
    }

    private func executeRequest(
        url: URL,
        cookies: [StoredCookie],
        accept: String,
        requestContext: CodexRequestContext?,
        includeWHAMHeaders: Bool
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 60
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue("https://chatgpt.com", forHTTPHeaderField: "Origin")
        request.setValue("https://chatgpt.com/codex/settings/usage", forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/146.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue(cookieHeader(from: cookies), forHTTPHeaderField: "Cookie")
        request.setValue(Locale.preferredLanguages.first ?? "en-US", forHTTPHeaderField: "OAI-Language")
        request.setValue("1", forHTTPHeaderField: "DNT")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")

        if let requestContext {
            request.setValue("Bearer \(requestContext.bearerToken)", forHTTPHeaderField: "Authorization")
            if let deviceID = requestContext.deviceID {
                request.setValue(deviceID, forHTTPHeaderField: "OAI-Device-Id")
            }
        }

        if includeWHAMHeaders {
            request.setValue("/backend-api/wham/usage", forHTTPHeaderField: "X-OpenAI-Target-Path")
            request.setValue("/backend-api/wham/usage", forHTTPHeaderField: "X-OpenAI-Target-Route")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        logStore.append(category: "codex", message: "HTTP \(status) for \(url.absoluteString) | preview=\(preview(of: data))")
        try validate(response: response, data: data)
        return data
    }

    private func cookieHeader(from cookies: [StoredCookie]) -> String {
        cookies
            .map { "\($0.name)=\($0.value)" }
            .joined(separator: "; ")
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CodexProviderError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw CodexProviderError.sessionExpired(body)
            }
            throw CodexProviderError.httpFailure(httpResponse.statusCode, body)
        }
    }

    private func preview(of data: Data) -> String {
        let text = String(data: data.prefix(320), encoding: .utf8) ?? "<non-utf8>"
        return text.replacingOccurrences(of: "\n", with: " ")
    }

    private func findString(in payload: Any, candidateKeys: [String]) -> String? {
        if let dictionary = payload as? [String: Any] {
            for key in candidateKeys {
                if let value = dictionary[key] as? String, value.isEmpty == false {
                    return value
                }
            }

            for value in dictionary.values {
                if let nested = findString(in: value, candidateKeys: candidateKeys) {
                    return nested
                }
            }
        }

        if let array = payload as? [Any] {
            for value in array {
                if let nested = findString(in: value, candidateKeys: candidateKeys) {
                    return nested
                }
            }
        }

        return nil
    }
}

@MainActor
private final class CodexPageExtractor: NSObject, WKNavigationDelegate {
    struct ExtractionResult {
        let page: Payload
        let usagePayload: Any?
        let session: CodexSessionState
    }

    struct Payload {
        let html: String
        let text: String
        let title: String
    }

    private let url: URL
    private let logStore: LogStore
    private var continuation: CheckedContinuation<Void, Error>?
    private var webView: WKWebView?

    init(url: URL, logStore: LogStore) {
        self.url = url
        self.logStore = logStore
    }

    func extract(session: CodexSessionState) async throws -> ExtractionResult {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()

        let userContentController = WKUserContentController()
        if let bootstrapSource = storageBootstrapScript(localStorage: session.localStorage, sessionStorage: session.sessionStorage) {
            userContentController.addUserScript(WKUserScript(source: bootstrapSource, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        configuration.userContentController = userContentController

        let webView = WKWebView(frame: .zero, configuration: configuration)
        self.webView = webView
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 15_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"

        for cookie in session.cookies.compactMap(\.httpCookie) {
            await withCheckedContinuation { continuation in
                webView.configuration.websiteDataStore.httpCookieStore.setCookie(cookie) {
                    continuation.resume()
                }
            }
        }

        logStore.append(
            category: "codex",
            message: "Loading rendered usage page in WebKit fallback with \(session.localStorage.count) localStorage keys and \(session.sessionStorage.count) sessionStorage keys."
        )
        webView.load(URLRequest(url: url))

        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }

        try await waitForHydration(timeout: .seconds(8))

        let usagePayload = await fetchUsagePayloadViaJavaScript(retryCount: 3)

        let title = await bestEffortJavaScriptString(
            primary: "document.title || ''",
            fallback: "''",
            context: "title extraction"
        )
        let text = await bestEffortJavaScriptString(
            primary: deepTextExtractionScript,
            fallback: "document.body ? (document.body.innerText || '') : (document.documentElement ? (document.documentElement.innerText || '') : '')",
            context: "text extraction"
        )
        let html = await bestEffortJavaScriptString(
            primary: deepHTMLExtractionScript,
            fallback: "document.documentElement ? document.documentElement.outerHTML : ''",
            context: "deep HTML extraction"
        )
        let capturedSession = await captureSession()

        logStore.append(category: "codex", message: "WebKit fallback captured title=\(title), textLength=\(text.count), htmlLength=\(html.count), textPreview=\(String(text.prefix(200)).replacingOccurrences(of: "\n", with: " "))")

        if text.localizedCaseInsensitiveContains("log in") || title.localizedCaseInsensitiveContains("login") {
            throw CodexProviderError.sessionExpired("")
        }

        return ExtractionResult(page: Payload(html: html, text: text, title: title), usagePayload: usagePayload, session: capturedSession)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        continuation?.resume()
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }

    private func javaScriptString(_ source: String) async throws -> String {
        guard let webView else {
            throw CodexProviderError.invalidResponse
        }

        return try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(source) { value, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                continuation.resume(returning: value as? String ?? "")
            }
        }
    }

    private func bestEffortJavaScriptString(primary: String, fallback: String, context: String) async -> String {
        do {
            return try await javaScriptString(primary)
        } catch {
            logStore.append(level: .warning, category: "codex", message: "\(context) failed, retrying with simpler DOM snapshot. Error: \(error.localizedDescription)")
            do {
                return try await javaScriptString(fallback)
            } catch {
                logStore.append(level: .warning, category: "codex", message: "\(context) fallback also failed. Error: \(error.localizedDescription)")
                return ""
            }
        }
    }

    private func fetchUsagePayloadViaJavaScript(retryCount: Int) async -> Any? {
        for attempt in 1...retryCount {
            if let payload = await fetchUsagePayloadAttempt(attempt: attempt) {
                return payload
            }

            if attempt < retryCount {
                try? await Task.sleep(for: .milliseconds(500))
            }
        }

        return nil
    }

    private func waitForHydration(timeout: Duration) async throws {
        let timeoutNanoseconds = timeout.components.seconds * 1_000_000_000 + Int64(timeout.components.attoseconds / 1_000_000_000)
        let stepNanoseconds: Int64 = 500_000_000
        let attempts = max(1, Int(timeoutNanoseconds / stepNanoseconds))

        for attempt in 1...attempts {
            let signal = (try? await javaScriptString(hydrationSignalScript)) ?? "0|0|loading"
            let parts = signal.split(separator: "|", omittingEmptySubsequences: false)
            let textLength = Int(parts.first ?? "0") ?? 0
            let htmlLength = Int(parts.dropFirst().first ?? "0") ?? 0
            let readyState = parts.count > 2 ? String(parts[2]) : "loading"

            if textLength > 0 || (readyState == "complete" && htmlLength > 5_000) {
                logStore.append(category: "codex", message: "Hydration probe succeeded on attempt \(attempt): readyState=\(readyState), textLength=\(textLength), htmlLength=\(htmlLength)")
                return
            }

            if attempt < attempts {
                try await Task.sleep(nanoseconds: UInt64(stepNanoseconds))
            }
        }

        logStore.append(level: .warning, category: "codex", message: "Hydration probe timed out without rendered text; continuing with deepest available DOM snapshot.")
    }

    private func fetchUsagePayloadAttempt(attempt: Int) async -> Any? {
        let payload: String
        do {
            payload = try await javaScriptString("""
            (function() {
                const parseSessionToken = (body) => {
                    try {
                        const payload = JSON.parse(body || '{}');
                        if (payload && typeof payload === 'object') {
                            if (typeof payload.accessToken === 'string' && payload.accessToken) return payload.accessToken;
                            if (typeof payload.access_token === 'string' && payload.access_token) return payload.access_token;
                        }
                    } catch (error) {}
                    return null;
                };

                const readCookie = (name) => {
                    const escaped = name.replace(/[.*+?^${}()|[\\]\\\\]/g, '\\\\$&');
                    const match = document.cookie.match(new RegExp('(?:^|; )' + escaped + '=([^;]*)'));
                    return match ? decodeURIComponent(match[1]) : null;
                };

                try {
                    const authRequest = new XMLHttpRequest();
                    authRequest.open('GET', 'https://chatgpt.com/api/auth/session', false);
                    authRequest.withCredentials = true;
                    authRequest.setRequestHeader('Accept', 'application/json');
                    authRequest.send(null);

                    const accessToken = authRequest.status >= 200 && authRequest.status < 300
                        ? parseSessionToken(authRequest.responseText || '')
                        : null;

                    const request = new XMLHttpRequest();
                    request.open('GET', 'https://chatgpt.com/backend-api/wham/usage', false);
                    request.withCredentials = true;
                    request.setRequestHeader('Accept', 'application/json');
                    if (accessToken) {
                        request.setRequestHeader('Authorization', 'Bearer ' + accessToken);
                        request.setRequestHeader('X-OpenAI-Target-Path', '/backend-api/wham/usage');
                        request.setRequestHeader('X-OpenAI-Target-Route', '/backend-api/wham/usage');
                    }
                    const deviceID = readCookie('oai-did');
                    if (deviceID) {
                        request.setRequestHeader('OAI-Device-Id', deviceID);
                    }
                    request.send(null);
                    return JSON.stringify({
                        authStatus: authRequest.status,
                        authTokenFound: Boolean(accessToken),
                        status: request.status,
                        ok: request.status >= 200 && request.status < 300,
                        body: request.responseText || ''
                });
            } catch (error) {
                return JSON.stringify({ status: -1, ok: false, body: String(error) });
            }
        })();
        """)
        } catch {
            logStore.append(level: .warning, category: "codex", message: "WebKit WHAM fetch attempt \(attempt) could not execute in page context. Error: \(error.localizedDescription)")
            return nil
        }

        guard let data = payload.data(using: .utf8),
              let envelope = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            logStore.append(level: .warning, category: "codex", message: "WebKit WHAM fetch returned an unreadable payload envelope.")
            return nil
        }

        let authStatus = (envelope["authStatus"] as? NSNumber)?.intValue ?? -1
        let authTokenFound = envelope["authTokenFound"] as? Bool ?? false
        let status = (envelope["status"] as? NSNumber)?.intValue ?? -1
        let ok = envelope["ok"] as? Bool ?? false
        let body = envelope["body"] as? String ?? ""

        logStore.append(
            category: "codex",
            message: "WebKit fetch('/backend-api/wham/usage') attempt \(attempt) authStatus=\(authStatus) authTokenFound=\(authTokenFound) returned \(status) | preview=\(preview(of: body))"
        )

        guard ok, let bodyData = body.data(using: .utf8) else {
            return nil
        }

        do {
            return try JSONSerialization.jsonObject(with: bodyData)
        } catch {
            logStore.append(level: .warning, category: "codex", message: "WebKit WHAM fetch returned a non-JSON response body.")
            return nil
        }
    }

    private func captureSession() async -> CodexSessionState {
        guard let webView else {
            return CodexSessionState(cookies: [])
        }

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
        let payload = (try? await javaScriptString("""
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
        """)) ?? "{}"

        guard let data = payload.data(using: .utf8),
              let dictionary = try? JSONDecoder().decode([String: String].self, from: data) else {
            return []
        }

        return dictionary
            .sorted { $0.key < $1.key }
            .map { StoredWebStorageItem(key: $0.key, value: $0.value) }
    }

    private func storageBootstrapScript(localStorage: [StoredWebStorageItem], sessionStorage: [StoredWebStorageItem]) -> String? {
        guard localStorage.isEmpty == false || sessionStorage.isEmpty == false else {
            return nil
        }

        let localJSON = storageJSONObjectLiteral(from: localStorage)
        let sessionJSON = storageJSONObjectLiteral(from: sessionStorage)

        return """
        (function() {
            const apply = (storage, values) => {
                try {
                    for (const [key, value] of Object.entries(values)) {
                        storage.setItem(key, value);
                    }
                } catch (error) {
                    void error;
                }
            };

            apply(window.localStorage, \(localJSON));
            apply(window.sessionStorage, \(sessionJSON));
        })();
        """
    }

    private func storageJSONObjectLiteral(from items: [StoredWebStorageItem]) -> String {
        let dictionary = Dictionary(uniqueKeysWithValues: items.map { ($0.key, $0.value) })
        guard let data = try? JSONSerialization.data(withJSONObject: dictionary, options: []),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }

        return string
    }

    private var hydrationSignalScript: String {
        """
        (function() {
            const deepText = (() => {
                const seen = new Set();
                const chunks = [];
                const visit = (node) => {
                    if (!node || seen.has(node)) return;
                    seen.add(node);
                    if (node.nodeType === Node.TEXT_NODE) {
                        const value = (node.textContent || '').trim();
                        if (value) chunks.push(value);
                        return;
                    }
                    if (node.nodeType !== Node.ELEMENT_NODE && node.nodeType !== Node.DOCUMENT_FRAGMENT_NODE && node.nodeType !== Node.DOCUMENT_NODE) return;
                    if (node.shadowRoot) visit(node.shadowRoot);
                    for (const child of node.childNodes || []) visit(child);
                };
                visit(document.documentElement);
                return chunks.join(' ');
            })();
            const html = document.documentElement ? document.documentElement.outerHTML.length : 0;
            return `${deepText.length}|${html}|${document.readyState}`;
        })();
        """
    }

    private var deepTextExtractionScript: String {
        """
        (function() {
            const bodyText = document.body ? (document.body.innerText || '') : '';
            if (bodyText) return bodyText;
            return document.documentElement ? (document.documentElement.innerText || '') : '';
        })();
        """
    }

    private var deepHTMLExtractionScript: String {
        """
        (function() {
            const root = document.documentElement;
            if (!root) return '';

            const chunks = [root.outerHTML || ''];
            const walker = document.createTreeWalker(root, NodeFilter.SHOW_ELEMENT);

            while (walker.nextNode()) {
                const node = walker.currentNode;
                if (node && node.shadowRoot) {
                    try {
                        const host = node.tagName ? node.tagName.toLowerCase() : 'unknown';
                        chunks.push(`<!-- shadow-root:${host} -->${node.shadowRoot.innerHTML || ''}`);
                    } catch (error) {}
                }
            }

            return chunks.join('\n');
        })();
        """
    }

    private func preview(of text: String) -> String {
        String(text.prefix(320)).replacingOccurrences(of: "\n", with: " ")
    }
}

enum CodexProviderError: LocalizedError {
    case invalidResponse
    case incompleteSessionContext
    case missingAccessToken
    case sessionExpired(String)
    case httpFailure(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Codex returned an invalid response."
        case .incompleteSessionContext:
            return "Codex session is missing the ChatGPT web storage context required to read usage. Open Settings > Accounts > Codex and save the session again."
        case .missingAccessToken:
            return "Codex session did not expose the ChatGPT access token needed for usage requests. Open Settings > Accounts > Codex and save the session again."
        case let .sessionExpired(body):
            return body.isEmpty ? "Codex session appears to be signed out or expired." : "Codex session appears to be signed out or expired: \(body)"
        case let .httpFailure(status, body):
            return "Codex request failed with status \(status): \(body)"
        }
    }
}
