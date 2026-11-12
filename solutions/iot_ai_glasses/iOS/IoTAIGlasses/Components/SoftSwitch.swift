import SwiftUI

struct SoftSwitch: View {
    @Binding var isOn: Bool
    let label: String

    var body: some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) {
                isOn.toggle()
            }
        } label: {
            Capsule()
                .fill(isOn ? Palette.toggleOn : Palette.toggleOff)
                .frame(width: 43, height: 24)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle()
                        .fill(isOn ? Palette.toggleKnobOn : Palette.toggleKnobOff)
                        .frame(width: 18, height: 18)
                        .padding(3)
                }
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "开启" : "关闭")
        .accessibilityAddTraits(.isToggle)
    }
}
