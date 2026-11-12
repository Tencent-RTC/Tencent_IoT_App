import SwiftUI

struct ChatView: View {
    @Environment(AppState.self) private var state
    @Environment(AppRouter.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        FlowScreen(spacing: 14) {
            SessionHeader(title: "AI 对话", backLabel: "返回首页", onBack: router.pop)
        } content: {
            if state.chat.isEmpty {
                emptyState
            } else {
                thread
            }
        } footer: {
            footer
        }
        .onDisappear { state.chat.interrupt("已停止聆听", quiet: true) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { state.chat.interrupt("已停止聆听", quiet: true) }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image("art-chat")
                .resizable()
                .scaledToFit()
                .frame(width: 132, height: 132)
                .accessibilityHidden(true)
            Text("有什么想问的？")
                .font(AppFont.bodyMedium)
                .foregroundStyle(Palette.textPrimary)
            Text("对眼镜说出问题，回答会显示在这里")
                .font(AppFont.caption)
                .foregroundStyle(Palette.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var thread: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(state.chat.turns) { turn in
                        ChatTurnView(turn: turn,
                                     isSpeaking: state.chat.speakingTurnID == turn.id,
                                     canRetry: state.chat.canRetry && state.canStartCapture && state.session == nil, onRetry: {
                            guard state.canStartCapture, state.session == nil else { return }
                            state.chat.retry(turn.id)
                        })
                        .id(turn.id)
                    }
                }
                .padding(.vertical, 4)
                .scrollShadowProbe()
            }
            .topScrollShadow()
            .scrollDismissesKeyboard(.interactively)
            .onAppear {
                if let id = state.chat.turns.last?.id { proxy.scrollTo(id, anchor: .bottom) }
            }
            .onChange(of: state.chat.turns) {
                if let id = state.chat.turns.last?.id {
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .bottom) }
                }
            }
        }
    }

    private var footer: some View {
        let chat = state.chat
        let canStop = chat.isBusy || chat.speakingTurnID != nil
        return VStack(spacing: 12) {
            if !state.isConnected {
                InlineHint(tone: .error, text: "眼镜未连接，无法收音提问。") {
                    Button("重新连接") { state.reconnect() }
                        .buttonStyle(HintButtonStyle())
                }
            } else if !state.isOnline {
                InlineHint(tone: .warning, text: "网络中断，暂不能提问。")
            } else if let reason = state.captureBlocker {
                InlineHint(tone: .warning, text: reason)
            }

            LiveControlBar(
                leading: LiveBarButton(
                    glyph: .app(.speaker),
                    tint: chat.readsAloud ? Palette.textPrimary : Palette.textSecondary.opacity(0.6),
                    label: chat.readsAloud ? "关闭回答播报" : "开启回答播报",
                    action: chat.toggleReadsAloud
                ),
                pillIcon: chat.isListening ? .pause : .mic,
                pillText: chat.isListening ? "正在聆听" : "点击开始提问",
                pillLabel: chat.isListening ? "暂停聆听" : "开始聆听",
                pillEnabled: chat.isListening || state.canStartCapture,
                onPill: togglePrompt,
                trailing: LiveBarButton(glyph: .app(.stop), label: "停止", isEnabled: canStop) {
                    if chat.speakingTurnID != nil { chat.stopSpeaking() }
                    if chat.isBusy { chat.interrupt("已停止") }
                }
            )
        }
    }

    private func togglePrompt() {
        if state.chat.isListening {
            state.chat.pauseListening()
            return
        }
        guard state.canStartCapture else { return }
        if state.session != nil {
            state.dialog = .conflict
            return
        }
        state.chat.beginQuestion()
    }
}

private struct ChatTurnView: View {
    let turn: ChatTurn
    let isSpeaking: Bool
    let canRetry: Bool
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            QuestionBubble(text: turn.displayQuestion, isLive: turn.phase == .listening)
            if turn.phase == .interrupted {
                Text("本轮已中断")
                    .font(AppFont.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            } else if turn.phase != .listening {
                AnswerCard(turn: turn, isSpeaking: isSpeaking, canRetry: canRetry, onRetry: onRetry)
                    .padding(.trailing, 24)
            }
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }
}

private struct QuestionBubble: View {
    let text: String
    let isLive: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        VStack(alignment: .trailing, spacing: 6) {
            HStack {
                Spacer(minLength: 56)
                Text(text)
                    .font(.system(size: 14.5))
                    .lineSpacing(4)
                    .foregroundStyle(CaptionPalette.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Palette.accentSoft, in: shape)
                    .overlay(shape.strokeBorder(CaptionPalette.latestActiveBorder, lineWidth: 1))
            }
            if isLive {
                HStack(spacing: 5) {
                    Circle()
                        .fill(CaptionPalette.latestActiveTag)
                        .frame(width: 5, height: 5)
                    Text("实时识别中")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(CaptionPalette.latestActiveTag)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isLive ? "提问，识别中：\(text)" : "提问：\(text)")
    }
}

private struct AnswerCard: View {
    let turn: ChatTurn
    let isSpeaking: Bool
    let canRetry: Bool
    let onRetry: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sparkle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.accent)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Palette.accentSoft))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 10) {
                content
                if isSpeaking {
                    HStack(spacing: 5) {
                        AppIconView(.speaker, size: 13)
                        Text("正在眼镜中播报")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(CaptionPalette.latestActiveTag)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CaptionPalette.card, in: shape)
            .overlay(shape.strokeBorder(CaptionPalette.border, lineWidth: 1))
        }
    }

    @ViewBuilder
    private var content: some View {
        switch turn.phase {
        case .done:
            Text(turn.answer ?? "")
                .font(AppFont.body)
                .lineSpacing(5)
                .foregroundStyle(CaptionPalette.text)
                .fixedSize(horizontal: false, vertical: true)
        case .thinking:
            HStack(spacing: 8) {
                ThinkingDots()
                Text("思考中…")
                    .font(AppFont.body)
                    .foregroundStyle(Palette.textSecondary)
            }
        case .failed:
            VStack(alignment: .leading, spacing: 10) {
                Text("回答生成失败，请检查网络后重试。")
                    .font(AppFont.body)
                    .foregroundStyle(CaptionPalette.errorText)
                Button {
                    onRetry()
                } label: {
                    Text("重试")
                }
                .buttonStyle(.pill)
                .disabled(!canRetry)
            }
        case .listening, .interrupted:
            EmptyView()
        }
    }
}

struct ThinkingDots: View {
    @State private var phase = 0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Palette.textSecondary.opacity(phase == index ? 1 : 0.35))
                    .frame(width: 5, height: 5)
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(420))
                phase = (phase + 1) % 3
            }
        }
        .accessibilityHidden(true)
    }
}
