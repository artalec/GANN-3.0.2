import SwiftUI

/// Окно настроек (⌘,). Сюда переехали эффекты перехода — раньше они занимали
/// верхнюю часть главного окна рядом с волной и отбирали место у плеера.
struct SettingsView: View {

    @EnvironmentObject private var model: AppModel

    var body: some View {
        // Без TabView: вкладка всего одна, и полоса вкладок с крупной иконкой
        // только занимала место. Заголовок окна задаёт сама сцена Settings.
        transitionsTab
            .frame(width: 460, height: 430)
    }

    private var transitionsTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            effectBlock(
                title: "Focus Fade",
                isOn: Binding(
                    get: { model.state.settings.focusFadeEnabled },
                    set: { value in model.updateSettings { $0.focusFadeEnabled = value } }
                ),
                help: "Плавно останавливает воспроизведение при переходе в другую программу и плавно возобновляет его при возвращении к плееру"
            ) {
                sliderRow(label: "время",
                          value: model.state.settings.focusFadeDuration,
                          range: 0.2...10,
                          enabled: model.state.settings.focusFadeEnabled) { value in
                    model.updateSettings { $0.focusFadeDuration = value }
                }
            }

            Divider()

            effectBlock(
                title: "Crossfade",
                isOn: Binding(
                    get: { model.state.settings.crossfadeEnabled },
                    set: { value in model.updateSettings { $0.crossfadeEnabled = value } }
                ),
                help: "Плавный переход между треками"
            ) {
                sliderRow(label: "переход",
                          value: model.state.settings.crossfadeDuration,
                          range: 0.5...15,
                          enabled: model.state.settings.crossfadeEnabled) { value in
                    model.updateSettings { $0.crossfadeDuration = value }
                }
            }

            Divider()

            effectBlock(
                title: "High-cut",
                isOn: Binding(
                    get: { model.state.settings.highCutEnabled },
                    set: { value in model.updateSettings { $0.highCutEnabled = value } }
                ),
                help: "Плавно уводит верхи у играющего трека, затем запускает следующий"
            ) {
                VStack(alignment: .leading, spacing: 3) {
                    sliderRow(label: "эффект",
                              value: model.state.settings.highCutDuration,
                              range: 0.3...10,
                              enabled: model.state.settings.highCutEnabled) { value in
                        model.updateSettings { $0.highCutDuration = value }
                    }

                    sliderRow(label: "пауза",
                              value: model.state.settings.highCutPauseAfter,
                              range: 0...10,
                              enabled: model.state.settings.highCutEnabled) { value in
                        model.updateSettings { $0.highCutPauseAfter = value }
                    }
                }
            }

        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Компоненты

    private func sliderRow(label: String,
                           value: Double,
                           range: ClosedRange<Double>,
                           enabled: Bool,
                           onChange: @escaping (Double) -> Void) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(Typography.meta())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(width: 52, alignment: .leading)

            Slider(value: Binding(get: { value }, set: { onChange($0) }), in: range)
                .frame(width: 180)
                .controlSize(.small)
                .disabled(!enabled)

            Text(String(format: "%.1f", value))
                .font(Typography.number)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(width: 30, alignment: .leading)
        }
    }

    private func effectBlock<Content: View>(title: String,
                                            isOn: Binding<Bool>,
                                            help: String,
                                            @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(title, isOn: isOn)
                .toggleStyle(.switch)
                .controlSize(.small)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .help(help)

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
