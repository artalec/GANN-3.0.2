import Foundation

/// Поиск по трекам: чистая логика без SwiftUI, чтобы её можно было покрыть тестами.
///
/// Правила:
/// - запрос режется по пробелам, и каждое слово должно найтись (логика «И»);
/// - сравнение не зависит от регистра, диакритики и ширины символов;
/// - «ё» приравнивается к «е», иначе «ёлка» не находится по «елка»;
/// - ищем по названию трека, по имени папки и по расширению файла.
enum TrackFilter {

    /// Приводит строку к виду, в котором сравнение не зависит от регистра и раскладки.
    static func normalize(_ text: String) -> String {
        text
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                     locale: Locale(identifier: "ru_RU"))
            .replacingOccurrences(of: "ё", with: "е")
    }

    /// Разбивает запрос на слова. Пустой запрос даёт пустой массив — это значит «без фильтра».
    static func tokens(from query: String) -> [String] {
        normalize(query)
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
    }

    /// Поле, по которому идёт поиск: название, папка, расширение.
    static func haystack(for track: Track) -> String {
        let folder = track.url.deletingLastPathComponent().lastPathComponent
        let ext = track.url.pathExtension
        return normalize("\(track.name) \(folder) \(ext)")
    }

    /// Подходит ли трек под уже разобранные слова запроса.
    static func matches(_ track: Track, tokens: [String]) -> Bool {
        guard !tokens.isEmpty else { return true }
        let hay = haystack(for: track)
        return tokens.allSatisfy { hay.contains($0) }
    }

    /// Фильтрует список. Пустой запрос возвращает исходный массив без изменений.
    static func apply(_ tracks: [Track], query: String) -> [Track] {
        let words = tokens(from: query)
        guard !words.isEmpty else { return tracks }
        return tracks.filter { matches($0, tokens: words) }
    }
}
