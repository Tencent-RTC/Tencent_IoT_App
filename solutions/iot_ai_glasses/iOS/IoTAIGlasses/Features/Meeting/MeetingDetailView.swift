import SwiftUI

struct MeetingDetailView: View {
    let recordID: UUID

    @Environment(AppState.self) private var state
    @Environment(AppRouter.self) private var router
    @State private var tab: MeetingDetailTab = .summary

    private enum MeetingDetailTab: String, CaseIterable {
        case summary = "摘要"
        case transcript = "原文"
        case todos = "待办"
    }

    var body: some View {
        if let record = state.records.first(where: { $0.id == recordID }) {
            content(record)
        } else {
            Palette.background
                .ignoresSafeArea()
                .toolbar(.hidden, for: .navigationBar)
                .onAppear { router.pop() }
        }
    }

    private func content(_ record: Record) -> some View {
        FlowScreen(spacing: 16) {
            PageHeader(title: record.title, subtitle: record.subtitle(), backLabel: "返回", onBack: router.pop) {
                ShareLink(item: exportText(record)) {
                    AppIconView(.download, size: 19)
                        .foregroundStyle(Palette.textPrimary)
                        .headerCircle()
                }
                .accessibilityLabel("导出文字")
            }
        } content: {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    tabs

                    switch tab {
                    case .summary: summaryBody(record)
                    case .transcript: transcriptBody(record)
                    case .todos: todosBody(record)
                    }
                }
                .padding(1)
                .scrollShadowProbe()
            }
            .topScrollShadow()
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
        } footer: {
            Color.clear.frame(height: 0)
        }
    }

    private var tabs: some View {
        HStack(spacing: 8) {
            ForEach(MeetingDetailTab.allCases, id: \.rawValue) { item in
                Button {
                    withAnimation(.snappy(duration: 0.18)) { tab = item }
                } label: {
                    Text(item.rawValue)
                        .font(AppFont.footnote)
                        .foregroundStyle(tab == item ? Palette.accentText : Palette.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background {
                            if tab == item {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Palette.accentSoft)
                            }
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(tab == item ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private func summaryBody(_ record: Record) -> some View {
        switch record.summary?.phase {
        case nil:
            DetailCard {
                Text("AI 服务未配置，无法生成摘要。")
                    .font(AppFont.footnote)
                    .foregroundStyle(Palette.textSecondary)
            }
        case .pending:
            if state.isOnline {
                DetailCard {
                    HStack(spacing: 10) {
                        if state.isSummaryGenerating(record.id) {
                            ThinkingDots()
                            Text("正在生成摘要…")
                        } else {
                            Text("待联网处理。恢复网络后自动生成，也可以手动重试。")
                        }
                    }
                    .font(AppFont.footnote)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                if !state.isSummaryGenerating(record.id) {
                    retryButton
                }
            } else {
                DetailCard {
                    Text("待联网处理。此段内容还没有生成摘要。")
                        .font(AppFont.footnote)
                        .foregroundStyle(CaptionPalette.warnText)
                }
                retryButton
            }
        case .failed:
            DetailCard {
                Text("摘要生成失败，请重试。")
                    .font(AppFont.footnote)
                    .foregroundStyle(CaptionPalette.errorText)
            }
            retryButton
        case .ready:
            let summary = record.summary ?? MeetingSummary()
            VStack(alignment: .leading, spacing: 14) {
                DetailCard(title: "一句话总结") {
                    Text(summary.headline)
                        .font(AppFont.body)
                        .lineSpacing(4)
                        .foregroundStyle(CaptionPalette.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !summary.consensus.isEmpty {
                    DetailCard(title: "已达成共识") {
                        DetailList(items: summary.consensus)
                    }
                }
                if !summary.questions.isEmpty {
                    DetailCard(title: "待确认问题") {
                        DetailList(items: summary.questions)
                    }
                }
            }
        case .some:
            EmptyView()
        }
    }

    private var retryButton: some View {
        Button {
            state.retrySummary(recordID)
        } label: {
            Text("重试")
        }
        .buttonStyle(.pill)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func transcriptBody(_ record: Record) -> some View {
        let lines = record.transcript ?? []
        let index = MeetingSpeakerIndex.map(lines)
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                AppIconView(.play, size: 16)
                    .foregroundStyle(Palette.textSecondary)
                Text(record.keepsAudio ? "录音回听" : "未保留原始录音")
                    .font(AppFont.caption)
                    .foregroundStyle(Palette.textSecondary)
            }
            .padding(.horizontal, 14)
            .frame(height: 40)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            if lines.isEmpty {
                Text("没有识别到文字")
                    .font(AppFont.footnote)
                    .foregroundStyle(Palette.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
            } else {
                ForEach(Array(lines.enumerated()), id: \.element.id) { position, line in
                    MeetingCard(
                        index: position,
                        line: line,
                        isLatest: false,
                        speakerIndex: index[line.speakerLabel ?? ""] ?? 0
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func todosBody(_ record: Record) -> some View {
        let todos = record.summary?.todos ?? []
        if todos.isEmpty {
            Text("本条记录未提取到待办。")
                .font(AppFont.footnote)
                .foregroundStyle(Palette.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
        } else {
            VStack(alignment: .leading, spacing: 14) {
                DetailCard {
                    VStack(spacing: 0) {
                        ForEach(Array(todos.enumerated()), id: \.element.id) { position, todo in
                            if position > 0 {
                                Rectangle().fill(Palette.separator).frame(height: 1)
                            }
                            Button {
                                state.toggleMeetingTodo(record.id, todoID: todo.id)
                            } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    TodoCheck(isOn: todo.isDone)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(todo.text)
                                            .font(AppFont.body)
                                            .foregroundStyle(Palette.textPrimary)
                                            .strikethrough(todo.isDone, color: Palette.textSecondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                        Text(todo.note)
                                            .font(AppFont.caption)
                                            .foregroundStyle(Palette.textSecondary)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(.vertical, 14)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(todo.isDone ? "完成待办：\(todo.text)" : "待办：\(todo.text)")
                            .accessibilityHint(todo.isDone ? "双击取消完成" : "双击完成")
                        }
                    }
                }
            }
        }
    }

    private func exportText(_ record: Record) -> String {
        var lines = ["\(record.title)", record.subtitle(), ""]
        lines.append("—— 原文 ——")
        for line in record.transcript ?? [] {
            lines.append("[\(line.speakerLabel ?? "发言")] \(line.original)")
        }
        if let summary = record.summary, summary.phase == .ready {
            lines.append("")
            lines.append("—— 摘要 ——")
            lines.append(summary.headline)
            if !summary.consensus.isEmpty {
                lines.append("已达成共识：")
                lines.append(contentsOf: summary.consensus.map { "· \($0)" })
            }
            if !summary.questions.isEmpty {
                lines.append("待确认问题：")
                lines.append(contentsOf: summary.questions.map { "· \($0)" })
            }
            if !summary.todos.isEmpty {
                lines.append("待办：")
                lines.append(contentsOf: summary.todos.map { "· \($0.text)（\($0.note)）" })
            }
        }
        return lines.joined(separator: "\n")
    }
}

private struct DetailCard<Content: View>: View {
    var title: String?
    @ViewBuilder let content: Content

    init(title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                Text(title)
                    .font(AppFont.bodyMedium)
                    .foregroundStyle(Palette.textPrimary)
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface(radius: 18)
    }
}

private struct DetailList: View {
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(Palette.accentText)
                        .frame(width: 4, height: 4)
                        .padding(.top, 7)
                    Text(item)
                        .font(AppFont.footnote)
                        .lineSpacing(4)
                        .foregroundStyle(CaptionPalette.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct TodoCheck: View {
    let isOn: Bool

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(isOn ? Palette.accent : Palette.checkboxBorder, lineWidth: 1.5)
            if isOn {
                Circle().fill(Palette.accent)
                AppIconView(.check, size: 12)
                    .foregroundStyle(Palette.onAccent)
            }
        }
        .frame(width: 20, height: 20)
        .padding(.top, 2)
    }
}
