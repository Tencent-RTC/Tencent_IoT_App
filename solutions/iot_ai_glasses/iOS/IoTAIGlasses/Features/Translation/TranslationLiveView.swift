import SwiftUI

struct TranslationLiveView: View {
    @Environment(AppState.self) private var state
    @Environment(AppRouter.self) private var router
    @State private var openSide: LanguageSide?
    @State private var showsSettings = false

    var body: some View {
        if let session = state.session, session.kind == .translation {
            content(session)
        } else {
            Palette.background
                .ignoresSafeArea()
                .toolbar(.hidden, for: .navigationBar)
                .onAppear { router.popToRoot() }
        }
    }

    private func content(_ session: ActiveSession) -> some View {
        FlowScreen(spacing: 14) {
            SessionHeader(title: "实时翻译", backLabel: "返回", onBack: { state.dialog = .endSession }, onSettings: { showsSettings = true })
        } content: {
            VStack(spacing: 12) {
                languageBar
                if !state.isConnected {
                    InlineHint(tone: .error, text: "眼镜已断开，已有文字已保留。断连期间的音频无法补回。") {
                        Button("重新连接") { state.reconnect() }
                            .buttonStyle(HintButtonStyle())
                    }
                } else if !state.isOnline {
                    InlineHint(tone: .warning, text: "网络中断，字幕暂停更新。")
                }
                CaptionTranscript(entries: session.entries, isPaused: session.isPaused) { index, line in
                    SentenceCard(index: index, line: line, isLatest: index == session.entries.count - 1)
                }
                .frame(maxHeight: .infinity)
            }
        } footer: {
            LiveControlBar(
                leading: LiveBarButton(
                    glyph: .app(.speaker),
                    tint: state.readsTranslationAloud ? Palette.textPrimary : Palette.textSecondary.opacity(0.6),
                    label: state.readsTranslationAloud ? "关闭译文播报" : "开启译文播报",
                    action: state.toggleReadAloud
                ),
                pillIcon: session.isPaused ? .play : .pause,
                pillText: "\(session.isPaused ? "已暂停" : "正在翻译") · \(Clock.text(session.seconds))",
                pillLabel: session.isPaused ? "继续翻译" : "暂停翻译",
                onPill: state.togglePause,
                trailing: LiveBarButton(glyph: .app(.stop), label: "结束翻译") { state.dialog = .endSession }
            )
        }
        .overlayPreferenceValue(LanguageAnchorKey.self) { anchors in
            GeometryReader { proxy in
                if let side = openSide, let anchor = anchors[side] {
                    let rect = proxy[anchor]
                    ZStack(alignment: .topLeading) {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { openSide = nil }
                            .accessibilityHidden(true)
                        LanguageMenu(selection: side == .source ? state.sourceLanguage : state.targetLanguage) { language in
                            withAnimation(.snappy(duration: 0.2)) {
                                if side == .source {
                                    state.setSourceLanguage(language)
                                } else {
                                    state.setTargetLanguage(language)
                                }
                                openSide = nil
                            }
                        }
                        .offset(x: rect.minX, y: rect.maxY + 8)
                        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                    }
                }
            }
            .animation(.snappy(duration: 0.18), value: openSide)
        }
        .sheet(isPresented: $showsSettings) {
            SessionSettingsSheet(title: "翻译设置", height: state.availableEngines.count > 1 ? 288 : 220) {
                if state.availableEngines.count > 1 {
                    SettingRow(icon: .listen, title: "识别方式") {
                        Menu {
                            ForEach(state.availableEngines) { engine in
                                Button(engine.title) { state.setCaptionEngine(engine) }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(state.captionEngine.title)
                                AppIconView(.chevronDown, size: 14)
                            }
                            .font(AppFont.callout)
                            .foregroundStyle(Palette.accentText)
                            .frame(minHeight: 44)
                        }
                        .accessibilityLabel("识别方式：\(state.captionEngine.title)")
                    }
                }
                SettingRow(icon: .records, title: "保存双语文字", showsDivider: state.availableEngines.count > 1) {
                    SoftSwitch(isOn: Binding(get: { state.savesTranslationText }, set: state.setSavesTranslationText), label: "保存双语文字")
                }
                SettingRow(icon: .speaker, title: "自动播放译文", showsDivider: true) {
                    SoftSwitch(isOn: Binding(get: { state.readsTranslationAloud }, set: { if $0 != state.readsTranslationAloud { state.toggleReadAloud() } }), label: "自动播放译文")
                }
            }
        }
    }

    private var languageBar: some View {
        HStack(spacing: 8) {
            LanguageTrigger(side: .source, label: "听到的语言", value: state.sourceLanguage, isOpen: openSide == .source, boxed: true) {
                toggle(.source)
            }
            Button {
                openSide = nil
                withAnimation(.snappy(duration: 0.2)) { state.swapLanguages() }
            } label: {
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Palette.accentSoft))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("交换语言")
            LanguageTrigger(side: .target, label: "我的期望语言", value: state.targetLanguage, isOpen: openSide == .target, boxed: true) {
                toggle(.target)
            }
        }
        .padding(8)
        .surface(radius: 20)
    }

    private func toggle(_ side: LanguageSide) {
        openSide = openSide == side ? nil : side
    }
}
