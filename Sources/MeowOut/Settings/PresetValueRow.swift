import SwiftUI

/// 数值设置行：弹出菜单（预设档位 + 自定义…）。
/// 选「自定义…」时行内展开 文本框 + 步进器；失焦/回车提交，非法输入恢复原值，越界夹取。
struct PresetValueRow: View {
    let title: String
    var description: String? = nil
    @Binding var value: Int
    let preset: ValuePreset
    let unitKey: String
    /// 值为 0 时的特殊标签键（如电池阈值的「关闭」），nil 表示无特殊值
    var zeroLabelKey: String? = nil
    let language: AppState.AppLanguage

    /// 自定义菜单项的占位 tag（所有数值范围均为非负，-1 安全）
    private let customTag = -1

    @State private var isEditingCustom = false
    @State private var customText = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            SettingsRow(title, description: description) {
                Picker("", selection: pickerSelection) {
                    ForEach(preset.menuValues(currentValue: value), id: \.self) { v in
                        Text(formatted(v)).tag(v)
                    }
                    Divider()
                    Text(I18n.localized("settings_value_custom", language: language)).tag(customTag)
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }

            if isEditingCustom {
                SettingsRowDivider()
                HStack(spacing: 8) {
                    Text(I18n.localized("settings_value_custom", language: language))
                        .font(.system(size: 13))
                    Spacer()
                    TextField("", text: $customText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                        .multilineTextAlignment(.trailing)
                        .focused($fieldFocused)
                        .onSubmit(commitCustom)
                        .accessibilityLabel(title)
                    Stepper("", value: customStepperBinding, in: preset.range, step: preset.step)
                        .labelsHidden()
                        .accessibilityLabel(title)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
            }
        }
        .onChange(of: fieldFocused) { _, focused in
            if !focused { commitCustom() }
        }
    }

    private var pickerSelection: Binding<Int> {
        Binding(
            get: { isEditingCustom ? customTag : value },
            set: { newValue in
                if newValue == customTag {
                    customText = "\(value)"
                    isEditingCustom = true
                    fieldFocused = true
                } else {
                    isEditingCustom = false
                    value = newValue
                }
            }
        )
    }

    private var customStepperBinding: Binding<Int> {
        Binding(
            get: { Int(customText) ?? value },
            set: { newValue in
                customText = "\(newValue)"
                value = preset.snapped(newValue)
            }
        )
    }

    private func commitCustom() {
        guard let parsed = Int(customText) else {
            customText = "\(value)" // 非法输入恢复当前值
            return
        }
        value = preset.snapped(parsed)
        customText = "\(value)"
        if preset.isPreset(value) {
            isEditingCustom = false
        }
    }

    private func formatted(_ v: Int) -> String {
        if v == 0, let zeroLabelKey {
            return I18n.localized(zeroLabelKey, language: language)
        }
        return I18n.localizedFormat(unitKey, language: language, Int64(v))
    }
}
