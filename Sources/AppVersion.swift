import Foundation

/// Единственный источник версии — `Resources/Info.plist`.
///
/// Сборка копирует этот plist в бандл и подставляет туда номер сборки CI,
/// поэтому здесь ничего не дублируется: значения читаются из бандла.
/// При запуске через `swift run` бандла нет и `Info.plist` недоступен —
/// тогда используется `fallback`, чтобы приложение не показывало пустую версию.
enum AppVersion {

    static let fallbackMarketing = "2.10.0"
    static let fallbackBuild = "1"

    /// Версия для человека: «1.0.0».
    static var marketing: String {
        bundleValue("CFBundleShortVersionString") ?? fallbackMarketing
    }

    /// Номер сборки: в CI это номер запуска, локально — «1».
    static var build: String {
        bundleValue("CFBundleVersion") ?? fallbackBuild
    }

    /// Для панели «О программе»: «1.0.0 (42)».
    static var display: String { "\(marketing) (\(build))" }

    private static func bundleValue(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }
}
