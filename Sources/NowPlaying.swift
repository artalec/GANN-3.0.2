import Foundation
import MediaPlayer
import AppKit

/// Интеграция с системой: что показывать в «Сейчас играет», в Пункте управления
/// и на экране блокировки, плюс обработка медиа-клавиш.
///
/// До этого класса плеер был невидим для macOS: F8/F9 на клавиатуре ничего
/// не делали, название трека в системе не появлялось, а кнопки в Пункте
/// управления были неактивны. Для приложения категории «музыка» это базовое
/// ожидание, а не украшение.
///
/// Класс намеренно не знает про `AudioEngine` и `AppModel`: он получает готовые
/// значения и дергает переданные замыкания. Так его можно проверить и так
/// он не создаёт цикл ссылок с синглтоном модели.
final class NowPlayingCenter {

    /// Действия, которые приходят снаружи: с клавиатуры, из Пункта управления
    /// или с экрана блокировки.
    struct Handlers {
        var play: () -> Void = {}
        var pause: () -> Void = {}
        var toggle: () -> Void = {}
        var next: () -> Void = {}
        var previous: () -> Void = {}
        var seek: (TimeInterval) -> Void = { _ in }
    }

    var handlers = Handlers()

    /// Последнее отправленное состояние. Нужно, чтобы не переписывать
    /// nowPlayingInfo на каждый тик: система сама двигает время воспроизведения,
    /// пока `playbackRate` равен 1.
    private var lastTrackID: UUID?
    private var lastAccentKey: String?
    private var lastArtwork: MPMediaItemArtwork?
    private var isRegistered = false

    // MARK: - Регистрация команд

    /// Вызывается один раз при старте приложения.
    func activate() {
        guard !isRegistered else { return }
        isRegistered = true

        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { [weak self] _ in
            self?.handlers.play()
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            self?.handlers.pause()
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.handlers.toggle()
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            self?.handlers.next()
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            self?.handlers.previous()
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            self?.handlers.seek(event.positionTime)
            return .success
        }

        // Команды, которых у плеера нет, выключаем явно: иначе система рисует
        // активные кнопки, нажатие на которые ничего не делает.
        //
        // ВАЖНО: ratingCommand, likeCommand, dislikeCommand и bookmarkCommand
        // существуют только в iOS. На macOS этих свойств у MPRemoteCommandCenter
        // нет, и обращение к ним не компилируется.
    }

    // MARK: - Публикация состояния

    /// - Parameters:
    ///   - elapsed: позиция внутри уже обрезанного фрагмента (то, что видит пользователь).
    ///   - duration: эффективная длительность, а не длина файла.
    func update(track: Track?,
                accent: RGBAColor?,
                isPlaying: Bool,
                elapsed: TimeInterval,
                duration: TimeInterval) {

        guard let track else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            MPNowPlayingInfoCenter.default().playbackState = .stopped
            lastTrackID = nil
            return
        }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.displayName,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: max(0, elapsed),
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyIsLiveStream: false
        ]

        // Теги появились в 2.11. Если их нет — соответствующего ключа просто
        // не будет, и система покажет только название, как раньше.
        if let artist = track.artist {
            info[MPMediaItemPropertyArtist] = artist
        }
        if let album = track.album {
            info[MPMediaItemPropertyAlbumTitle] = album
        }
        if let genre = track.genre {
            info[MPMediaItemPropertyGenre] = genre
        }
        if let number = track.trackNumber {
            info[MPMediaItemPropertyAlbumTrackNumber] = number
        }

        if duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }

        // Обложку пересобираем только при смене трека или цвета: рисование
        // NSImage на каждый тик — лишняя работа на главном потоке.
        let accentKey = accent.map { "\($0.red)-\($0.green)-\($0.blue)" } ?? "-"
        if lastTrackID != track.id || lastAccentKey != accentKey {
            lastArtwork = Self.artwork(for: track, accent: accent)
            lastTrackID = track.id
            lastAccentKey = accentKey
        }
        if let lastArtwork {
            info[MPMediaItemPropertyArtwork] = lastArtwork
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
    }

    /// Сброс при остановке: система не должна показывать прошлый трек.
    func clear() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
        lastTrackID = nil
        lastAccentKey = nil
        lastArtwork = nil
    }

    // MARK: - Обложка

    /// Обложка рисуется из цвета трека и первой буквы названия.
    ///
    /// Настоящих обложек нет: метаданные файлов плеер не читает, а брать
    /// иконку приложения на каждый трек бессмысленно. Цветная плашка
    /// с инициалом последовательна и мгновенна — и совпадает с цветом волны.
    static func makeArtworkImage(for track: Track, accent: RGBAColor?) -> NSImage {
        let side: CGFloat = 512
        let size = NSSize(width: side, height: side)

        // drawingHandler вместо lockFocus/unlockFocus: тот вариант объявлен
        // устаревшим, а этот ещё и перерисовывает сам при смене масштаба.
        let image = NSImage(size: size, flipped: false) { rect in
            // База: цвет трека, приглушённый, чтобы белый текст читался.
            let base = (accent?.nsColor ?? NSColor.systemBlue)
                .blended(withFraction: 0.25, of: .black) ?? .systemBlue
            base.setFill()
            rect.fill()

            // Мягкое световое пятно — чтобы плашка не выглядела плоской.
            NSColor.white.withAlphaComponent(0.10).setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: side * 0.16, dy: side * 0.16)).fill()

            // Инициал названия.
            let initial = String(track.name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: side * 0.46, weight: .semibold),
                .foregroundColor: NSColor.white.withAlphaComponent(0.92)
            ]
            let text = NSAttributedString(string: initial.isEmpty ? "♪" : initial,
                                          attributes: attributes)
            let textSize = text.size()
            text.draw(at: NSPoint(x: (side - textSize.width) / 2,
                                  y: (side - textSize.height) / 2))
            return true
        }

        return image
    }

    private static func artwork(for track: Track, accent: RGBAColor?) -> MPMediaItemArtwork {
        let image = makeArtworkImage(for: track, accent: accent)
        return MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }
}
