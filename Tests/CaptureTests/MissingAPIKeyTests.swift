import Foundation
import Security
import XCTest
@testable import Capture

final class MissingAPIKeyTests: XCTestCase {
    private func client(readKey: @escaping () throws -> String?) -> OpenRouterClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RejectNetworkProtocol.self]
        return OpenRouterClient(session: URLSession(configuration: configuration), readAPIKey: readKey)
    }

    @MainActor
    func testMissingKeyInChatRequestsSettingsBeforeNetworking() async {
        AppSettings.shared.apiKeyRequired = false
        defer { AppSettings.shared.apiKeyRequired = false }
        do {
            for try await _ in client(readKey: { nil }).stream(ChatRequest(model: "test-model", messages: [])) {}
            XCTFail("Expected a missing-key error")
        } catch OpenRouterError.missingAPIKey {
            XCTAssertTrue(AppSettings.shared.apiKeyRequired)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    @MainActor
    func testWhitespaceKeyInKeyTestRequestsSettingsBeforeNetworking() async {
        AppSettings.shared.apiKeyRequired = false
        defer { AppSettings.shared.apiKeyRequired = false }
        do {
            _ = try await client(readKey: { " \n\t " }).testKey()
            XCTFail("Expected a missing-key error")
        } catch OpenRouterError.missingAPIKey {
            XCTAssertTrue(AppSettings.shared.apiKeyRequired)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    @MainActor
    func testInaccessibleKeyIsNotReportedAsEmpty() async {
        AppSettings.shared.apiKeyRequired = false
        defer { AppSettings.shared.apiKeyRequired = false }
        do {
            for try await _ in client(readKey: { throw Keychain.KeychainError(status: errSecAuthFailed) })
                .stream(ChatRequest(model: "test-model", messages: [])) {}
            XCTFail("Expected a Keychain error")
        } catch let error as Keychain.KeychainError {
            XCTAssertEqual(error.status, errSecAuthFailed)
            XCTAssertFalse(AppSettings.shared.apiKeyRequired)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

private final class RejectNetworkProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        XCTFail("A missing or inaccessible key must not make a network request")
        client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
    }
    override func stopLoading() {}
}
