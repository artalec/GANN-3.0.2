import XCTest
@testable import GANNPlayer

final class TrackTrimTests: XCTestCase {

    func testDefaultTrimIsWholeFile() {
        let track = Track(name: "A", path: "/tmp/a.mp3", duration: 120)
        XCTAssertEqual(track.trimStart, 0)
        XCTAssertNil(track.trimEnd)
        XCTAssertEqual(track.effectiveDuration, 120, accuracy: 0.0001)
    }

    func testEffectiveDurationUsesTrimEnd() {
        var track = Track(name: "A", path: "/tmp/a.mp3", duration: 120)
        track.trimStart = 10
        track.trimEnd = 90
        XCTAssertEqual(track.effectiveDuration, 80, accuracy: 0.0001)
    }

    func testClampKeepsStartBelowEnd() {
        // start заходит за end — обязан отъехать назад.
        let result = Track.clampedTrim(currentStart: 0,
                                       currentEnd: 30,
                                       newStart: 40, newEnd: nil, duration: 120)
        XCTAssertLessThan(result.start, result.end ?? .infinity)
        XCTAssertEqual(result.end ?? -1, 30, accuracy: 0.0001)
        XCTAssertEqual(result.start, 29.9, accuracy: 0.0001)
    }

    func testClampBoundsStartToZero() {
        let result = Track.clampedTrim(currentStart: 0,
                                       currentEnd: nil,
                                       newStart: -50, newEnd: nil, duration: 120)
        XCTAssertEqual(result.start, 0, accuracy: 0.0001)
    }

    func testClampBoundsEndToDuration() {
        let result = Track.clampedTrim(currentStart: 0,
                                       currentEnd: nil,
                                       newStart: nil, newEnd: 500, duration: 120)
        // end за пределом файла прижимается к длительности, а end == duration
        // хранится как nil — это «до конца файла».
        let end = result.end ?? 120
        XCTAssertEqual(end, 120, accuracy: 0.0001)
    }

    func testClampIgnoresNilChanges() {
        let result = Track.clampedTrim(currentStart: 20,
                                       currentEnd: 80,
                                       newStart: nil, newEnd: nil, duration: 120)
        XCTAssertEqual(result.start, 20, accuracy: 0.0001)
        XCTAssertEqual(result.end ?? -1, 80, accuracy: 0.0001)
    }
}
