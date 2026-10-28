import SwiftUI

/// Полоса состояния поиска пропавших файлов. Появляется только пока идёт поиск,
/// чтобы не занимать место в остальное время.
///
/// Раньше поиск по всему диску молотил минутами без единого признака жизни:
/// непонятно ни что происходит, ни сколько ждать, ни как остановить.
struct RecoveryProgressBar: View {

    @EnvironmentObject private var model: AppModel

    private var scheduler: RecoveryScheduler { model.recoveryScheduler }

    var body: some View {
        if let progress = scheduler.progress {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
                    .frame(width: 14, height: 14)

                Text(progress.trackName)
                    .font(Typography.meta(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text("· \(progress.phase.title)")
                    .font(Typography.meta())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if progress.scanned > 0 {
                    Text("· просмотрено \(progress.scanned)")
                        .font(Typography.number)
                        .foregroundStyle(.secondary)
                }

                Text("· \(Self.format(progress.elapsed))")
                    .font(Typography.number)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                if progress.remaining > 0 {
                    Text("в очереди: \(progress.remaining)")
                        .font(Typography.number)
                        .foregroundStyle(.secondary)
                }

                Button("Отменить") {
                    scheduler.cancelSearch()
                }
                .controlSize(.small)
                .help("Прервать поиск пропавших файлов")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity)
            .background(Palette.warningSurface)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Palette.warningBorder)
                    .frame(height: 1)
            }
            .transition(.opacity)
        }
    }

    private static func format(_ seconds: TimeInterval) -> String {
        if seconds < 60 { return String(format: "%.0f с", seconds) }
        return String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }
}
