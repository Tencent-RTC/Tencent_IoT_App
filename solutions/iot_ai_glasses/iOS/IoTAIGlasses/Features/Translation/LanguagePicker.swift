import SwiftUI

enum LanguageSide: Hashable {
    case source
    case target
}

struct LanguageAnchorKey: PreferenceKey {
    static let defaultValue: [LanguageSide: Anchor<CGRect>] = [:]

    static func reduce(value: inout [LanguageSide: Anchor<CGRect>], nextValue: () -> [LanguageSide: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

struct LanguageTrigger: View {
    let side: LanguageSide
    let label: String
    let value: Language
    let isOpen: Bool
    var boxed = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if boxed {
                VStack(spacing: 3) {
                    Text(label)
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.textSecondary)
                    Text(value.rawValue)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(isOpen ? PickerPalette.selectedText : Palette.textPrimary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(isOpen ? PickerPalette.selectedBackground : Color(light: 0xF3F3F6, dark: 0x1B1E1A))
                }
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                VStack(spacing: 6) {
                    Text(label)
                        .font(AppFont.caption)
                        .foregroundStyle(Palette.textSecondary)
                    HStack(spacing: 7) {
                        Text(value.rawValue)
                            .font(.system(size: 23, weight: .medium))
                            .tracking(-0.4)
                            .foregroundStyle(Palette.textPrimary)
                        AppIconView(.chevronDown, size: 14)
                            .foregroundStyle(isOpen ? PickerPalette.selectedText : Palette.textSecondary)
                            .rotationEffect(.degrees(isOpen ? 180 : 0))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .padding(.horizontal, 8)
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(isOpen ? PickerPalette.triggerOpen : .clear)
                }
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .buttonStyle(.plain)
        .anchorPreference(key: LanguageAnchorKey.self, value: .bounds) { [side: $0] }
        .accessibilityLabel("\(label)，\(value.rawValue)")
        .accessibilityHint("选择语言")
        .accessibilityValue(isOpen ? "已展开" : "")
    }
}

struct LanguageMenu: View {
    let selection: Language
    let onSelect: (Language) -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        VStack(spacing: 2) {
            ForEach(Language.allCases) { language in
                let selected = language == selection
                Button {
                    onSelect(language)
                } label: {
                    HStack(spacing: 12) {
                        Text(language.rawValue)
                            .font(.system(size: 14, weight: selected ? .medium : .regular))
                        Spacer(minLength: 0)
                        if selected {
                            AppIconView(.check, size: 16)
                        }
                    }
                    .foregroundStyle(selected ? PickerPalette.selectedText : Palette.textPrimary)
                    .padding(.horizontal, 12)
                    .frame(height: 44)
                    .background {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(selected ? PickerPalette.selectedBackground : .clear)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(6)
        .frame(width: 156)
        .background(Palette.surface, in: shape)
        .overlay(shape.strokeBorder(Palette.line, lineWidth: 1))
        .shadow(color: PickerPalette.menuShadow, radius: colorScheme == .dark ? 16 : 14, x: 0, y: colorScheme == .dark ? 12 : 10)
    }
}
