import XCTest
import UserNotifications
@testable import AiUsageApp

final class UpdateCheckerTests: XCTestCase {
    func testSemanticVersionOrdersStableAndPrereleaseVersions() throws {
        let beta = try XCTUnwrap(SemanticVersion("v1.2.3-beta.2"))
        let releaseCandidate = try XCTUnwrap(SemanticVersion("1.2.3-rc.1"))
        let stable = try XCTUnwrap(SemanticVersion("1.2.3"))
        let nextPatch = try XCTUnwrap(SemanticVersion("1.2.4"))

        XCTAssertLessThan(beta, releaseCandidate)
        XCTAssertLessThan(releaseCandidate, stable)
        XCTAssertLessThan(stable, nextPatch)
    }

    func testSemanticVersionOrdersNumericPrereleaseIdentifiersNumerically() throws {
        let secondBeta = try XCTUnwrap(SemanticVersion("1.0.0-beta.2"))
        let tenthBeta = try XCTUnwrap(SemanticVersion("1.0.0-beta.10"))

        XCTAssertLessThan(secondBeta, tenthBeta)
    }

    func testSemanticVersionIgnoresBuildMetadataForPrecedence() throws {
        let local = try XCTUnwrap(SemanticVersion("1.0.0+local.1"))
        let release = try XCTUnwrap(SemanticVersion("1.0.0+release.2"))

        XCTAssertEqual(local, release)
    }

    func testSemanticVersionRejectsInvalidValues() {
        XCTAssertNil(SemanticVersion("1.2"))
        XCTAssertNil(SemanticVersion("01.2.3"))
        XCTAssertNil(SemanticVersion("1.2.3-beta.01"))
    }

    @MainActor
    func testManualCheckSelectsLatestStableReleaseAndSendsGitHubHeaders() async throws {
        let defaultsSuiteName = "UpdateCheckerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsSuiteName))
        defer {
            defaults.removePersistentDomain(forName: defaultsSuiteName)
            URLProtocolStub.handler = nil
        }

        var capturedRequest: URLRequest?
        URLProtocolStub.handler = { request in
            capturedRequest = request
            let body = Data(
                """
                [
                  {"tag_name":"v2.0.0-beta.1","html_url":"https://github.com/wojtekmaj/ai-usage/releases/tag/v2.0.0-beta.1","prerelease":true,"draft":false},
                  {"tag_name":"v1.1.0","html_url":"https://github.com/wojtekmaj/ai-usage/releases/tag/v1.1.0","prerelease":false,"draft":false},
                  {"tag_name":"v1.0.1","html_url":"https://github.com/wojtekmaj/ai-usage/releases/tag/v1.0.1","prerelease":false,"draft":false}
                ]
                """.utf8
            )
            let response = try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["ETag": "test-etag"]
            ))
            return (response, body)
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        let session = URLSession(configuration: configuration)
        let notificationService = NotificationService(
            usageStore: UsageStore(defaults: defaults),
            logStore: LogStore(defaults: defaults),
            notificationCenter: NotificationCenterClient(
                requestAuthorization: {},
                addRequest: { _ in XCTFail("Manual checks should not send a system notification.") }
            )
        )
        let checker = UpdateChecker(
            currentVersion: "1.0.0",
            notificationService: notificationService,
            session: session,
            defaults: defaults
        )

        await checker.checkManually(localizer: Localizer(language: .englishUS))

        XCTAssertEqual(
            checker.status,
            .available(AppRelease(
                version: "1.1.0",
                pageURL: try XCTUnwrap(URL(string: "https://github.com/wojtekmaj/ai-usage/releases/tag/v1.1.0"))
            ))
        )
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "Accept"), "application/vnd.github+json")
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "User-Agent"), "AI-Usage/1.0.0")

        let restoredChecker = UpdateChecker(
            currentVersion: "1.0.0",
            notificationService: notificationService,
            session: session,
            defaults: defaults
        )
        XCTAssertEqual(restoredChecker.status, checker.status)
        session.invalidateAndCancel()
    }
}

private final class URLProtocolStub: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
