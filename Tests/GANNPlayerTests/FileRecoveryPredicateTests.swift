import XCTest
@testable import GANNPlayer

/// Проверки чистых функций поиска: сборка предиката и экранирование.
/// Сам обход диска и mdfind не тестируются — им нужна реальная файловая система
/// и индекс Spotlight, а предикат собирается детерминированно.
final class FileRecoveryPredicateTests: XCTestCase {

    func testEscapesBackslashAndQuote() {
        XCTAssertEqual(FileRecovery.escapeForPredicate("a\\b"), "a\\\\b")
        XCTAssertEqual(FileRecovery.escapeForPredicate("say \"hi\""), "say \\\"hi\\\"")
        XCTAssertEqual(FileRecovery.escapeForPredicate("plain.mp3"), "plain.mp3")
    }

    func testSizePredicateContainsBothConditions() {
        let p = FileRecovery.sizePredicate(name: "Track 01.flac", size: 12_345_678)
        XCTAssertTrue(p.contains("kMDItemFSName == "))
        XCTAssertTrue(p.contains("kMDItemFSSize == 12345678"))
        XCTAssertTrue(p.contains("&&"), "имя и размер должны проверяться вместе")
        XCTAssertTrue(p.contains("Track 01.flac"))
        // Сравнение имени без учёта регистра: суффикс cd идёт сразу после значения.
        XCTAssertTrue(p.contains("\"cd"), "ожидался модификатор cd у имени")
    }

    func testNamePredicateHasNoSize() {
        let p = FileRecovery.namePredicate(name: "Song.wav")
        XCTAssertFalse(p.contains("kMDItemFSSize"))
        XCTAssertTrue(p.contains("Song.wav"))
    }

    /// Имя с кавычкой не должно ломать предикат: иначе mdfind вернёт ошибку разбора.
    func testPredicateSurvivesQuoteInName() {
        let p = FileRecovery.sizePredicate(name: "He said \"go\".mp3", size: 1024)
        // Обрамляющие кавычки (2) плюс две экранированные внутри имени.
        let quotes = p.filter { $0 == "\"" }.count
        XCTAssertEqual(quotes, 4, "кавычки внутри имени должны быть экранированы, а не выброшены")
        XCTAssertTrue(p.contains("\\\"go\\\""))
    }

    /// Обратная косая в имени не должна экранировать обрамляющую кавычку предиката.
    func testBackslashIsDoubled() {
        let p = FileRecovery.sizePredicate(name: "a\\", size: 10)
        XCTAssertTrue(p.contains("a\\\\"), "одиночная косая черта ломает предикат")
    }
}
