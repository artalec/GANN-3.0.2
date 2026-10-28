import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Application entry point
// ВАЖНО: файл намеренно НЕ называется main.swift. Если положить @main
// в файл с именем main.swift, компилятор трактует модуль как содержащий
// top-level код и падает с ошибкой
// "'main' attribute cannot be used in a module that contains top-level code".

@main
struct GANNPlayerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        WindowGroup("GANN Player") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 900, minHeight: 640)
        }
        .windowToolbarStyle(.unified)

        .commands {
            CommandGroup(replacing: .newItem) {}

            CommandGroup(replacing: .appInfo) {
                Button("О GANN Player") {
                    NSApp.orderFrontStandardAboutPanel(options: [
                        .applicationName: "GANN Player",
                        .applicationVersion: AppVersion.marketing,
                        .version: AppVersion.build
                    ])
                }
            }

            CommandMenu("Воспроизведение") {
                Button("Воспроизвести / пауза") {
                    AppModel.shared.togglePlayPause()
                }
                // Намеренно без .keyboardShortcut(.space, modifiers: []):
                // NSMenu.performKeyEquivalent перехватывает key equivalent без
                // модификаторов раньше, чем событие доходит до первого
                // респондера, — поэтому пробел переставал печататься в текстовых
                // полях (например, при вводе имени плейлиста). Пробел уже
                // полностью обрабатывается локальным NSEvent-монитором ниже
                // (AppDelegate), который корректно пропускает ввод в NSTextView.

                Button("Остановить") {
                    AppModel.shared.audioEngine.fadeOutAndStop(duration: 1.0)
                }
                .keyboardShortcut(".", modifiers: .command)

                Divider()

                Button("Предыдущий трек") {
                    AppModel.shared.playPrevious()
                }
                .keyboardShortcut(.leftArrow, modifiers: .command)

                Button("Следующий трек") {
                    AppModel.shared.playNext()
                }
                .keyboardShortcut(.rightArrow, modifiers: .command)

                Divider()

                Button("Зациклить трек") {
                    AppModel.shared.updateSettings {
                        $0.loopTrackEnabled.toggle()
                    }
                }

                Button("Зациклить плейлист") {
                    let current = AppModel.shared.selectedPlaylist?.loopEnabled ?? false
                    AppModel.shared.setLoopPlaylist(!current)
                }

                Button("Автопереход к следующему") {
                    let current = AppModel.shared.selectedPlaylist?.autoplayEnabled ?? false
                    AppModel.shared.setAutoplay(!current)
                }
            }

            // Отмена и повтор. Штатный механизм SwiftUI здесь не подходит: состояние
            // живёт в одной модели, а не в биндингах полей, поэтому снимки хранит AppModel.
            // Пункты подменяют стандартные ⌘Z/⇧⌘Z только там, где первым ответчиком
            // не является текстовое поле — иначе сломается отмена набора в поиске.
            CommandGroup(replacing: .undoRedo) {
                Button(model.undoTitle.map { "Отменить \($0)" } ?? "Отменить") {
                    if let manager = focusedTextViewUndoManager() {
                        manager.undo()
                    } else {
                        model.performUndo()
                    }
                }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!model.canUndo && focusedTextViewUndoManager() == nil)

                Button(model.redoTitle.map { "Повторить \($0)" } ?? "Повторить") {
                    if let manager = focusedTextViewUndoManager() {
                        manager.redo()
                    } else {
                        model.performRedo()
                    }
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!model.canRedo && focusedTextViewUndoManager() == nil)

                Divider()

                Button("Найти трек") {
                    model.focusSearch()
                }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(model.selectedPlaylist == nil)

                Button("Сбросить поиск") {
                    model.clearSearch()
                }
                .disabled(model.searchText.isEmpty)
            }

            // Меню «Вид» со сворачиванием колонки. У NavigationSplitView есть своя
            // кнопка в тулбаре, но сочетание клавиш и пункт меню тоже нужны:
            // без них toggleSidebar в модели оставался бы мёртвым кодом.
            CommandGroup(after: .sidebar) {
                Button(model.isSidebarVisible ? "Скрыть список плейлистов" : "Показать список плейлистов") {
                    model.toggleSidebar()
                }
                .keyboardShortcut("s", modifiers: [.command, .option])
            }

            CommandMenu("Файл") {
                Button("Экспортировать фрагмент…") {
                    exportFragment()
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(!model.canExportFragment)

                Button("Дочитать метаданные") {
                    model.refreshMetadataForLibrary()
                }

                Divider()

                Button("Показать в Finder") {
                    guard let track = model.displayedTrack else { return }
                    NSWorkspace.shared.activateFileViewerSelecting([track.url])
                }
                .disabled(model.displayedTrack == nil)
            }

            CommandMenu("Выделение") {
                // ⌘A. В текстовом поле это «выделить весь текст», и пункт меню
                // не должен его отбирать — та же причина, что и у Пробела.
                if model.isTextEditing {
                    Button(model.isFiltering ? "Выделить найденные треки" : "Выделить все треки") {
                        model.selectAllVisible()
                    }
                } else {
                    Button(model.isFiltering ? "Выделить найденные треки" : "Выделить все треки") {
                        model.selectAllVisible()
                    }
                    .keyboardShortcut("a", modifiers: .command)
                }

                Button("Снять выделение") {
                    AppModel.shared.selection.clear()
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])

                Divider()

                Button("Найти пропавшие треки сейчас") {
                    // Раньше здесь было: for id in model.missingTrackIDs { forceRecovery(for: id); break }
                    // — обрабатывался только один случайный элемент Set, хотя
                    // пункт меню называется во множественном числе. Теперь
                    // запускается поиск для всех пропавших треков по очереди.
                    model.forceRecoveryForAllMissing()
                }
                // Раньше кнопка блокировалась, пока идёт любой поиск — из-за
                // этого нельзя было поставить остальные пропавшие треки в
                // очередь, пока ищется первый. Теперь forceSearchAll сам
                // умеет ставить в очередь, так что достаточно проверить,
                // что вообще есть что искать.
                .disabled(model.missingTrackIDs.isEmpty)

                Button("Отменить поиск пропавших") {
                    model.recoveryScheduler.cancelSearch()
                }
                .disabled(model.recoveryScheduler.progress == nil)

                Divider()

                Button("Удалить выделенные треки") {
                    AppModel.shared.removeSelectedTracks()
                }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(AppModel.shared.selection.isEmpty)
            }
        }

        // Окно настроек (⌘,). Стоит ПОСЛЕ WindowGroup: при запуске приложение
        // открывает первую сцену в списке, и когда Settings был сверху, вместо
        // плеера открывалось одно окно настроек.
        Settings {
            SettingsView()
                .environmentObject(model)
        }
    }
}

// MARK: - App delegate

/// Диалог сохранения фрагмента и запуск экспорта.
///
/// Панель по умолчанию подставляет имя с границами обрезки: «Название (1-30).m4a».
/// Так несколько фрагментов одного трека не перетирают друг друга.
@MainActor
private func exportFragment() {
    let model = AppModel.shared
    guard let track = model.displayedTrack else { return }

    let panel = NSSavePanel()
    panel.title = "Экспортировать фрагмент"
    panel.nameFieldStringValue = FragmentExporter.suggestedFileName(for: track)
    panel.allowedContentTypes = [.mpeg4Audio]
    panel.canCreateDirectories = true

    guard panel.runModal() == .OK, let url = panel.url else { return }
    model.exportFragment(of: track, to: url)
}

/// Возвращает undo-менеджер активного текстового поля, если курсор сейчас в нём.
/// Нужно, чтобы ⌘Z в поле поиска отменял набор текста, а не удаление трека.
@MainActor
private func focusedTextViewUndoManager() -> UndoManager? {
    guard let textView = NSApp.keyWindow?.firstResponder as? NSTextView else { return nil }
    return textView.undoManager
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var keyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Глобальный перехват клавиш на уровне окна (работает и в macOS 13,
        // в отличие от SwiftUI .onKeyPress, который появился только в macOS 14).
        // Медиа-клавиши и Пункт управления регистрируем после запуска приложения:
        // до этого MPRemoteCommandCenter может не иметь готового соединения с системой.
        AppModel.shared.nowPlaying.activate()

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Не перехватываем ввод в текстовых полях. Проверка вынесена в отдельный
            // метод: полагаться только на `is NSTextView` нельзя — в SwiftUI первым
            // ответчиком бывает NSTextField или хостинг-вью, и тогда Пробел уходил
            // в плеер вместо набора, а Esc останавливал трек вместо выхода из поля.
            if Self.isEditingText(in: event.window) { return event }

            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            switch event.keyCode {
            case 49: // Space — играть/пауза
                guard flags.isEmpty else { return event }
                AppModel.shared.togglePlayPause()
                return nil

            case 53: // Escape — плавное затухание за 1 секунду, затем стоп
                AppModel.shared.audioEngine.fadeOutAndStop(duration: 1.0)
                return nil

            default:
                return event
            }
        }
    }

    /// Идёт ли ввод текста в окне события.
    ///
    /// Локальный монитор получает keyDown раньше первого ответчика, поэтому любое
    /// перехваченное сочетание отнимается у поля ввода. Проверяем несколько форм
    /// текстового ответчика плюс признак из модели, который выставляет поле поиска.
    private static func isEditingText(in window: NSWindow?) -> Bool {
        if AppModel.shared.isTextEditing { return true }

        let responder = window?.firstResponder ?? NSApp.keyWindow?.firstResponder
        guard let responder else { return false }

        if responder is NSTextView { return true }
        if responder is NSTextField { return true }
        if let text = responder as? NSText, text.isFieldEditor { return true }
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppModel.shared.save()
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
