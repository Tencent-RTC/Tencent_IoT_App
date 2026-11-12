import SwiftUI

struct CallLiveView: View {
    @Environment(AppState.self) private var state
    @Environment(AppRouter.self) private var router
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if let session = state.session, session.kind == .call {
            content(session)
        } else {
            Palette.background
                .ignoresSafeArea()
                .toolbar(.hidden, for: .navigationBar)
                .onAppear { router.pop() }
        }
    }

    private func content(_ session: ActiveSession) -> some View {
        let call = state.call
        return FlowScreen(background: .clear) {
            SessionHeader(title: "语音通话", showsStatus: false, backLabel: "返回，保持通话", onBack: router.pop)
        } content: {
            VStack(spacing: 0) {
                avatar
                    .padding(.top, 48)
                    .padding(.bottom, 22)
                Text("房间 \(session.title)")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                Text(statusText(call))
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.textSecondary)
                    .padding(.top, 14)
                Text(Clock.text(session.seconds))
                    .font(.system(size: 16))
                    .monospacedDigit()
                    .foregroundStyle(Palette.textSecondary)
                    .padding(.top, 12)
                if !state.isConnected {
                    InlineHint(tone: .error, text: "眼镜已断开，通话收音中断。") {
                        Button("重新连接") { state.reconnect() }
                            .buttonStyle(HintButtonStyle())
                    }
                    .padding(.top, 20)
                }
                Spacer(minLength: 24)
            }
            .frame(maxWidth: .infinity)
        } footer: {
            HStack(spacing: 40) {
                control(symbol: call.isMuted ? "mic.slash.fill" : "mic.fill", label: call.isMuted ? "取消静音" : "麦克风", danger: false, enabled: call.phase == .inCall) {
                    call.toggleMute()
                }
                control(symbol: "phone.down.fill", label: "挂断", danger: true, enabled: true) {
                    state.hangUp()
                }
            }
            .padding(.top, 16)
            .padding(.bottom, 12)
        }
        .background { if colorScheme != .dark { glow.ignoresSafeArea() } }
    }

    private var avatar: some View {
        Image(systemName: "person.fill")
            .font(.system(size: 40))
            .foregroundStyle(Palette.accent)
            .frame(width: 96, height: 96)
            .background(Circle().fill(Palette.accentSoft))
            .padding(8)
            .background(Circle().fill(colorScheme == .dark ? Palette.surfaceRaised : Color.white))
            .accessibilityHidden(true)
    }

    private var glow: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            ZStack {
                Color(hex: 0xF4ECEA)
                blob(0xF7A27E, 0.55, x: 0.45, y: 0.3, w: w * 1.1, h: h * 0.42, in: proxy.size)
                blob(0xF39A7A, 0.5, x: 0.55, y: 0.62, w: w * 1.2, h: h * 0.4, in: proxy.size)
                LinearGradient(colors: [.clear, Color(hex: 0xE9E9F0)], startPoint: .center, endPoint: .bottom)
            }
            .frame(width: w, height: h)
        }
    }

    private func blob(_ hex: UInt32, _ opacity: Double, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, in size: CGSize) -> some View {
        EllipticalGradient(colors: [Color(hex: hex, opacity: opacity), Color(hex: hex, opacity: 0)], center: .center, startRadiusFraction: 0, endRadiusFraction: 0.5)
            .frame(width: w, height: h)
            .position(x: size.width * x, y: size.height * y)
    }

    private func control(symbol: String, label: String, danger: Bool, enabled: Bool, action: @escaping () -> Void) -> some View {
        VStack(spacing: 8) {
            Button(action: action) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(danger ? Color.white : Palette.textPrimary)
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(danger ? Color(hex: 0xEF4B55) : (colorScheme == .dark ? Palette.surfaceRaised : Color.white.opacity(0.92))))
                    .opacity(enabled ? 1 : 0.45)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!enabled)
            .accessibilityLabel(label)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Palette.textSecondary)
                .accessibilityHidden(true)
        }
    }

    private func statusText(_ call: CallController) -> String {
        if !state.isConnected { return "眼镜断开 · 通话中断" }
        switch call.phase {
        case .idle: return "通话已结束"
        case .joining: return "正在进入房间…"
        case .inCall:
            if call.isReconnecting { return "网络波动，正在重连…" }
            if call.isMuted { return "已静音 · 对方听不到你" }
            return call.remoteUsers.isEmpty ? "等待对方进入房间…" : "通话中"
        }
    }
}
