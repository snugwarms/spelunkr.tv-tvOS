import XCTest
@testable import SpelunkrCore

final class CommunityServiceTests: XCTestCase {
    func testReadsModeratedCommentsAndSupportedReactions() async throws {
        CommunityMock.handler = { request in
            let parts = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
            let query = Dictionary(uniqueKeysWithValues: parts.queryItems!.map { ($0.name, $0.value ?? "") })
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(query["video_id"], "eq.A # tape")
            XCTAssertEqual(query["and"], "(timestamp_s.gte.0,timestamp_s.lt.600)")
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

    func testCachesTapeWindowAndDoesNotFetchDisabledOverlays() async throws {
        let requests = CommunityRequestCounter()
        CommunityMock.handler = { _ in requests.increment(); return Data("[]".utf8) }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CommunityMock.self]
        let service = CommunityService(session: URLSession(configuration: config), minimumFetchInterval: 0)
        _ = try await service.snapshot(videoID: "tape", position: 901)
        _ = try await service.snapshot(videoID: "tape", position: 910)
        XCTAssertEqual(requests.value, 2, "Repeated reads of the same tape window should use the cache")
        _ = try await service.snapshot(videoID: "other", includeComments: false, includeReactions: false)
        XCTAssertEqual(requests.value, 2)
        _ = try await service.snapshot(videoID: "tape", position: 901, includeReactions: false)
        XCTAssertEqual(requests.value, 3, "A disabled reaction overlay must not request the reactions endpoint")
    }

    func testDenseTapeWindowHasBoundedPagination() async throws {
        let requests = CommunityRequestCounter()
        CommunityMock.handler = { request in
            requests.increment()
            let row = "{\"id\":\"c\",\"timestamp_s\":20,\"text\":\"Tape comment\"}"
            return Data(("[" + Array(repeating: row, count: 1000).joined(separator: ",") + "]").utf8)
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CommunityMock.self]
        let service = CommunityService(session: URLSession(configuration: config), minimumFetchInterval: 0)
        let result = try await service.snapshot(videoID: "tape", includeReactions: false)
        XCTAssertEqual(requests.value, 2)
        XCTAssertEqual(result.comments.count, 2000)
    }
}

private final class CommunityRequestCounter {
    private let lock = NSLock()
    private var count = 0
    func increment() { lock.lock(); count += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
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
