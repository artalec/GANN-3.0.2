import XCTest
@testable import GANNPlayer

final class TrackFilterTests: XCTestCase {

    private func track(_ name: String, folder: String = "Music", ext: String = "mp3") -> Track {
        Track(name: name, path: "/Users/test/\(folder)/\(name).\(ext)")
    }

    func testEmptyQueryKeepsEverything() {
        let tracks = [track("Alpha"), track("Beta")]
        XCTAssertEqual(TrackFilter.apply(tracks, query: "").count, 2)
        XCTAssertEqual(TrackFilter.apply(tracks, query: "   ").count, 2)
        XCTAssertTrue(TrackFilter.tokens(from: "  ").isEmpty)
    }

    func testMatchesByNameCaseInsensitive() {
        let tracks = [track("Midnight City"), track("Outro")]
        let result = TrackFilter.apply(tracks, query: "midnight")
        XCTAssertEqual(result.map(\.name), ["Midnight City"])
    }

    func testAllWordsMustMatch() {
        let tracks = [track("Midnight City"), track("Midnight Sun")]
        XCTAssertEqual(TrackFilter.apply(tracks, query: "midnight city").map(\.name), ["Midnight City"])
        XCTAssertTrue(TrackFilter.apply(tracks, query: "midnight jazz").isEmpty)
    }

    func testMatchesByFolder() {
        let tracks = [track("Intro", folder: "Techno"), track("Intro", folder: "Jazz")]
        XCTAssertEqual(TrackFilter.apply(tracks, query: "techno").count, 1)
    }

    func testMatchesByExtension() {
        let tracks = [track("A", ext: "flac"), track("B", ext: "mp3")]
        XCTAssertEqual(TrackFilter.apply(tracks, query: "flac").map(\.name), ["A"])
    }

    /// «ё» приравнивается к «е» — иначе русские запросы половину времени не находят ничего.
    func testYoEqualsYe() {
        let tracks = [track("Ёлка в лесу")]
        XCTAssertEqual(TrackFilter.apply(tracks, query: "елка").count, 1)
        XCTAssertEqual(TrackFilter.apply(tracks, query: "ёлка").count, 1)
    }

    func testPreservesOrder() {
        let tracks = [track("B"), track("A"), track("Bob")]
        XCTAssertEqual(TrackFilter.apply(tracks, query: "b").map(\.name), ["B", "Bob"])
    }

    func testNormalizeFoldsDiacritics() {
        XCTAssertEqual(TrackFilter.normalize("Café"), "cafe")
        XCTAssertEqual(TrackFilter.normalize("ЁЖИК"), "ежик")
    }
}
