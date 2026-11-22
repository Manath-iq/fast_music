import XCTest
@testable import FastMusic

final class PolicyTests: XCTestCase {
    func testTokenAndStreamBoundary() {
        for address in ["https://api.music.yandex.net/account/status", "https://storage.mds.yandex.net/file", "https://oauth.yandex.ru/token"] {
            XCTAssertTrue(NetworkPolicy.yandex(URL(string: address)!), address)
        }
        for address in ["http://api.music.yandex.net", "https://yandex.net.evil.com", "https://notyandex.ru", "https://yandex.ru@evil.com", "https://user:pass@yandex.ru", "https://yandex.ru:8443", "file:///etc/passwd"] {
            XCTAssertFalse(NetworkPolicy.yandex(URL(string: address)!), address)
        }
    }

    func testCoverURLDoesNotAllowArbitraryHosts() {
        XCTAssertEqual(ArtworkURL.make("avatars.yandex.net/get-music/abc/%%", size: 240)?.absoluteString, "https://avatars.yandex.net/get-music/abc/240x240")
        XCTAssertNil(ArtworkURL.make("evil.com/get-music/%%", size: 240))
        XCTAssertNil(ArtworkURL.make("https://avatars.yandex.net.evil.com/%%", size: 240))
        XCTAssertNil(ArtworkURL.make(nil, size: 240))
    }

    func testTrackSupportsNumericIDsAndMissingMetadata() throws {
        let track = try XCTUnwrap(Track(json: ["id": 123, "title": "Тест", "durationMs": 197000, "artists": [["name": "Артист"]], "albums": [["id": 456]], "available": false]))
        XCTAssertEqual(track.id, "123")
        XCTAssertEqual(track.fullID, "123:456")
        XCTAssertEqual(track.duration, 197)
        XCTAssertFalse(track.available)
        XCTAssertEqual(track.artist, "Артист")
        XCTAssertNil(Track(json: ["id": 1]))
    }

    func testTimeNeverDisplaysInvalidValues() {
        XCTAssertEqual(clock(197), "3:17")
        XCTAssertEqual(clock(84.8), "1:24")
        XCTAssertEqual(clock(-2), "0:00")
        XCTAssertEqual(clock(.nan), "0:00")
        XCTAssertEqual(clock(.infinity), "0:00")
    }
}
