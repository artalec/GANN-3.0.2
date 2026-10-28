import Foundation
import AVFoundation

/// Вырезает обрезанный фрагмент трека в отдельный файл.
///
/// Зачем: обрезка Start/End уже была, но только для прослушивания. Выгрузить
/// результат было нельзя — приходилось идти в Audacity и повторять руками то,
/// что плеер уже знает.
///
/// Про формат. Экспорт идёт в M4A (AAC) через `AVAssetExportPresetAppleM4A`.
/// Это осознанный выбор, а не упрощение:
///
/// - `AVAssetExportPresetPassthrough` копирует без перекодирования, но режет
///   только по границам кадров контейнера. Для MP3 это 26 мс, для AAC — 21 мс,
///   и на слух стык слышен как щелчок. Обрезка «по волне» требует точности
///   лучше этих значений.
/// - AppleM4A перекодирует, зато диапазон соблюдается с точностью до сэмпла.
///   Слышимой деградации при 256 kbps нет, а стык чистый.
///
/// Если когда-нибудь понадобится копирование без перекодирования (например,
/// для архивных FLAC), это отдельный пресет и отдельная честная надпись
/// в интерфейсе о потере точности.
enum FragmentExporter {

    enum Failure: LocalizedError {
        case fileMissing(String)
        case unreadable(String)
        case emptyRange
        case noSession
        case exportFailed(String)
        case cancelled

        var errorDescription: String? {
            switch self {
            case .fileMissing(let path):
                return "Файл не найден: \(path)"
            case .unreadable(let name):
                return "Не удалось прочитать файл «\(name)»"
            case .emptyRange:
                return "Фрагмент пустой: проверьте маркеры Start и End"
            case .noSession:
                return "Не удалось подготовить экспорт для этого файла"
            case .exportFailed(let reason):
                return "Экспорт не удался: \(reason)"
            case .cancelled:
                return "Экспорт отменён"
            }
        }
    }

    /// Результат успешного экспорта.
    struct Result {
        let url: URL
        let duration: TimeInterval
    }

    /// - Parameters:
    ///   - track: источник; границы берутся из `track.exportRange`.
    ///   - destination: куда писать. Файл не должен существовать.
    ///   - progress: вызывается на произвольном потоке, значения 0…1.
    static func export(track: Track,
                       to destination: URL,
                       progress: ((Double) -> Void)? = nil) async throws -> Result {

        guard FileManager.default.fileExists(atPath: track.path) else {
            throw Failure.fileMissing(track.path)
        }

        let range = track.exportRange
        guard range.end - range.start > 0.05 else {
            throw Failure.emptyRange
        }

        let asset = AVURLAsset(url: track.url)
        guard let session = AVAssetExportSession(asset: asset,
                                                 presetName: AVAssetExportPresetAppleM4A) else {
            throw Failure.noSession
        }

        session.outputURL = destination
        session.outputFileType = .m4a
        session.timeRange = CMTimeRange(
            start: CMTime(seconds: range.start, preferredTimescale: 600),
            duration: CMTime(seconds: range.end - range.start, preferredTimescale: 600)
        )
        // Метаданные исходника переносим, иначе у вырезанного фрагмента
        // не останется ни исполнителя, ни альбома — а плеер их уже умеет читать.
        session.metadata = (try? await asset.load(.commonMetadata)) ?? []

        do {
            try await exportAsync(session, progress: progress)
        } catch let failure as Failure {
            // Отмена и пустой диапазон должны дойти до интерфейса своим текстом,
            // а не превратиться в «экспорт не удался: отменено».
            throw failure
        } catch is CancellationError {
            try? FileManager.default.removeItem(at: destination)
            throw Failure.cancelled
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw Failure.exportFailed(error.localizedDescription)
        }

        progress?(1.0)
        return Result(url: destination, duration: range.end - range.start)
    }

    /// Запускает экспорт и ждёт завершения, опрашивая статус сессии.
    ///
    /// Continuation здесь не нужен и только мешает: у `AVAssetExportSession`
    /// статус — публичное свойство, поэтому цикл с `Task.checkCancellation()`
    /// даёт и ожидание, и отмену, и не оставляет висящих задач.
    private static func exportAsync(_ session: AVAssetExportSession,
                                    progress: ((Double) -> Void)?) async throws {
        session.exportAsynchronously {}

        while true {
            // Отмена приходит от вызывающего кода: он держит Task и отменяет его.
            try Task.checkCancellation()

            progress?(Double(session.progress))

            switch session.status {
            case .completed:
                return
            case .cancelled:
                throw Failure.cancelled
            case .failed:
                let reason = session.error?.localizedDescription ?? "неизвестная ошибка"
                throw Failure.exportFailed(reason)
            default:
                try await Task.sleep(nanoseconds: 100_000_000)
            }
        }
    }

    // MARK: - Имя файла

    /// «Название (0-30).m4a» — по имени трека и границам фрагмента.
    ///
    /// Скобки и двоеточие заменяются: Finder их не любит, а имя должно
    /// открываться двойным щелчком без сюрпризов.
    static func suggestedFileName(for track: Track) -> String {
        let range = track.exportRange
        let base = sanitize(track.displayName)
        let suffix = "\(fmt(range.start))-\(fmt(range.end))"
        return "\(base) (\(suffix)).m4a"
    }

    static func sanitize(_ name: String) -> String {
        let bad = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let cleaned = name
            .components(separatedBy: bad)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Фрагмент" : cleaned
    }

    private static func fmt(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d-%02d", total / 60, total % 60)
    }
}
