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

    func testArchiveMirrorsAreDistinctValidatedAndKeepTheirDirectories() throws {
        let data = Data("""
        {"server":"dn800307.us.archive.org","d1":"dn800307.us.archive.org","d2":"ia600100.us.archive.org","dir":"/0/items/tape",
         "alternate_locations":{"workable":[{"server":"dn711306.ca.archive.org","dir":"/1/items/tape"}],
         "servers":[{"server":"dn711306.ca.archive.org","dir":"/1/items/tape"},{"server":"evil.test","dir":"/items/tape"}]}}
        """.utf8)
        let info = try JSONDecoder().decode(ArchiveMetadata.self, from: data)
        let urls = info.directURLs(file: "Tape #1.mp4")
        XCTAssertEqual(urls.map(\.host), ["dn800307.us.archive.org", "ia600100.us.archive.org", "dn711306.ca.archive.org"])
        XCTAssertEqual(urls[2].absoluteString, "https://dn711306.ca.archive.org/1/items/tape/Tape%20%231.mp4")
        XCTAssertEqual(urls[0].path, "/0/items/tape/Tape #1.mp4")
    }

    func testInvalidFirstMirrorDoesNotHideAValidReplica() throws {
        let data = Data("""
        {"server":"ia800100.us.archive.org","dir":"/12/items/tape","alternate_locations":{"workable":[{"server":"archive.org.evil.test","dir":"/items/tape"}]}}
        """.utf8)
        let info = try JSONDecoder().decode(ArchiveMetadata.self, from: data)
        XCTAssertEqual(info.directURL(file: "tape.mp4")?.host, "ia800100.us.archive.org")
        XCTAssertTrue(info.directURLs(file: "../tape.mp4").isEmpty)
    }

    func testUsesExistingH264TranscodeForTheSameRecording() throws {
        let data = Data("""
        {"files":[
        {"name":"episode-a.avi","format":"Cinepack"},
        {"name":"episode-a-av1.mp4","format":"AV1","original":"episode-a.avi"},
        {"name":"episode-b.mp4","format":"h.264","original":"episode-b.avi"},
        {"name":"episode-a.mp4","format":"h.264","original":"episode-a.avi"}]}
        """.utf8)
        let info = try JSONDecoder().decode(ArchiveMetadata.self, from: data)
        XCTAssertEqual(info.playbackFilename(requested: "episode-a.avi"), "episode-a.mp4")
        XCTAssertEqual(info.playbackFilename(requested: "episode-a-av1.mp4"), "episode-a.mp4")
        XCTAssertEqual(info.playbackFilename(requested: "episode-b.mp4"), "episode-b.mp4")
        XCTAssertNil(info.playbackFilename(requested: "unrelated.avi"))
    }
}
