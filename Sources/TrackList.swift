import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Список треков плейлиста: выделение, drag-n-drop файлов, перетаскивание порядка.
struct TrackList: View {

    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()

            if let playlist = model.selectedPlaylist {
                if playlist.tracks.isEmpty {
                    emptyState
                } else if model.visibleTracks.isEmpty {
                    noMatchesState
                } else {
                    trackListView(playlist)
                }
            } else {
                VStack {
                    Text("Плейлист не выбран")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        // Приём аудиофайлов, перетащенных из Finder
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleFileDrop(providers)
        }
    }

    // MARK: - Панель над списком

    private var topBar: some View {
        HStack(spacing: 10) {
            if let playlist = model.selectedPlaylist {
                RoundedRectangle(cornerRadius: 3)
                    .fill(playlist.color.swiftUIColor)
                    .frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 1) {
                    Text(playlist.name).font(.headline)
                    Text("Треков: \(playlist.tracks.count)  ·  Длительность: \(playlistDuration(playlist))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if model.selection.count > 0 {
                Text("\(model.selection.count) выделено")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    model.removeSelectedTracks()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Удалить выделенные")
            }

            if model.isFiltering {
                // При активном фильтре показываем, сколько нашлось из скольких.
                Text("найдено \(model.visibleTracks.count) из \(model.selectedPlaylist?.tracks.count ?? 0)")
                    .font(Typography.iconSmall)
                    .foregroundStyle(.secondary)
                    .fixedSize()
                Button {
                    model.clearSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .help("Сбросить поиск")
            } else {
                Text("клик · ⌘+клик · ⇧+клик для диапазона")
                    .font(Typography.meta())
                    .foregroundStyle(.secondary)
            }

            Button {
                model.playFirstTrackOfSelectedPlaylist()
            } label: {
                Image(systemName: "play.fill")
            }
            .buttonStyle(.borderless)
            .help("Запустить первый трек")
            .disabled(model.selectedPlaylist?.tracks.isEmpty ?? true)

            Button {
                addTracks()
            } label: {
                Label("Добавить", systemImage: "plus")
            }
            .disabled(model.selectedPlaylist == nil)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Список

    private func trackListView(_ playlist: Playlist) -> some View {
        List(selection: Binding(
            get: { model.selection.selectedIDs },
            set: { model.selection.setSelectedIDs($0) }
        )) {
            ForEach(model.visibleTracks, id: \.id) { track in
                // Клик/⌘-клик/⇧-клик для выделения отдаём нативному
                // List(selection:) — он уже реализует стандартную для macOS
                // семантику мульти-выбора. Раньше TrackRow поверх вешал свой
                // onTapGesture(count: 1) с ручным чтением NSEvent.modifierFlags,
                // и два независимых обработчика выделения спорили за один и
                // тот же Set<UUID>, из-за чего ⇧-клик после ⌘-клика мог выделить
                // не тот диапазон (anchor уезжал на случайный элемент Set).
                TrackRow(
                    track: track,
                    isCurrent: model.audioEngine.currentTrack?.id == track.id,
                    isSelected: model.selection.isSelected(track.id),
                    playlistColor: playlist.color
                )
                .tag(track.id)
                .opacity(model.draggingTrackIDs.contains(track.id) ? 0.45 : 1)
                .overlay(alignment: .top) {
                    if showsDropLine(above: track.id) {
                        Rectangle()
                            .fill(Palette.accent)
                            .frame(height: 2)
                            .allowsHitTesting(false)
                    }
                }
                .contextMenu {
                    trackContextMenu(track)
                }
                .onDrag {
                    let ids = model.selection.isSelected(track.id) ? Array(model.selection.selectedIDs) : [track.id]
                    model.trackDropTarget = nil
                    model.playlistDropTargetID = nil
                    model.beginDragWatch()
                    model.draggingTrackIDs = ids
                    model.draggingPlaylistID = nil

                    // Провайдеру отдаём сам файл: тогда Finder скопирует трек
                    // целиком, сохранив оригинальное расширение, а не создаст
                    // .textClipping из строки.
                    let provider = NSItemProvider(contentsOf: track.url) ?? NSItemProvider()
                    // Имя файла в Finder: только базовое имя, без расширения. Расширение
                    // Finder добавляет сам по типу файла, поэтому получается Song.mp3,
                    // а не Song.mp3.mp3. Без имени macOS подставляет «MP3Audio».
                    provider.suggestedName = track.url.deletingPathExtension().lastPathComponent
                    // Метка для внутренних перемещений: видна только нашему
                    // процессу и не мешает копированию файла наружу.
                    provider.registerObject("tracks" as NSString, visibility: .ownProcess)
                    return provider
                }
                .onDrop(of: [.plainText, .fileURL],
                        delegate: TrackDropDelegate(
                            targetIndex: playlist.tracks.firstIndex(where: { $0.id == track.id }) ?? 0,
                            targetID: track.id,
                            model: model,
                            enabled: !model.isFiltering))
                .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
            }
            .onDelete { offsets in
                // Индексы относятся к видимому (возможно, отфильтрованному) списку,
                // поэтому в плейлист передаём идентификаторы, а не позиции.
                let visible = model.visibleTracks
                let ids = offsets.compactMap { visible.indices.contains($0) ? visible[$0].id : nil }
                model.removeTracks(ids: ids)
            }
        }
        .listStyle(.inset)
    }

    /// Нужно ли рисовать синюю линию над строкой трека с данным ID.
    private func showsDropLine(above trackID: UUID) -> Bool {
        guard let target: (id: UUID, before: Bool) = model.trackDropTarget else { return false }
        return target.id == trackID && target.before
    }

    /// Отдельное состояние на случай, когда треки есть, но под фильтр не попал ни один.
    /// Молчаливый пустой список выглядел бы как потеря данных.
    private var noMatchesState: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(Typography.display)
                .foregroundStyle(.secondary)
            Text("Ничего не найдено по запросу «\(model.searchText)»")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text("Ищем по названию трека, имени папки и расширению файла. Несколько слов — все должны найтись.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            Button("Сбросить поиск") { model.clearSearch() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "music.note.list")
                .font(Typography.display)
                .foregroundStyle(.secondary)
            Text("В плейлисте пока нет треков")
                .foregroundStyle(.secondary)
            Text("Перетащите аудиофайлы сюда или нажмите «Добавить»")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Добавить треки") { addTracks() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Контекстное меню

    @ViewBuilder
    private func trackContextMenu(_ track: Track) -> some View {
        Button("Воспроизвести") {
            model.play(track: track)
        }

        Button("Показать в Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([track.url])
        }

        Divider()

        Menu("Переместить в плейлист") {
            ForEach(model.playlistsSorted.filter { $0.id != model.selectedPlaylistID }) { pl in
                Button(pl.name) {
                    let ids = model.selection.isSelected(track.id) ? Array(model.selection.selectedIDs) : [track.id]
                    withAnimation(.easeInOut(duration: 0.18)) {
                        model.moveTracksToPlaylist(trackIDs: ids, targetPlaylistID: pl.id)
                    }
                }
            }
        }

        Divider()

        Menu("Изменить цвет") {
            ForEach(Array(RGBAColor.palette.enumerated()), id: \.offset) { item in
                Button {
                    if model.selection.isSelected(track.id) && model.selection.count > 1 {
                        model.setColorForSelected(item.element)
                    } else {
                        model.setTrackColor(item.element, for: track.id)
                    }
                } label: {
                    // Цветной кружок вместо эмодзи: настоящий цвет палитры, а не смайлик.
                    Image(nsImage: Self.colorDotImage(item.element))
                }
            }
            Divider()
            Button("Сбросить цвет") {
                if model.selection.isSelected(track.id) && model.selection.count > 1 {
                    model.setColorForSelected(nil)
                } else {
                    model.setTrackColor(nil, for: track.id)
                }
            }
        }

        Button(track.deleteAfterPlay ? "Не удалять после проигрывания" : "Удалять после проигрывания") {
            if model.selection.isSelected(track.id) && model.selection.count > 1 {
                model.toggleDeleteAfterPlayForSelected()
            } else {
                model.toggleDeleteAfterPlay(for: track.id)
            }
        }

        Button("Сбросить обрезку") {
            model.resetTrim(for: track.id)
        }

        Divider()

        Button("Переместить выше") {
            withAnimation(.easeInOut(duration: 0.18)) {
                model.moveTrackUp(id: track.id)
            }
        }
        Button("Переместить ниже") {
            withAnimation(.easeInOut(duration: 0.18)) {
                model.moveTrackDown(id: track.id)
            }
        }

        Divider()

        Button("Удалить трек", role: .destructive) {
            if model.selection.isSelected(track.id) && model.selection.count > 1 {
                model.removeSelectedTracks()
            } else {
                model.removeTrack(id: track.id)
            }
        }
    }

    // MARK: - Drag and drop файлов

    private func handleFileDrop(_ providers: [NSItemProvider]) -> Bool {
        // Перетаскивание внутри плеера своим обработчиком не занимается: файлы
        // из Finder обрабатываются только когда ничего не тянется.
        guard model.draggingTrackIDs.isEmpty, model.draggingPlaylistID == nil else { return false }

        let fileType = UTType.fileURL.identifier
        let matching = providers.filter { $0.hasItemConformingToTypeIdentifier(fileType) }
        guard !matching.isEmpty else { return false }

        Task {
            var urls: [URL] = []
            for provider in matching {
                if let data = try? await provider.loadItem(forTypeIdentifier: fileType) as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    urls.append(url)
                }
            }

            // Проверку файлов делаем вне главного потока: открытие файла — операция
            // с диском и не должна подвешивать интерфейс.
            let candidates = urls
            let collected = await Task.detached(priority: .userInitiated) { () -> [URL] in
                candidates.filter { AudioFileSupport.canOpen($0) }
            }.value

            if !collected.isEmpty {
                await MainActor.run {
                    model.addTracks(urls: collected)
                }
            }
        }
        return true
    }

    // MARK: - Перетаскивание порядка треков

    /// Кружок цвета для пункта меню (не template, чтобы macOS не сделал его серым).
    static func colorDotImage(_ color: RGBAColor) -> NSImage {
        let image = NSImage(size: NSSize(width: 14, height: 14), flipped: false) { rect in
            NSColor(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha).setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }

    private func addTracks() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.audio, .movie, .mpeg4Movie, .mp3, .wav, .aiff, .mpeg4Audio]
        panel.title = "Выберите аудиофайлы"
        if panel.runModal() == .OK {
            model.addTracks(urls: panel.urls)
        }
    }

    /// Суммарная длительность плейлиста с учётом trim-точек.
    private func playlistDuration(_ playlist: Playlist) -> String {
        let total = playlist.tracks.reduce(0.0) { $0 + $1.effectiveDuration }
        return total.timecode
    }
}

// MARK: - Строка трека

private struct TrackRow: View {

    let track: Track
    let isCurrent: Bool
    let isSelected: Bool
    let playlistColor: RGBAColor

    @EnvironmentObject private var model: AppModel
    @State private var isHovering = false

    private var effectiveColor: RGBAColor {
        track.color ?? playlistColor
    }

    /// Файл трека отсутствует (следит модель, поэтому значок обновляется сразу).
    private var isMissing: Bool {
        model.isMissing(track.id)
    }

    private var recoveryTooltip: String {
        if let status = model.recoveryScheduler.statuses[track.id], let reason = status.reason {
            return "\(track.displayName): \(reason)"
        }
        if isMissing { return "Файл не найден: \(track.path)" }
        return track.path
    }

    private var rowIconName: String {
        if model.recoveryScheduler.searchingTrackID == track.id { return "magnifyingglass" }
        if isMissing { return "exclamationmark.triangle.fill" }
        return isCurrent ? "speaker.wave.2.fill" : "music.note"
    }

    private var rowIconColor: Color {
        if isMissing { return Palette.danger }
        return isCurrent ? effectiveColor.swiftUIColor : Color.secondary
    }

    /// Строка в одну линию.
    ///
    /// Раньше было две строки: имя, а под ним папка и текстовые пометки
    /// «• удалить после проигрывания», «• обрезка». На плейлисте в несколько
    /// сотен треков это вдвое сокращало видимый список, а пометки занимали
    /// место ради информации, которую достаточно показать значком с подсказкой.
    /// Папка переехала в подсказку к строке, пометки — в маленькие значки справа.
    var body: some View {
        HStack(spacing: 8) {
            // Заменённый файл помечаем ©, отсутствующий — предупреждением.
            Group {
                if track.isReplaced && !isMissing && !isCurrent {
                    Text("©")
                        .font(Typography.body(.semibold))
                        .foregroundStyle(Color.secondary)
                        .help("Файл заменён: найден на диске по имени и хэшу. \(track.path)")
                } else {
                    Image(systemName: rowIconName)
                        .font(Typography.iconSmall)
                        .foregroundStyle(rowIconColor)
                        .help(recoveryTooltip)
                }
            }
            .frame(width: 14)

            RoundedRectangle(cornerRadius: 2)
                .fill(effectiveColor.swiftUIColor)
                .frame(width: 3, height: 14)

            Text(track.displayName)
                .font(Typography.body(isCurrent ? .semibold : .regular))
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(2)

            // Исполнитель и альбом — прямо в строке, но приглушённо и с меньшим
            // приоритетом: при узком окне они уступают место названию.
            if let subtitle = track.metadataSubtitle {
                Text(subtitle)
                    .font(Typography.meta())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(0)
            }

            if isMissing {
                Text("файл не найден")
                    .font(Typography.meta())
                    .foregroundStyle(Palette.danger)
                    .layoutPriority(1)
            }

            Spacer(minLength: 6)

            // Пометки: значок вместо текста, смысл — в подсказке.
            if track.hasTrim {
                Image(systemName: "scissors")
                    .font(Typography.badge)
                    .foregroundStyle(Palette.trim)
                    .help(trimTooltip)
            }

            if track.deleteAfterPlay {
                Image(systemName: "trash")
                    .font(Typography.badge)
                    .foregroundStyle(Palette.warning)
                    .help("Удалить после проигрывания")
            }

            Text(track.effectiveDuration.timecode)
                .font(Typography.metaMono)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(minWidth: 38, alignment: .trailing)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(rowBackground)
        )
        .contentShape(Rectangle())
        // Двойной щелчок запускает трек.
        .onTapGesture(count: 2) {
            model.play(track: track)
        }
        // Одиночный клик намеренно не перехватываем своим onTapGesture:
        // выделение (клик / ⌘-клик / ⇧-клик) обрабатывает нативный List(selection:).
        // Если повесить сюда onTapGesture(count: 1), он съест тап раньше List.
        .onHover { isHovering = $0 }
        .help(tooltip)
    }

    private var rowBackground: Color {
        if isSelected {
            return effectiveColor.swiftUIColor.opacity(0.25)
        }
        return isHovering ? Palette.hover : Color.clear
    }

    /// Границы обрезки словами — для подсказки к значку ножниц.
    private var trimTooltip: String {
        let range = track.exportRange
        return "Обрезка: \(range.start.timecode) — \(range.end.timecode)"
    }

    /// Полная подсказка строки: имя файла, папка и теги, если они есть.
    private var tooltip: String {
        var lines = [track.displayName]
        if let artist = track.artist { lines.append("Исполнитель: \(artist)") }
        if let album = track.album { lines.append("Альбом: \(album)") }
        if let year = track.year { lines.append("Год: \(year)") }
        if let genre = track.genre { lines.append("Жанр: \(genre)") }
        lines.append(track.url.deletingLastPathComponent().path)
        return lines.joined(separator: "\n")
    }
}

/// Перестановка треков перетаскиванием: трек вставляется перед строкой, на которую бросили.
struct TrackDropDelegate: DropDelegate {
    let targetIndex: Int
    let targetID: UUID
    let model: AppModel
    /// При активном поиске переставлять треки нельзя: строка стоит на позиции
    /// в отфильтрованном списке, а `moveTracks` ждёт позицию в плейлисте.
    let enabled: Bool

    func validateDrop(info: DropInfo) -> Bool {
        enabled && !model.draggingTrackIDs.isEmpty
    }

    /// Трек вставляется ПЕРЕД строкой, над которой отпущен. Линия рисуется
    /// над строкой — ровно там, где окажется трек.
    func dropEntered(info: DropInfo) {
        showIndicator()
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard enabled else { return DropProposal(operation: .forbidden) }
        showIndicator()
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        if model.trackDropTarget?.id == targetID {
            model.trackDropTarget = nil
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        // Сбрасываем состояние при любом исходе: и при переносе, и при отказе.
        defer { model.endDragging() }
        guard enabled else { return false }
        let ids = model.draggingTrackIDs
        guard !ids.isEmpty, !ids.contains(targetID) else { return false }
        withAnimation(.easeInOut(duration: 0.18)) {
            model.moveTracks(ids: ids, to: targetIndex)
        }
        return true
    }

    private func showIndicator() {
        guard enabled else {
            model.trackDropTarget = nil
            return
        }
        // Перетаскивание уже завершено — линию не показываем. Без этой проверки
        // dropUpdated, приходящий после performDrop при перестройке списка,
        // зажигал бы линию заново.
        guard !model.draggingTrackIDs.isEmpty else {
            model.trackDropTarget = nil
            return
        }
        // Не показываем линию, если строка — сам перетаскиваемый трек: переносить некуда.
        guard !model.draggingTrackIDs.contains(targetID) else {
            model.trackDropTarget = nil
            return
        }
        // Запись только при изменении, чтобы не перерисовывать список на каждом кадре.
        if model.trackDropTarget?.id != targetID || model.trackDropTarget?.before != true {
            model.trackDropTarget = (targetID, true)
        }
    }
}

// MARK: - Поддержка аудиоформатов

/// Проверка форматов вынесена из View: внутри `View` методы неявно привязаны к
/// главному актору, а открытие файла должно выполняться в фоновом потоке.
enum AudioFileSupport {

    /// Расширения, которые macOS умеет декодировать (AVFoundation + системные кодеки).
    static let audioExtensions: Set<String> = [
        "mp3", "wav", "wave", "m4a", "m4b", "m4r", "aac", "adts", "flac",
        "aif", "aiff", "aifc", "caf", "alac", "au", "snd", "mp2", "mp1",
        "ac3", "eac3", "amr", "mp4", "m4v", "mov", "3gp", "3g2", "sd2", "opus"
    ]

    /// Знакомое расширение принимается сразу, незнакомое проверяется открытием файла.
    nonisolated static func canOpen(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if audioExtensions.contains(ext) { return true }
        return AudioEngine.canOpen(url)
    }
}
