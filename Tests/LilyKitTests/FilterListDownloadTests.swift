import Foundation
import Testing
@testable import LilyKit

/// Serves canned responses so no network is touched.
final class ListServer: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var body = Data()
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var declaredLength: Int?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var headers: [String: String] = [:]
        if let declaredLength = Self.declaredLength { headers["Content-Length"] = "\(declaredLength)" }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: headers)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Suite(.serialized) struct FilterListDownloadTests {
    private func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ListServer.self]
        return URLSession(configuration: config)
    }
    private let url = URL(string: "https://lists.example/easylist.txt")!

    @Test func aListWithinTheLimitIsRead() async throws {
        ListServer.body = Data("||ads.example^\n".utf8); ListServer.status = 200; ListServer.declaredLength = nil
        let data = try await AdBlocker.download(url, with: session(), limit: 1_000)
        #expect(String(data: data, encoding: .utf8) == "||ads.example^\n")
    }

    @Test func aBodyOverTheLimitIsRefusedWhileReading() async throws {
        ListServer.body = Data(repeating: 0x61, count: 5_000); ListServer.status = 200; ListServer.declaredLength = nil
        await #expect(throws: URLError.self) { _ = try await AdBlocker.download(url, with: session(), limit: 1_000) }
    }

    @Test func aDeclaredSizeOverTheLimitIsRefusedBeforeReading() async throws {
        ListServer.body = Data("x".utf8); ListServer.status = 200; ListServer.declaredLength = 50_000_000
        await #expect(throws: URLError.self) { _ = try await AdBlocker.download(url, with: session()) }
    }

    @Test func aBadStatusIsRefused() async throws {
        ListServer.body = Data("nope".utf8); ListServer.status = 404; ListServer.declaredLength = nil
        await #expect(throws: URLError.self) { _ = try await AdBlocker.download(url, with: session(), limit: 1_000) }
    }
}
