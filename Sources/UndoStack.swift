import Foundation

/// Снимок редактируемого состояния для отмены действий.
///
/// Храним именно список плейлистов, а не весь `AppState`: настройки и выбранный
/// плейлист — не то, что пользователь ждёт от ⌘Z, а копия всех плейлистов
/// невелика (структуры, не классы) и снимается за микросекунды.
///
/// Стек ограничен: длинная история не нужна, а память при тысячах треков
/// копилась бы заметно.
struct UndoStack {

    struct Snapshot: Equatable {
        let playlists: [Playlist]
        let selectedPlaylistID: UUID?
        let actionName: String
    }

    private(set) var undoStack: [Snapshot] = []
    private(set) var redoStack: [Snapshot] = []

    let limit: Int

    init(limit: Int = 40) {
        self.limit = max(1, limit)
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    var undoTitle: String? { undoStack.last?.actionName }
    var redoTitle: String? { redoStack.last?.actionName }

    /// Запоминает состояние ПЕРЕД изменением. Новое действие обнуляет redo.
    mutating func record(_ snapshot: Snapshot) {
        undoStack.append(snapshot)
        if undoStack.count > limit {
            undoStack.removeFirst(undoStack.count - limit)
        }
        redoStack.removeAll()
    }

    /// Возвращает состояние, к которому нужно откатиться, и кладёт текущее в redo.
    mutating func undo(current: Snapshot) -> Snapshot? {
        guard let previous = undoStack.popLast() else { return nil }
        redoStack.append(current)
        if redoStack.count > limit {
            redoStack.removeFirst(redoStack.count - limit)
        }
        return previous
    }

    /// Возвращает состояние, к которому нужно вернуться, и кладёт текущее в undo.
    mutating func redo(current: Snapshot) -> Snapshot? {
        guard let next = redoStack.popLast() else { return nil }
        undoStack.append(current)
        if undoStack.count > limit {
            undoStack.removeFirst(undoStack.count - limit)
        }
        return next
    }

    mutating func removeAll() {
        undoStack.removeAll()
        redoStack.removeAll()
    }
}
