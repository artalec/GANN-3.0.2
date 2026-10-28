import Foundation
import AVFoundation

/// Метаданные файла: исполнитель, альбом, год, жанр, номер трека.
///
/// До этого плеер знал только имя файла и длину. Из-за этого нельзя было
/// ни отсортировать, ни сгруппировать, ни показать, кто это поёт, — а в
/// системном «Сейчас играет» на месте исполнителя стояла пустота.
///
/// Читаем через `AVURLAsset` и `commonMetadata`: этот набор одинаков для MP3,
/// M4A, FLAC и WAV, поэтому один код покрывает все форматы, которые умеет
/// открывать движок. Для многократного чтения одного файла (добавление пачки)
/// есть `loadMany` — он создаёт один asset на файл, а не по одному на поле.
enum TrackMetadata {

    /// Значения в том виде, в каком их удобно хранить в `Track`.
    /// Пустые строки нормализуются в nil: пустое поле не должно занимать место
    /// в интерфейсе, а nil в Codable означает «поля нет».
    struct Values: Equatable {
        var artist: String?
        var album: String?
        var title: String?
        var year: Int?
        var genre: String?
        var trackNumber: Int?

        static let empty = Values()

        var isEmpty: Bool {
            artist == nil && album == nil && title == nil && year == nil
                && genre == nil && trackNumber == nil
        }
    }

    // MARK: - Чтение

    /// Собирает метаданные одного файла. Возвращает пустые значения, если
    /// файл недоступен или тегов в нём нет — это не ошибка, а норма для WAV.
    static func load(url: URL) async -> Values {
        let asset = AVURLAsset(url: url)
        guard let items = try? await asset.load(.commonMetadata) else {
            return .empty
        }

        var values = Values()
        for item in items {
            guard let key = item.commonKey else { continue }
            switch key {
            case .commonKeyArtist:
                values.artist = await string(from: item)
            case .commonKeyAlbumName:
                values.album = await string(from: item)
            case .commonKeyTitle:
                values.title = await string(from: item)
            case .commonKeyCreationDate:
                values.year = await year(from: item)
            case .commonKeyType:
                values.genre = await string(from: item)
            default:
                break
            }
        }

        // Номер трека живёт не в commonMetadata, а в формато-специфичных тегах.
        // Ошибку игнорируем: у большинства файлов его просто нет.
        if let number = try? await asset.load(.metadata)
            .first(where: { $0.identifier == .id3MetadataTrackNumber }),
           let raw = try? await number.load(.value) {
            values.trackNumber = parseInt(raw)
        }

        return values
    }

    /// Читает метаданные для пачки файлов, сохраняя порядок входа.
    static func loadMany(urls: [URL]) async -> [URL: Values] {
        var result: [URL: Values] = [:]
        for url in urls {
            result[url] = await load(url: url)
        }
        return result
    }

    // MARK: - Разбор значений

    /// `AVMetadataItem` на macOS отдаёт значение как `Any` (String, NSNumber,
    /// Data). Приводим к строке и обрезаем пробелы; пустое считаем отсутствием.
    private static func string(from item: AVMetadataItem) async -> String? {
        guard let raw = try? await item.load(.stringValue) else { return nil }
        return normalize(raw)
    }

    /// Год может лежать как «2003», «2003-05-01» или числом.
    private static func year(from item: AVMetadataItem) async -> Int? {
        if let raw = try? await item.load(.stringValue), let value = parseInt(raw) {
            return value
        }
        if let raw = try? await item.load(.numberValue) {
            return parseInt(raw)
        }
        return nil
    }

    /// Достаёт первое четырёхзначное число: «2003-05-01» → 2003, «2003» → 2003.
    static func parseInt(_ value: Any) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let text = value as? String { return parseInt(text) }
        return nil
    }

    static func parseInt(_ text: String) -> Int? {
        var digits = ""
        for character in text {
            if character.isNumber {
                digits.append(character)
                if digits.count == 4 { break }
            } else if !digits.isEmpty {
                break
            }
        }
        guard digits.count == 4 || (digits.count <= 3 && !digits.isEmpty) else { return nil }
        return Int(digits)
    }

    /// Обрезает пробелы и переводы строк; пустую строку превращает в nil.
    static func normalize(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }

    // MARK: - Подписи для интерфейса

    /// «Исполнитель — Альбом» для второй строки списка.
    /// Возвращает nil, если показывать нечего.
    static func subtitle(artist: String?, album: String?) -> String? {
        switch (normalize(artist), normalize(album)) {
        case let (artist?, album?): return "\(artist) — \(album)"
        case let (artist?, nil): return artist
        case let (nil, album?): return album
        case (nil, nil): return nil
        }
    }
}
