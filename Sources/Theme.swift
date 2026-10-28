import SwiftUI
import AppKit

// MARK: - Типографическая шкала

/// Пять ступеней вместо восьми разнокалиберных размеров.
///
/// До этой шкалы в коде жили 8, 9, 10, 11, 13, 14, 40 и 44 pt, выбранные
/// по месту. Читалось это как набор разных приложений: подпись плейлиста
/// и подпись трека оказывались одного кегля, хотя иерархически это разные вещи.
///
/// Правило: размер выбирается по роли, а не по вкусу.
///   display  — только пустые состояния, крупный символ по центру
///   title    — имя текущего трека, заголовок панели
///   body     — строки списков, названия плейлистов
///   meta     — подписи, счётчики, служебный текст
///   number   — числа и время, всегда моноширинные, чтобы не дёргались
///   icon*    — только для SF Symbols внутри строк
enum Typography {

    static let display = Font.system(size: 40, weight: .regular)

    static func title(_ weight: Font.Weight = .semibold) -> Font {
        .system(size: 15, weight: weight)
    }

    static func body(_ weight: Font.Weight = .regular) -> Font {
        .system(size: 13, weight: weight)
    }

    static func meta(_ weight: Font.Weight = .regular) -> Font {
        .system(size: 11, weight: weight)
    }

    /// Моноширинный вариант meta: битрейт, частота, размер файла.
    static let metaMono = Font.system(size: 11, design: .monospaced)

    /// Числа и таймкоды. Моноширинный, иначе время «прыгает» при смене цифры.
    static let number = Font.system(size: 10, design: .monospaced)

    /// Мелкие пометки-маркеры в строке трека.
    static let badge = Font.system(size: 9)

    /// Иконки внутри строк списка.
    static let iconSmall = Font.system(size: 10)

    /// Совсем мелкие служебные иконки (индикаторы режимов в сайдбаре).
    static let iconTiny = Font.system(size: 8)
}

// MARK: - Семантические цвета

/// Роли вместо литералов.
///
/// Раньше в коде было `Color.red` трижды, `Color.orange` четырежды, `Color.cyan`
/// дважды и `Color.black.opacity(0.18)` в волне. Проблема не в самих цветах,
/// а в том, что они не знали, что означают: в тёмной теме подложка волны
/// и маска обрезки сливались, а «опасность» и «предупреждение» были
/// неразличимы по смыслу, хотя выглядели по-разному.
enum Palette {

    /// Системный акцент: подсветка цели перетаскивания, линия вставки.
    static let accent = Color.accentColor

    /// Ошибка: файл не найден, действие разрушительно.
    static let danger = Color(nsColor: .systemRed)

    /// Предупреждение: идёт переход, трек будет удалён после проигрывания.
    static let warning = Color(nsColor: .systemOrange)

    /// Служебная пометка обрезки (Start/End).
    static let trim = Color(nsColor: .systemTeal)

    // MARK: Волна

    /// Подложка дорожки. Через `primary` с малой прозрачностью, а не чёрный:
    /// в светлой теме чёрная подложка выглядела грязным пятном.
    static let waveformBackground = Color.primary.opacity(0.06)
    /// Часть волны вне обрезанного фрагмента.
    static let waveformOutside = Color.secondary.opacity(0.25)
    /// Ручка маркера Start/End.
    static let handleFill = Color(nsColor: .secondaryLabelColor)
    static let handleLine = Color(nsColor: .tertiaryLabelColor)
    static let handleStroke = Color(nsColor: .separatorColor)

    // MARK: Поверхности

    /// Рамка поля ввода и разделители внутри панелей.
    static let hairline = Color.secondary.opacity(0.25)
    /// Подсветка строки под курсором.
    static let hover = Color.secondary.opacity(0.08)
    /// Плашка цели перетаскивания.
    static let dropTargetFill = Color.accentColor.opacity(0.18)
    /// Фон полосы прогресса восстановления.
    static let warningSurface = Color(nsColor: .systemOrange).opacity(0.12)
    static let warningBorder = Color(nsColor: .systemOrange).opacity(0.35)
}

// MARK: - Цвет трека

extension RGBAColor {
    var swiftUIColor: Color {
        Color(red: red, green: green, blue: blue, opacity: alpha)
    }

    /// Тот же цвет для AppKit: нужен, когда рисуем обложку для Now Playing.
    var nsColor: NSColor {
        NSColor(red: red, green: green, blue: blue, alpha: alpha)
    }
}

// MARK: - Время

extension TimeInterval {
    var timecode: String {
        let total = Int(self)
        let seconds = total % 60
        let minutes = (total / 60) % 60
        let hours = total / 3600
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}
