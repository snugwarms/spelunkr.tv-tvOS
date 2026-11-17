import XCTest
@testable import SpelunkrCore

final class MediaURLTests: XCTestCase {
    func testArchiveEscapesEachPathComponent() throws {
        let url = try XCTUnwrap(MediaURL.archive(id: "a #+", file: "folder/A 100% + # tape.mp4"))
        XCTAssertEqual(url.absoluteString, "https://archive.org/download/a%20%23%2B/folder/A%20100%25%20%2B%20%23%20tape.mp4")
    }

    func testBroadcastPathsRejectTraversalAndExternalHosts() {
        let base = URL(string: "https://spelunkr.tv/broadcast/")!
        for path in ["../lineup.json", "manifests/../../x.json", "https://elsewhere.test/x.json", "/manifests/x.json", "manifests/x.json?redirect=1"] {
            XCTAssertNil(MediaURL.asset(path: path, base: base))
        }
        XCTAssertEqual(MediaURL.asset(path: "manifests/channel/v18.json", base: base)?.absoluteString,
                       "https://spelunkr.tv/broadcast/manifests/channel/v18.json")
    }

    func testDirectArchiveHostValidationAndEncoding() throws {
        let valid = Data("{\"server\":\"ia800100.us.archive.org\",\"dir\":\"/12/items/tape\"}".utf8)
        let info = try JSONDecoder().decode(ArchiveMetadata.self, from: valid)
        XCTAssertEqual(info.directURL(file: "Tape #1.mp4")?.absoluteString, "https://ia800100.us.archive.org/12/items/tape/Tape%20%231.mp4")
        let invalid = Data("{\"server\":\"archive.org.evil.test\",\"dir\":\"/items/tape\"}".utf8)
        XCTAssertNil(try JSONDecoder().decode(ArchiveMetadata.self, from: invalid).directURL(file: "tape.mp4"))
    }

    func testLineupHidesUnpublishedChannelsAndSortsByDial() throws {
        let data = Data("""
        {"engine":5,"generatedAt":"2026-11-17","channels":[
        {"id":"b","name":"B","dial":8,"versions":[{"v":1,"manifest":"manifests/b/v1.json","epochMs":0}]},
        {"id":"a","name":"A","dial":2,"versions":[{"v":1,"manifest":"manifests/a/v1.json","epochMs":0}]},
        {"id":"debug","name":"DEBUG","dial":3,"debugOnly":true,"versions":[]},
        {"id":"soon","name":"SOON","dial":4,"comingSoon":true,"versions":[]}]}
        """.utf8)
        let lineup = try JSONDecoder().decode(Lineup.self, from: data)
        XCTAssertEqual(lineup.availableChannels.map(\.id), ["a", "b"])
    }
}
