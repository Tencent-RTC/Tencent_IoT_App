import SwiftUI

struct DeviceView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        TabScreen(spacing: 0) {
            ScreenTitle("我的眼镜")
                .padding(.bottom, 20)
            ProductHero(isConnected: state.isConnected, batteryLevel: state.batteryLevel)

            DeviceRow(title: "设备连接") {
                Button(state.isConnected ? "断开" : "连接") {
                    state.setConnected(!state.isConnected)
                }
                .buttonStyle(SmallOutlineButtonStyle())
                .accessibilityLabel(state.isConnected ? "断开眼镜" : "连接眼镜")
            }
            DeviceRow(title: "眼镜麦克风") {
                Text(state.isConnected ? "就绪" : "等待连接")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textSecondary)
                    .padding(.horizontal, 9)
                    .frame(height: 28)
                    .overlay(Capsule().strokeBorder(Palette.line, lineWidth: 1))
            }
        }
    }
}

private struct DeviceRow<Trailing: View>: View {
    let title: String
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack {
            Text(title)
                .font(AppFont.callout)
                .foregroundStyle(Palette.textPrimary)
            Spacer()
            trailing
        }
        .frame(minHeight: 69)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Palette.line).frame(height: 1)
        }
    }
}

struct SmallOutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        configuration.label
            .font(AppFont.caption)
            .foregroundStyle(Palette.textPrimary)
            .padding(.horizontal, 12)
            .frame(minWidth: 46, minHeight: 36)
            .background(Palette.surfaceRaised, in: shape)
            .overlay(shape.strokeBorder(Palette.line, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
    }
}
