import Foundation

/// Поиск пропавшего файла трека по всему компьютеру.
///
/// Порядок этапов (от дешёвого к дорогому), каждый следующий запускается только
/// если предыдущий не дал совпадения:
///
/// 1. Spotlight с предикатом **по имени И размеру** — самый точный и быстрый путь:
///    `kMDItemFSSize` отсекает чужие файлы с тем же именем ещё в индексе, поэтому
///    хэш приходится считать в разы реже.
/// 2. Spotlight только по имени — если первый этап ничего не дал (бывает, когда
///    размер в индексе не обновился после правки файла).
/// 3. Привычные папки: Музыка, Загрузки, Документы, Рабочий стол, iCloud Drive.
/// 4. Внешние диски в `/Volumes`.
/// 5. Остальной диск.
///
/// Этапы 3–5 — ручной обход дерева, самый дорогой по времени. Он умеет сообщать
/// прогресс и прерываться по `CancelToken`: раньше обход `/` с лимитом 200 000
/// файлов молотил диск минутами без индикации и без возможности остановить.
///
/// Каждый шаг пишется в `~/Library/Application Support/GANN Player/recovery.log`.
enum FileRecovery {

    struct Match {
        let url: URL
        let fingerprint: FileFingerprint
    }

    /// Флаг отмены. Класс, а не структура: его читает фоновый поток обхода,
    /// а выставляет главный поток по кнопке «Отменить».
    final class CancelToken {
        private let lock = NSLock()
        private var cancelled = false

        var isCancelled: Bool {
            lock.lock()
            defer { lock.unlock() }
            return cancelled
        }

        func cancel() {
            lock.lock()
            cancelled = true
            lock.unlock()
        }
    }

    /// Этап поиска — для индикатора в интерфейсе.
    enum Phase: String {
        case spotlightSize = "поиск в Spotlight по имени и размеру"
        case spotlightName = "поиск в Spotlight по имени"
        case commonFolders = "обход привычных папок"
        case volumes = "обход внешних дисков"
        case wholeDisk = "обход остального диска"

        var title: String { rawValue }
    }

    /// Что показать пользователю во время поиска.
    struct Progress {
        var phase: Phase
        var scanned: Int
        var elapsed: TimeInterval
    }

    /// Файл журнала. Создаётся при первой записи.
    private static var logFile: URL {
        StorageManager.appSupportDirectory().appendingPathComponent("recovery.log")
    }

    static func log(_ message: String) {
        let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(message)\n"
        NSLog("GANN Player recovery: %@", message)
        if let data = line.data(using: .utf8), let handle = try? FileHandle(forWritingTo: logFile) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else if let data = line.data(using: .utf8) {
            try? data.write(to: logFile)
        }
    }

    /// macOS может хранить одно и то же имя в разных Unicode-формах.
    static func normalized(_ s: String) -> String {
        s.precomposedStringWithCanonicalMapping
    }

    /// Системные каталоги проверяются ПО ПРЕФИКСУ пути, а не по вхождению подстроки.
    /// Иначе «/Library/» исключил бы и ~/Library/Mobile Documents (iCloud Drive).
    private static let systemPrefixes = [
        "/System/", "/private/", "/usr/", "/bin/", "/sbin/", "/dev/", "/cores/", "/var/",
        "/Library/", "/Applications/", "/opt/", "/proc/", "/sys/", "/run/"
    ]
    /// Служебные места, которые пропускаем на любом уровне вложенности.
    private static let skippedFragments = [
        "/.Trash/", "/.Trashes/", "/node_modules/", "/.git/", "/Library/Caches/", "/Backups.backupdb/"
    ]

    private static func skipped(_ path: String) -> Bool {
        if systemPrefixes.contains(where: { path.hasPrefix($0) }) { return true }
        return skippedFragments.contains(where: { path.contains($0) })
    }

    // MARK: - Spotlight

    /// Экранирует строку для предиката mdfind: обратная косая черта и кавычка
    /// внутри имени файла иначе ломают разбор запроса.
    static func escapeForPredicate(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// Предикат «имя совпадает И размер совпадает».
    /// `cd` в конце — сравнение без учёта регистра и диакритики.
    static func sizePredicate(name: String, size: Int64) -> String {
        "kMDItemFSName == \"\(escapeForPredicate(name))\"cd && kMDItemFSSize == \(size)"
    }

    /// Предикат «только имя».
    static func namePredicate(name: String) -> String {
        "kMDItemFSName == \"\(escapeForPredicate(name))\"cd"
    }

    /// Запускает `mdfind` с готовым предикатом и возвращает найденные пути.
    /// Если Spotlight недоступен (индекс выключен, mdfind упал) — пустой массив,
    /// и вызывающий код спокойно переходит к ручному обходу.
    static func spotlight(predicate: String) -> [URL] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        p.arguments = [predicate]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do {
            try p.run()
        } catch {
            log("mdfind: \(error.localizedDescription)")
            return []
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        if p.terminationStatus != 0 {
            log("mdfind: код завершения \(p.terminationStatus)")
            return []
        }
        return String(decoding: data, as: UTF8.self)
            .split(separator: "\n")
            .map { URL(fileURLWithPath: String($0)) }
    }

    // MARK: - Поиск

    /// - Parameter cancel: флаг отмены; проверяется между этапами и внутри обхода.
    /// - Parameter report: вызывается из фонового потока — вызывающий код сам
    ///   решает, как доставить прогресс на главный поток.
    static func find(name: String,
                     size: Int64,
                     hash: String,
                     excluding oldPath: String,
                     cancel: CancelToken? = nil,
                     report: ((Progress) -> Void)? = nil,
                     home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Match? {
        let started = Date()
        let target = normalized(name)
        log("ищу «\(name)» (\(size) байт), старый путь: \(oldPath)")

        func elapsed() -> TimeInterval { Date().timeIntervalSince(started) }
        func stopped() -> Bool { cancel?.isCancelled ?? false }

        // 1. Spotlight: имя + размер. Точнее некуда — тип и размер уже в индексе.
        if !stopped() {
            report?(Progress(phase: .spotlightSize, scanned: 0, elapsed: elapsed()))
            let urls = spotlight(predicate: sizePredicate(name: name, size: size))
            log("Spotlight (имя+размер): кандидатов — \(urls.count)")
            if let m = check(urls, target: target, size: size, hash: hash, excluding: oldPath) {
                return m
            }
        }

        // 2. Spotlight: только имя. Нужен, если размер в индексе устарел.
        if !stopped() {
            report?(Progress(phase: .spotlightName, scanned: 0, elapsed: elapsed()))
            let urls = spotlight(predicate: namePredicate(name: name))
            log("Spotlight (имя): кандидатов — \(urls.count)")
            if let m = check(urls, target: target, size: size, hash: hash, excluding: oldPath) {
                return m
            }
        }

        // 3. Привычные места.
        let common = [
            home.appendingPathComponent("Music"),
            home.appendingPathComponent("Downloads"),
            home.appendingPathComponent("Documents"),
            home.appendingPathComponent("Desktop"),
            home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        ]
        if !stopped() {
            for root in common where FileManager.default.fileExists(atPath: root.path) {
                let cands = walk(root, target: target, limit: 50000,
                                 phase: .commonFolders, elapsed: elapsed,
                                 cancel: cancel, report: report)
                if stopped() { break }
                log("\(root.lastPathComponent): просмотрено \(cands.walked), совпало по имени — \(cands.matches.count)")
                if let m = check(cands.matches, target: target, size: size, hash: hash, excluding: oldPath) {
                    return m
                }
            }
        }

        // 4. Внешние диски.
        if !stopped() {
            let volumes = URL(fileURLWithPath: "/Volumes")
            if let mounted = try? FileManager.default.contentsOfDirectory(at: volumes, includingPropertiesForKeys: nil) {
                for vol in mounted {
                    let cands = walk(vol, target: target, limit: 100000,
                                     phase: .volumes, elapsed: elapsed,
                                     cancel: cancel, report: report)
                    if stopped() { break }
                    log("\(vol.lastPathComponent): просмотрено \(cands.walked), совпало — \(cands.matches.count)")
                    if let m = check(cands.matches, target: target, size: size, hash: hash, excluding: oldPath) {
                        return m
                    }
                }
            }
        }

        // 5. Остальной диск (редко, но бывает: /Users/Shared, другие пользователи).
        if !stopped() {
            let rest = walk(URL(fileURLWithPath: "/"), target: target, limit: 200000,
                            phase: .wholeDisk, elapsed: elapsed,
                            cancel: cancel, report: report)
            log("остальной диск: просмотрено \(rest.walked), совпало — \(rest.matches.count)")
            if let m = check(rest.matches, target: target, size: size, hash: hash, excluding: oldPath) {
                return m
            }
        }

        if stopped() {
            log("поиск отменён через \(String(format: "%.1f", elapsed())) с")
            return nil
        }
        log("поиск завершён за \(String(format: "%.1f", elapsed())) с, совпадений по хэшу нет")
        return nil
    }

    /// Обходит дерево и собирает файлы с нужным именем. Останавливается по лимиту
    /// или по флагу отмены. Прогресс отдаёт не чаще, чем раз в 500 просмотренных
    /// файлов, чтобы не заваливать главный поток.
    private static func walk(_ root: URL,
                             target: String,
                             limit: Int,
                             phase: Phase,
                             elapsed: @escaping () -> TimeInterval,
                             cancel: CancelToken?,
                             report: ((Progress) -> Void)?) -> (matches: [URL], walked: Int) {
        var matches: [URL] = []
        var walked = 0
        guard let en = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isSymbolicLinkKey],
            options: [.skipsPackageDescendants]
        ) else { return ([], 0) }

        for case let url as URL in en {
            if walked >= limit { break }
            if walked % 500 == 0 {
                if cancel?.isCancelled == true { break }
                report?(Progress(phase: phase, scanned: walked, elapsed: elapsed()))
            }
            if skipped(url.path) { en.skipDescendants(); continue }
            if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true { continue }
            walked += 1
            if normalized(url.lastPathComponent) == target { matches.append(url) }
        }
        return (matches, walked)
    }

    /// Проверяет кандидатов: имя, размер, SHA-256. Первое полное совпадение — ответ.
    private static func check(_ urls: [URL], target: String, size: Int64, hash: String,
                              excluding oldPath: String) -> Match? {
        for url in urls {
            guard url.path != oldPath, normalized(url.lastPathComponent) == target else { continue }
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let s = attrs[.size] as? NSNumber else { continue }
            guard s.int64Value == size else {
                log("«\(url.path)»: размер другой (\(s.int64Value) ≠ \(size))")
                continue
            }
            guard let fp = FileFingerprint.compute(path: url.path) else {
                log("«\(url.path)»: не удалось прочитать файл")
                continue
            }
            if fp.sha256 == hash {
                log("✓ совпадение по хэшу: \(url.path)")
                return Match(url: url, fingerprint: fp)
            }
            log("«\(url.path)»: размер совпал, хэш другой")
        }
        return nil
    }
}
