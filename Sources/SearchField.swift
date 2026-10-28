import SwiftUI
import AppKit

/// Поле поиска по трекам. Живёт в тулбаре окна.
///
/// Сделано вручную, а не через `.searchable`: нужен явный `@FocusState`, чтобы ⌘F
/// ставил курсор именно сюда, и нужно сообщать модели «идёт ввод текста» — от этого
/// зависит, отдают ли пункты меню Пробел и ⌘A полю ввода или забирают себе.
struct SearchField: View {

    @EnvironmentObject private var model: AppModel
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(Typography.iconSmall)
                .foregroundStyle(.secondary)

            TextField("Поиск", text: $model.searchText)
                .textFieldStyle(.plain)
                .font(Typography.meta())
                .focused($focused)
                .frame(width: 150)
                .onExitCommand { model.clearSearch() }

            if !model.searchText.isEmpty {
                Button {
                    model.clearSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(Typography.iconSmall)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Очистить (Esc)")
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .textBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Palette.hairline, lineWidth: 1)
                )
        )
        .onTapGesture { focused = true }
        // ⌘F: каждый новый запрос фокуса ставит курсор в поле.
        .onChange(of: model.searchFocusRequest) { _, _ in
            focused = true
        }
        // Пока курсор здесь, Пробел и ⌘A принадлежат полю ввода.
        .onChange(of: focused) { _, value in
            model.setTextEditing(value)
        }
        .onDisappear {
            model.setTextEditing(false)
        }
    }
}
