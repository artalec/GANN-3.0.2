import Foundation
import Combine

/// Планирует поиск замены для пропавших треков: один за раз, с нарастающим интервалом.
///
/// Класс намеренно НЕ помечен @MainActor: AppModel не изолирован на главном акторе,
/// и вызовы из него были бы ошибкой компиляции. Вместо этого все изменения
/// @Published-свойств выполняются на главном потоке через onMain.
///
/// Одновременно идёт не больше одного поиска. Повтор — через 1, 5, 15, 30 минут.
/// Если отпечатка нет, больше не ищем (трек надо перетащить заново).
final class RecoveryScheduler: ObservableObject {

    /// Трек, для которого сейчас идёт поиск (не больше одного).
    @Published private(set) var searchingTrackID: UUID?

    struct Status {
        var attempts: Int = 0
        var nextAt: Date?
        var reason: String?
    }
    @Published private(set) var statuses: [UUID: Status] = [:]

    /// Что показать в индикаторе поиска. nil — поиск не идёт.
    struct SearchProgress: Equatable {
        var trackName: String
        var phase: FileRecovery.Phase
        var scanned: Int
        var elapsed: TimeInterval
        /// Сколько треков ещё ждёт в ручной очереди.
        var remaining: Int
    }

    @Published private(set) var progress: SearchProgress?

    /// Флаг отмены текущего поиска. Новый поиск получает новый токен.
    private var cancelToken: FileRecovery.CancelToken?
    /// Отчёты обход отдаёт часто, поэтому обновления троттлятся до 5 раз в секунду.
    /// Счётчик времени живёт в замыкании потока поиска (см. startSearch), а не здесь:
    /// так к общему состоянию не обращаются из двух потоков сразу.

    /// Данные трека, нужные для поиска.
    struct Candidate {
        let name: String
        let size: Int64?
        let hash: String?
        let path: String
    }

    private let delays: [TimeInterval]
    /// Сколько раз подряд искать автоматически. Дальше поиск только вручную из меню:
    /// полный обход диска каждые 30 минут для забытого файла — лишняя нагрузка.
    private let autoAttemptLimit: Int

    /// Очередь ручных запросов поиска ("Найти пропавшие треки сейчас" ищет все
    /// пропавшие треки, а не только первый попавшийся — но поиск по-прежнему
    /// идёт строго по одному за раз, поэтому остальные ждут своей очереди здесь).
    private var manualQueue: [(id: UUID, candidate: Candidate)] = []

    init(delays: [TimeInterval] = [60, 300, 900, 1800], autoAttemptLimit: Int = 6) {
        self.delays = delays
        self.autoAttemptLimit = autoAttemptLimit
    }

    /// Выполняет работу на главном потоке. Если мы уже на нём — сразу.
    private func onMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
    }

    /// Запускает поиск для первого пропавшего трека, которому пора. Если поиск уже идёт, ничего не делает.
    func schedule(missingIDs: Set<UUID>, tracks: [UUID: Candidate]) {
        onMain { [self] in
            // Пока разбирается ручная очередь (из "Найти пропавшие сейчас"),
            // не вмешиваемся: иначе периодический автопоиск по таймеру может
            // перехватить освободившийся слот и начать искать произвольный
            // трек вместо следующего в очереди пользователя.
            guard searchingTrackID == nil, manualQueue.isEmpty else { return }
            let now = Date()
            for id in missingIDs {
                guard let t = tracks[id] else { continue }
                if (statuses[id]?.attempts ?? 0) >= autoAttemptLimit {
                    if statuses[id]?.nextAt != nil {
                        statuses[id]?.nextAt = nil
                        statuses[id]?.reason = "не найден: автопоиск остановлен, запустите вручную из меню"
                        FileRecovery.log("«\(t.name)»: автопоиск остановлен после \(autoAttemptLimit) попыток")
                    }
                    continue
                }
                if let next = statuses[id]?.nextAt, next > now { continue }
                guard let size = t.size, let hash = t.hash else {
                    if statuses[id]?.reason != "нет отпечатка" {
                        statuses[id] = Status(attempts: 1, nextAt: nil, reason: "нет отпечатка")
                        FileRecovery.log("«\(t.name)»: нет отпечатка — замена невозможна. Перетащите трек заново.")
                    }
                    continue
                }
                startSearch(id: id, name: t.name, size: size, hash: hash, oldPath: t.path)
                return
            }
        }
    }

    /// Запускает поиск для трека немедленно, если сейчас ничего не ищется;
    /// иначе ставит его в очередь — она разбирается сама по мере завершения
    /// текущих поисков (см. pumpManualQueue()).
    func forceSearch(id: UUID, candidate t: Candidate) {
        onMain { [self] in
            guard let size = t.size, let hash = t.hash else {
                statuses[id] = Status(attempts: 1, nextAt: nil, reason: "нет отпечатка")
                FileRecovery.log("«\(t.name)»: нет отпечатка — замена невозможна.")
                return
            }
            guard searchingTrackID == nil else {
                guard !manualQueue.contains(where: { $0.id == id }) else { return }
                manualQueue.append((id, t))
                statuses[id] = Status(attempts: statuses[id]?.attempts ?? 0, nextAt: nil, reason: "в очереди на поиск")
                return
            }
            startSearch(id: id, name: t.name, size: size, hash: hash, oldPath: t.path)
        }
    }

    /// Ставит в очередь поиск для всех переданных треков. Используется пунктом
    /// меню "Найти пропавшие треки сейчас" — раньше он обрабатывал только один
    /// случайный трек из Set и выходил, хотя назывался во множественном числе.
    func forceSearchAll(_ candidates: [UUID: Candidate]) {
        onMain { [self] in
            for (id, candidate) in candidates {
                forceSearch(id: id, candidate: candidate)
            }
        }
    }

    /// Прерывает текущий поиск и очищает ручную очередь.
    ///
    /// Автоматические повторы это не отменяет: они вернутся по своему расписанию.
    /// Сбрасывается именно то, что пользователь запустил вручную и ждёт прямо сейчас.
    func cancelSearch() {
        onMain { [self] in
            guard searchingTrackID != nil || !manualQueue.isEmpty else { return }
            cancelToken?.cancel()
            for (id, _) in manualQueue {
                statuses[id] = Status(attempts: statuses[id]?.attempts ?? 0,
                                      nextAt: nil, reason: "поиск отменён")
            }
            manualQueue.removeAll()
            FileRecovery.log("поиск отменён пользователем")
        }
    }

    /// После завершения текущего поиска запускает следующий из ручной очереди, если он есть.
    private func pumpManualQueue() {
        guard searchingTrackID == nil, !manualQueue.isEmpty else { return }
        let next = manualQueue.removeFirst()
        guard let size = next.candidate.size, let hash = next.candidate.hash else {
            statuses[next.id] = Status(attempts: 1, nextAt: nil, reason: "нет отпечатка")
            pumpManualQueue()
            return
        }
        startSearch(id: next.id, name: next.candidate.name, size: size, hash: hash, oldPath: next.candidate.path)
    }

    /// Вызывается только на главном потоке (из onMain).
    private func startSearch(id: UUID, name: String, size: Int64, hash: String, oldPath: String) {
        searchingTrackID = id
        let attempt = statuses[id]?.attempts ?? 0
        statuses[id] = Status(attempts: attempt + 1, nextAt: nil, reason: "идёт поиск")

        let token = FileRecovery.CancelToken()
        cancelToken = token
        let queuedCount = manualQueue.count

        // Начальное состояние индикатора — до первого отчёта обхода.
        progress = SearchProgress(trackName: name,
                                  phase: .spotlightSize,
                                  scanned: 0,
                                  elapsed: 0,
                                  remaining: queuedCount)

        DispatchQueue.global(qos: .utility).async { [weak self] in
            // Фильтр по времени живёт здесь, а не в методе класса: это состояние
            // принадлежит одному потоку поиска, и трогать его из другого нельзя.
            var lastReport = Date.distantPast
            let found = FileRecovery.find(name: name, size: size, hash: hash, excluding: oldPath,
                                          cancel: token) { update in
                let now = Date()
                guard now.timeIntervalSince(lastReport) > 0.2 else { return }
                lastReport = now
                guard let self else { return }
                self.publishProgress(update, trackName: name, remaining: queuedCount)
            }
            guard let self else { return }
            self.onMain {
                self.searchingTrackID = nil
                self.progress = nil
                self.cancelToken = nil
                if let m = found {
                    self.statuses[id] = Status(attempts: 0, nextAt: nil, reason: "найден: \(m.url.path)")
                    NotificationCenter.default.post(
                        name: .recoveryFoundReplacement, object: nil,
                        userInfo: ["trackID": id, "url": m.url, "fingerprint": m.fingerprint])
                } else {
                    let delay = self.delays[min(attempt, self.delays.count - 1)]
                    let next = Date().addingTimeInterval(delay)
                    self.statuses[id] = Status(
                        attempts: attempt + 1, nextAt: next,
                        reason: "не найден, повтор через \(Self.format(delay))")
                }
                // Если в очереди "Найти пропавшие сейчас" остались треки — берём следующий.
                self.pumpManualQueue()
            }
        }
    }

    /// Пересылает готовый отчёт на главный поток. Частоту отсекает вызывающий код,
    /// поэтому здесь ни замков, ни общего состояния между потоками.
    private func publishProgress(_ update: FileRecovery.Progress,
                                 trackName: String,
                                 remaining: Int) {
        let snapshot = SearchProgress(trackName: trackName,
                                      phase: update.phase,
                                      scanned: update.scanned,
                                      elapsed: update.elapsed,
                                      remaining: remaining)
        onMain { [weak self] in
            self?.progress = snapshot
        }
    }

    static func format(_ seconds: TimeInterval) -> String {
        if seconds < 90 { return "\(Int(seconds)) с" }
        if seconds < 5400 { return "\(Int(seconds / 60)) мин" }
        return "\(Int(seconds / 3600)) ч"
    }
}

extension Notification.Name {
    static let recoveryFoundReplacement = Notification.Name("RecoveryFoundReplacement")
}
