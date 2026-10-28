import XCTest
@testable import GANNPlayer

final class TrackMetadataTests: XCTestCase {

    // MARK: - Разбор чисел

    func testParseIntFromPlainYear() {
        XCTAssertEqual(TrackMetadata.parseInt("2003"), 2003)
    }

    /// Дата в теге часто лежит целиком: «2003-05-01». Год — первые четыре цифры.
    func testParseIntFromFullDate() {
        XCTAssertEqual(TrackMetadata.parseInt("2003-05-01"), 2003)
    }

    func testParseIntFromNSNumber() {
        XCTAssertEqual(TrackMetadata.parseInt(NSNumber(value: 1999)), 1999)
    }

    func testParseIntReturnsNilForText() {
        XCTAssertNil(TrackMetadata.parseInt("без года"))
        XCTAssertNil(TrackMetadata.parseInt(""))
    }

    /// Номер трека в ID3 бывает вида «3/12».
    func testParseTrackNumberWithTotal() {
        XCTAssertEqual(TrackMetadata.parseInt("3/12"), 3)
    }

    // MARK: - Нормализация

    func testNormalizeTrimsAndDropsEmpty() {
        XCTAssertEqual(TrackMetadata.normalize("  Aphex Twin  "), "Aphex Twin")
        XCTAssertNil(TrackMetadata.normalize("   "))
        XCTAssertNil(TrackMetadata.normalize(nil))
        XCTAssertNil(TrackMetadata.normalize("\n\t"))
    }

    // MARK: - Подпись

    func testSubtitleBothParts() {
        XCTAssertEqual(TrackMetadata.subtitle(artist: "Boards", album: "Geogaddi"),
                       "Boards — Geogaddi")
    }

    func testSubtitleSinglePart() {
        XCTAssertEqual(TrackMetadata.subtitle(artist: "Boards", album: nil), "Boards")
        XCTAssertEqual(TrackMetadata.subtitle(artist: nil, album: "Geogaddi"), "Geogaddi")
    }

    func testSubtitleNilWhenNothing() {
        XCTAssertNil(TrackMetadata.subtitle(artist: nil, album: nil))
        XCTAssertNil(TrackMetadata.subtitle(artist: "  ", album: ""))
    }

    // MARK: - Values

    func testEmptyValuesIsEmpty() {
        XCTAssertTrue(TrackMetadata.Values.empty.isEmpty)
    }

    func testValuesWithOneFieldIsNotEmpty() {
        var values = TrackMetadata.Values.empty
        values.artist = "A"
        XCTAssertFalse(values.isEmpty)
    }
}
