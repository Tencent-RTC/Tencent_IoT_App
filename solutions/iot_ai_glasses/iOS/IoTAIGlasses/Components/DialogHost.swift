import SwiftUI

struct DialogHost: View {
    @Environment(AppState.self) private var state
    @Environment(AppRouter.self) private var router

    var body: some View {
        ZStack(alignment: .bottom) {
            if let dialog = state.dialog {
                Palette.scrim
                    .ignoresSafeArea()
                    .onTapGesture { state.dialog = nil }
                    .accessibilityLabel("关闭")
                    .accessibilityAddTraits(.isButton)
                    .transition(.opacity)
                BottomSheet {
                    content(for: dialog)
                }
                .id(dialog.id)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.28), value: state.dialog)
    }

    @ViewBuilder
    private func content(for dialog: AppDialog) -> some View {
        switch dialog {
        case .endSession:
            EndSessionSheet()
        case .leaveSession:
            EndSessionSheet(leaving: true)
        case .discardConfirm:
            DiscardConfirmSheet()
        case .conflict:
            SheetBody(title: "已有任务进行中", messages: ["翻译、同传、会议与通话不能同时使用眼镜麦克风。请返回当前任务，或先结束并保存。"]) {
                Button("返回当前任务") {
                    state.dialog = nil
                    if let kind = state.session?.kind { router.push(.live(kind)) }
                }
                .buttonStyle(.primary(height: 48, radius: 10, font: .system(size: 14, weight: .semibold)))
                Button("留在当前页面") { state.dialog = nil }
                    .buttonStyle(.sheet)
            }
        case .meetingInfo:
            MeetingInfoSheet()
        }
    }
}

private struct BottomSheet<Content: View>: View {
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: colorScheme == .dark ? 24 : 28, style: .continuous)
        content
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.sheet, in: shape)
            .overlay(shape.strokeBorder(Palette.sheetBorder, lineWidth: 1))
            .shadow(color: Palette.shadow.opacity(colorScheme == .dark ? 0 : 0.1), radius: 20, x: 0, y: -12)
            .padding(12)
            .accessibilityAddTraits(.isModal)
    }
}

private struct SheetBody<Extra: View, Actions: View>: View {
    let title: String
    let messages: [String]
    @ViewBuilder let extra: Extra
    @ViewBuilder let actions: Actions

    init(title: String, messages: [String], @ViewBuilder extra: () -> Extra, @ViewBuilder actions: () -> Actions) {
        self.title = title
        self.messages = messages
        self.extra = extra()
        self.actions = actions()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, 12)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(messages, id: \.self) { message in
                    Text(message)
                        .font(AppFont.footnote)
                        .foregroundStyle(Palette.textSecondary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            extra
            VStack(spacing: 9) {
                actions
            }
            .padding(.top, 24)
        }
    }
}

extension SheetBody where Extra == EmptyView {
    init(title: String, messages: [String], @ViewBuilder actions: () -> Actions) {
        self.init(title: title, messages: messages, extra: { EmptyView() }, actions: actions)
    }
}

private struct EndSessionSheet: View {
    var leaving = false
    @Environment(AppState.self) private var state
    @Environment(AppRouter.self) private var router

    var body: some View {
        let kind = state.session?.kind ?? .translation
        let saves = kind == .meeting || state.session?.savesText == true
        SheetBody(
            title: kind == .meeting ? "结束这场会议？" : kind == .interpret ? "结束本次同传？" : "结束本次翻译？",
            messages: ["将停止音频采集。" + (saves ? "已确认的内容会保存到记录。" : "当前未开启保存文字。")]
        ) {
            if leaving {
                Button(saves ? "结束并保存" : "结束，不保存") { finish() }
                    .buttonStyle(.primary(height: 48, radius: 10, font: .system(size: 14, weight: .semibold)))
                Button("不结束，仅返回") {
                    state.dialog = nil
                    router.popToRoot()
                }
                .buttonStyle(.sheet)
            } else {
                if saves {
                    Button("结束并保存") { finish() }
                        .buttonStyle(.primary(height: 48, radius: 10, font: .system(size: 14, weight: .semibold)))
                    Button("不保存直接结束") { discard() }
                        .buttonStyle(.sheet)
                } else {
                    Button("不保存直接结束") { discard() }
                        .buttonStyle(.primary(height: 48, radius: 10, font: .system(size: 14, weight: .semibold)))
                }
            }
        }
    }

    private func discard() {
        state.dialog = .discardConfirm
    }

    private func finish() {
        if let record = state.finishSession() {
            router.replaceTop(with: .recordDetail(record.id))
        } else {
            router.popToRoot()
        }
    }
}

private struct DiscardConfirmSheet: View {
    @Environment(AppState.self) private var state
    @Environment(AppRouter.self) private var router

    var body: some View {
        let kind = state.session?.kind ?? .translation
        let count = state.session?.entries.count ?? 0
        SheetBody(
            title: "确定不保存？",
            messages: ["本次" + (kind == .meeting ? "会议" : "翻译") + (count > 0 ? "已有 \(count) 段内容，" : "") + "结束后将直接丢弃，无法恢复。"]
        ) {
            Button("确认不保存") {
                state.discardSession()
                router.popToRoot()
            }
            .buttonStyle(.danger)
            Button("返回") { state.dialog = .endSession }
                .buttonStyle(.sheet)
        }
    }
}

private struct MeetingInfoSheet: View {
    @Environment(AppState.self) private var state

    var body: some View {
        let session = state.session
        SheetBody(title: "会议信息", messages: session.map { session in
            var lines = [
                "会议名称：" + (session.title.isEmpty ? "未命名会议" : session.title),
                "会议语言：中文",
                "已进行 \(Clock.text(session.seconds)) · 已转 \(session.entries.count) 段"
            ]
            lines.append(session.keepsAudio ? "结束后保存录音与文字" : "结束后仅保存文字")
            return lines
        } ?? ["当前没有进行中的会议"]) {
            Button("知道了") { state.dialog = nil }
                .buttonStyle(.primary(height: 48, radius: 10, font: .system(size: 14, weight: .semibold)))
        }
    }
}
