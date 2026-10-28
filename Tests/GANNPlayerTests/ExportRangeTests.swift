import XCTest
@testable import GANNPlayer

final class ExportRangeTests: XCTestCase {

    private func track(duration: TimeInterval,
                       trimStart: TimeInterval = 0,
                       trimEnd: TimeInterval? = nil) -> Track {
        Track(name: "Test", path: "/tmp/test.mp3", duration: duration,
              trimStart: trimStart, trimEnd: trimEnd)
    }

    func testFullFileRangeWithoutTrim() {
        let range = track(duration: 120).exportRange
        XCTAssertEqual(range.start, 0, accuracy: 0.0001)
        XCTAssertEqual(range.end, 120, accuracy: 0.0001)
    }

    func testRangeUsesTrim() {
        let range = track(duration: 120, trimStart: 10, trimEnd: 90).exportRange
        XCTAssertEqual(range.start, 10, accuracy: 0.0001)
        XCTAssertEqual(range.end, 90, accuracy: 0.0001)
    }

    /// trimEnd за пределом файла не должен выводить диапазон за длительность.
    func testRangeClampedToDuration() {
        let range = track(duration: 60, trimStart: 0, trimEnd: 999).exportRange
        XCTAssertEqual(range.end, 60, accuracy: 0.0001)
    }

    func testRangeNeverInverted() {
        // trimStart больше trimEnd — диапазон не должен перевернуться.
        let range = track(duration: 120, trimStart: 100, trimEnd: 30).exportRange
        XCTAssertLessThanOrEqual(range.start, range.end)
    }

    func testRangeRoundsToMilliseconds() {
        let range = track(duration: 120, trimStart: 10.123456789, trimEnd: 90.987654321).exportRange
        XCTAssertEqual(range.start, 10.123, accuracy: 0.0001)
        XCTAssertEqual(range.end, 90.988, accuracy: 0.0001)
    }

    // MARK: - hasTrim

    func testHasTrimFalseForUntouched() {
        XCTAssertFalse(track(duration: 120).hasTrim)
    }

    func testHasTrimTrueForStart() {
        XCTAssertTrue(track(duration: 120, trimStart: 5).hasTrim)
    }

    func testHasTrimTrueForEnd() {
        XCTAssertTrue(track(duration: 120, trimEnd: 100).hasTrim)
    }

    /// Микроскопическое смещение от дрожания мыши не считается обрезкой.
    func testHasTrimIgnoresSubMillisecondNoise() {
        XCTAssertFalse(track(duration: 120, trimStart: 0.0005).hasTrim)
    }

    // MARK: - Имя файла

    func testSuggestedFileNameContainsRange() {
        let name = FragmentExporter.suggestedFileName(
            for: track(duration: 120, trimStart: 65, trimEnd: 95))
        XCTAssertTrue(name.hasSuffix(".m4a"))
        XCTAssertTrue(name.contains("1-05"), "начало 1:05 → 1-05: \(name)")
        XCTAssertTrue(name.contains("1-35"), "конец 1:35 → 1-35: \(name)")
    }

    func testSanitizeRemovesPathCharacters() {
        XCTAssertFalse(FragmentExporter.sanitize("a/b:c").contains("/"))
        XCTAssertFalse(FragmentExporter.sanitize("a/b:c").contains(":"))
    }

    func testSanitizeFallsBackForEmptyName() {
        XCTAssertEqual(FragmentExporter.sanitize("   "), "Фрагмент")
    }
}
