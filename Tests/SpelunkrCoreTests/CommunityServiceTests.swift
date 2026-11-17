import XCTest
@testable import SpelunkrCore

final class CommunityServiceTests: XCTestCase {
    func testReadsModeratedCommentsAndSupportedReactions() async throws {
        CommunityMock.handler = { request in
            let parts = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
            let query = Dictionary(uniqueKeysWithValues: parts.queryItems!.map { ($0.name, $0.value ?? "") })
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(query["video_id"], "eq.A # tape")
            if request.url!.lastPathComponent == "comments" {
                XCTAssertEqual(query["status"], "eq.active")
                return Data("[{\"id\":\"c\",\"video_id\":\"A # tape\",\"timestamp_s\":12,\"text\":\"Great tape\",\"users\":{\"display_name\":\"Viewer\"}}]".utf8)
            }
            return Data("[{\"id\":\"r\",\"video_id\":\"A # tape\",\"timestamp_s\":13,\"emoji\":\"heart\"},{\"id\":\"bad\",\"video_id\":\"A # tape\",\"timestamp_s\":13,\"emoji\":\"unknown\"}]".utf8)
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CommunityMock.self]
        let result = try await CommunityService(session: URLSession(configuration: config)).snapshot(videoID: "A # tape")
        XCTAssertEqual(result.comments.first?.author, "Viewer")
        XCTAssertEqual(result.comments.first?.timestamp_s, 12)
        XCTAssertEqual(result.reactions.count, 1)
        XCTAssertEqual(result.reactions.first?.symbol, "❤️")
    }
}

private final class CommunityMock: URLProtocol {
    static var handler: ((URLRequest) -> Data)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let data = Self.handler!(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
