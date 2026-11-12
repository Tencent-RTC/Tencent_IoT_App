import SwiftUI

struct InterpretLiveView: View {
    @Environment(AppState.self) private var state
    @Environment(AppRouter.self) private var router
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if let session = state.session, session.kind == .interpret {
            content(session)
        } else {
            Palette.background
                .ignoresSafeArea()
                .toolbar(.hidden, for: .navigationBar)
                .onAppear { router.popToRoot() }
        }
    }

    private func content(_ session: ActiveSession) -> some View {
        FlowScreen(spacing: 16) {
            LiveHeader(title: "双向传译", onBack: { state.dialog = .leaveSession })
        } content: {
            VStack(spacing: 16) {
                speakingSwitch(session)
                if !state.isConnected {
                    InlineHint(tone: .error, text: "眼镜已断开，已有文字已保留。断连期间的音频无法补回。") {
                        Button("重新连接") { state.reconnect() }
                            .buttonStyle(HintButtonStyle())
                    }
                } else if !state.isOnline {
                    InlineHint(tone: .warning, text: "网络中断，字幕暂停更新。")
                }
                CaptionTranscript(entries: session.entries, isPaused: session.isPaused) { index, line in
                    SentenceCard(index: index, line: line, isLatest: index == session.entries.count - 1, showSpeaker: true)
                }
                .frame(maxHeight: .infinity)
            }
        } footer: {
            HStack(spacing: 14) {
                AudioWave(isActive: state.canProcess)
                Button {
                    state.togglePause()
                } label: {
                    AppIconView(session.isPaused ? .play : .pause, size: 20)
                        .foregroundStyle(Palette.onAccent)
                        .frame(width: 51, height: 51)
                        .background {
                            if colorScheme == .dark {
                                Circle().fill(Palette.accent)
                            } else {
                                Circle().fill(Palette.primaryGradient)
                            }
                        }
                        .shadow(color: colorScheme == .dark ? .clear : Palette.primaryGlow, radius: 10, x: 0, y: 7)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(session.isPaused ? "继续同传" : "暂停同传")
                AudioWave(isActive: state.canProcess)
                    .scaleEffect(x: -1, y: 1)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
        }
    }

    private func speakingSwitch(_ session: ActiveSession) -> some View {
        HStack(spacing: 8) {
            ForEach(Speaker.allCases, id: \.rawValue) { item in
                let selected = item == session.speaking
                let label = item == .me ? "我说" : "对方说"
                Button {
                    if session.speaking != item { state.switchSpeaking() }
                } label: {
                    Text(label)
                        .font(AppFont.footnote)
                        .foregroundStyle(selected ? selectedForeground : Palette.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background {
                            if selected {
                                if colorScheme == .dark {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Palette.accentSoft)
                                } else {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Palette.primaryGradient)
                                }
                            }
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(selected ? "\(label)，正在翻译这一方" : "切换到\(label)")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(4)
        .glass(radius: 14)
    }

    private var selectedForeground: Color {
        colorScheme == .dark ? Palette.accentText : Palette.onAccent
    }
}
