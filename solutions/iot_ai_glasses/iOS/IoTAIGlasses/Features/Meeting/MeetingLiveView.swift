import SwiftUI

struct MeetingLiveView: View {
    @Environment(AppState.self) private var state
    @Environment(AppRouter.self) private var router
    @State private var showsSettings = false

    var body: some View {
        if let session = state.session, session.kind == .meeting {
            content(session)
        } else {
            Palette.background
                .ignoresSafeArea()
                .toolbar(.hidden, for: .navigationBar)
                .onAppear { router.popToRoot() }
        }
    }

    private func content(_ session: ActiveSession) -> some View {
        let speakers = MeetingSpeakerIndex.map(session.entries)
        return FlowScreen(spacing: 14) {
            SessionHeader(title: "会议转录", backLabel: "返回", onBack: { state.dialog = .endSession }, onSettings: { showsSettings = true })
        } content: {
            VStack(spacing: 12) {
                if !state.isConnected {
                    InlineHint(tone: .error, text: "眼镜已断开，已有文字已保留。断连期间的音频无法补回。") {
                        Button("重新连接") { state.reconnect() }
                            .buttonStyle(HintButtonStyle())
                    }
                } else if !state.isOnline {
                    InlineHint(tone: .warning, text: "网络中断，转录暂停更新。")
                }
                CaptionTranscript(entries: session.entries, isPaused: session.isPaused) { index, line in
                    let isLatest = index == session.entries.count - 1
                    MeetingCard(
                        index: index,
                        line: line,
                        isLatest: isLatest,
                        speakerIndex: speakers[line.speakerLabel ?? ""] ?? 0,
                        isSpeaking: isLatest && !session.isPaused && state.canProcess
                    )
                }
                .frame(maxHeight: .infinity)
            }
        } footer: {
            LiveControlBar(
                leading: LiveBarButton(
                    glyph: .symbol(session.isStarred ? "star.fill" : "star"),
                    tint: session.isStarred ? Palette.accent : Palette.textPrimary,
                    label: session.isStarred ? "取消星标" : "将本场会议标为星标",
                    action: state.toggleStar
                ),
                pillIcon: session.isPaused ? .play : .pause,
                pillText: "\(session.isPaused ? "已暂停" : "正在转录") · \(Clock.text(session.seconds))",
                pillLabel: session.isPaused ? "继续记录" : "暂停记录",
                onPill: state.togglePause,
                trailing: LiveBarButton(glyph: .app(.stop), label: "结束记录") { state.dialog = .endSession }
            )
        }
        .sheet(isPresented: $showsSettings) {
            SessionSettingsSheet(title: "会议设置") {
                SettingRow(icon: .meeting, title: "保留原始录音") {
                    SoftSwitch(isOn: Binding(get: { state.keepsMeetingAudio }, set: state.setKeepsMeetingAudio), label: "保留原始录音")
                }
            }
        }
    }
}
