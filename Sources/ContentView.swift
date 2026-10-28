import SwiftUI
import AppKit

/// Главное окно.
///
/// Раскладка:
///   слева  — список плейлистов
///   справа — waveform с маркерами обрезки, панель управления, список треков
struct ContentView: View {

    @EnvironmentObject private var model: AppModel

    var body: some View {
        // NavigationSplitView вместо HSplitView: даёт штатное сворачивание колонки,
        // её перетаскивание, запоминание ширины и кнопку в тулбаре — всё то, что
        // раньше приходилось изображать вручную плавающей кнопкой у края окна.
        NavigationSplitView(columnVisibility: Binding(
            get: { model.isSidebarVisible ? .all : .detailOnly },
            set: { model.isSidebarVisible = ($0 != .detailOnly) }
        )) {
            PlaylistSidebar()
                .navigationSplitViewColumnWidth(min: 210, ideal: 250, max: 340)
        } detail: {
            VStack(spacing: 0) {
                WaveformPanel(engine: model.audioEngine)
                Divider()
                TrackList()
                // Полоса поиска пропавших файлов: видна только когда поиск идёт.
                RecoveryProgressBar()
                Divider()
                TrackInfoBar()
            }
            .frame(minWidth: 620)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    SearchField()
                }
            }
        }
        .frame(minWidth: 880, minHeight: 640)
    }
}

// MARK: - Верхняя часть: информация, waveform, управление

private struct WaveformPanel: View {

    @EnvironmentObject private var model: AppModel
    /// Движок подписан напрямую: курсор меняется 20 раз в секунду, и перерисовывать
    /// из-за него всё окно не нужно.
    @ObservedObject var engine: AudioEngine

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                trackInfo
                Spacer(minLength: 8)
                // Эффекты перехода переехали в отдельное окно настроек (⌘,):
                // здесь остаётся только вход в него.
                SettingsLink {
                    Label("Эффекты", systemImage: "slider.horizontal.3")
                        .font(Typography.meta())
                }
                .controlSize(.small)
                .help("Настройки переходов между треками (⌘,)")
            }

            WaveformView(
                peaks: model.displayedWaveform,
                currentTime: progressTime,
                duration: displayedDuration,
                accent: displayedAccent,
                trimStart: displayedTrimStart,
                trimEnd: displayedTrimEnd,
                onSeek: { time, shouldPlay, crossfade in
                    model.seekDisplayed(to: time, thenPlay: shouldPlay, crossfade: crossfade)
                },
                onTrimChange: { start, end in
                    guard let track = model.displayedTrack else { return }
                    model.setTrim(for: track.id, start: start, end: end)
                }
            )
            .frame(height: 96)

            transportBar
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: Данные для waveform

    private var displayedTrack: Track? { model.displayedTrack }

    private var displayedDuration: TimeInterval {
        displayedTrack?.duration ?? 0
    }

    private var displayedTrimStart: TimeInterval {
        displayedTrack?.trimStart ?? 0
    }

    private var displayedTrimEnd: TimeInterval {
        guard let track = displayedTrack else { return 0 }
        return track.trimEnd ?? track.duration
    }

    private var displayedAccent: RGBAColor {
        displayedTrack.map { model.accentColor(for: $0) } ?? RGBAColor(red: 0.2, green: 0.55, blue: 1.0)
    }

    /// Время для курсора: если играет этот трек — реальное, если это выбранный,
    /// но не играющий трек — сохранённая точка старта, иначе 0.
    private var progressTime: TimeInterval {
        guard let track = displayedTrack else { return 0 }
        if engine.currentTrack?.id == track.id {
            return engine.currentTime
        }
        return model.pendingStart(for: track.id)
    }

    // MARK: Информация о треке

    private var trackInfo: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let track = displayedTrack {
                Text(track.name)
                    .font(Typography.title())
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(engine.currentTrack?.id == track.id
                         ? engine.currentTime.timecode
                         : track.trimStart.timecode)
                    Text("/")
                    Text(track.effectiveDuration.timecode)

                    if engine.isTransitioning {
                        Text("· переход…").foregroundStyle(Palette.warning)
                    }
                    if track.trimStart > 0 || track.trimEnd != nil {
                        Text("· Start \(track.trimStart.timecode)  End \((track.trimEnd ?? track.duration).timecode)")
                            .foregroundStyle(Palette.trim)
                    }
                }
                .font(Typography.metaMono)
                .foregroundStyle(.secondary)
            } else {
                Text("Ничего не выбрано")
                    .font(Typography.title())
                    .foregroundStyle(.secondary)
                Text("Выберите трек в списке")
                    .font(Typography.meta())
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 80, maxWidth: 340, alignment: .leading)
    }

    // MARK: Панель управления и громкость

    /// Нижняя панель: четыре блока делят ширину поровну, разделители фиксированы.
    private var transportBar: some View {
        HStack(spacing: 0) {
            transportButtons
                .frame(maxWidth: .infinity)
            Divider().frame(height: 22)
            playlistModeButtons
                .frame(maxWidth: .infinity)
            Divider().frame(height: 22)
            volumeControl
                .frame(maxWidth: .infinity)
            Divider().frame(height: 22)
            deviceControl
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
    }

    /// Предыдущий / Играть-пауза / Следующий.
    ///
    /// Раньше здесь стояли пять кнопок: play и pause были отдельными, плюс stop.
    /// Это противоречит тому, как ведёт себя любой плеер на macOS: одна кнопка
    /// переключает состояние, а стоп либо не нужен вовсе, либо живёт в меню.
    /// Стоп остался в меню «Воспроизведение» и на Esc.
    private var transportButtons: some View {
        HStack(spacing: 8) {
            Button {
                model.playPrevious()
            } label: {
                Image(systemName: "backward.fill").frame(width: 20)
            }
            .help("Предыдущий трек (⌘←)")

            Button {
                model.togglePlayPause()
            } label: {
                Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 22)
            }
            .help(engine.isPlaying ? "Пауза (Пробел)" : "Воспроизвести (Пробел)")
            // Тумблер всегда доступен: в покое он запускает первый трек.
            .disabled(model.selectedPlaylist?.tracks.isEmpty ?? true)

            Button {
                model.playNext()
            } label: {
                Image(systemName: "forward.fill").frame(width: 20)
            }
            .help("Следующий трек (⌘→)")
        }
        .buttonStyle(.borderless)
    }

    /// Три режима плейлиста: повтор трека, зацикливание плейлиста, автопереход.
    private var playlistModeButtons: some View {
        HStack(spacing: 6) {
            Toggle(isOn: Binding(
                get: { model.state.settings.loopTrackEnabled },
                set: { value in model.updateSettings { $0.loopTrackEnabled = value } }
            )) {
                Image(systemName: "repeat.1")
            }
            .toggleStyle(.button)
            .help("Зациклить текущий трек")

            Toggle(isOn: Binding(
                get: { model.selectedPlaylist?.loopEnabled ?? false },
                set: { model.setLoopPlaylist($0) }
            )) {
                Image(systemName: "repeat")
            }
            .toggleStyle(.button)
            .help("Зациклить плейлист")

            Toggle(isOn: Binding(
                get: { model.selectedPlaylist?.autoplayEnabled ?? false },
                set: { model.setAutoplay($0) }
            )) {
                Image(systemName: "arrow.forward.to.line")
            }
            .toggleStyle(.button)
            .help("Автоматически переходить к следующему треку")
        }
    }

    /// Громкость: иконка, ползунок (растягивается), проценты.
    private var volumeControl: some View {
        HStack(spacing: 6) {
            Image(systemName: volumeIcon)
                .foregroundStyle(.secondary)
                .frame(width: 16)

            Slider(value: Binding(
                get: { model.state.settings.volume },
                set: { model.setVolume($0) }
            ), in: 0...1)
            .controlSize(.small)
            .frame(maxWidth: .infinity)

            Text("\(Int(model.state.settings.volume * 100))%")
                .font(Typography.number)
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .trailing)
        }
        .padding(.horizontal, 8)
    }

    /// Выбор устройства вывода: значок колонки и список стоят вплотную, с небольшим отступом.
    /// Группа центрируется в своём блоке и ширину списка ограничивает, поэтому при изменении
    /// размера окна значок не отходит от списка.
    private var deviceControl: some View {
        HStack(spacing: 4) {
            Image(systemName: "hifispeaker.fill")
                .foregroundStyle(.secondary)
                .frame(width: 14)

            Picker("", selection: Binding(
                get: { model.outputDeviceSelection },
                set: { model.setOutputDevice($0) }
            )) {
                Text("Системное по умолчанию").tag(Optional<String>.none)
                ForEach(model.outputDevices) { device in
                    Text(device.name).tag(Optional(device.uid))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.small)
            .frame(minWidth: 110, maxWidth: 190)
            .help("Устройство, через которое играет плеер")
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 8)
    }

    /// Запускает выделенный трек, иначе возобновляет текущий или запускает первый.
    private func playSelectedOrResume() {
        if let playlist = model.selectedPlaylist, !model.selection.isEmpty,
           let first = model.selection.selectedTracks(from: playlist.tracks).first {
            model.play(track: first)
            return
        }
        if engine.currentTrack != nil {
            engine.resume()
        } else {
            model.playFirstTrackOfSelectedPlaylist()
        }
    }

    private var volumeIcon: String {
        let v = model.state.settings.volume
        if v <= 0.001 { return "speaker.slash.fill" }
        if v < 0.4 { return "speaker.fill" }
        if v < 0.75 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }
}
