import SwiftUI

struct RecordsView: View {
    private enum RecordFilter: String, CaseIterable, Identifiable {
        case all = "全部"
        case meeting = "会议"
        case translation = "翻译"

        var id: String { rawValue }

        var kind: RecordKind? {
            switch self {
            case .all: nil
            case .meeting: .meeting
            case .translation: .translation
            }
        }
    }

    @Environment(AppState.self) private var state
    @Environment(AppRouter.self) private var router
    @State private var query = ""
    @State private var filter: RecordFilter = .all

    private var results: [Record] {
        state.records.filter { record in
            guard filter.kind == nil || record.kind == filter.kind else { return false }
            guard !query.isEmpty else { return true }
            return record.title.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        TabScreen(spacing: 14) {
            ScreenTitle("记录") {
                Text("\(state.records.count) 条")
                    .font(AppFont.caption)
                    .foregroundStyle(Palette.textSecondary)
            }
            .padding(.bottom, 10)

            searchField

            HStack(spacing: 8) {
                ForEach(RecordFilter.allCases) { item in
                    RecordFilterChip(title: item.rawValue, isActive: filter == item) {
                        withAnimation(.snappy(duration: 0.18)) { filter = item }
                    }
                }
                Spacer()
            }

            if results.isEmpty {
                Text(query.isEmpty && filter.kind == nil ? "你的第一条记录，会从这里开始。" : "没有找到匹配的记录")
                    .font(AppFont.footnote)
                    .foregroundStyle(Palette.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(results) { record in
                        RecordCard(record: record) {
                            router.push(.recordDetail(record.id))
                        }
                    }
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            AppIconView(.records, size: 16)
                .foregroundStyle(Palette.iconMuted)
            TextField("搜索记录名称", text: $query)
                .font(AppFont.body)
                .autocorrectionDisabled()
                .accessibilityLabel("搜索记录名称")
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    AppIconView(.close, size: 14)
                        .foregroundStyle(Palette.iconMuted)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除搜索")
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct RecordFilterChip: View {
    let title: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(AppFont.captionMedium)
                .foregroundStyle(isActive ? Palette.accentText : Palette.textSecondary)
                .padding(.horizontal, 16)
                .frame(minHeight: 34)
                .background(isActive ? Palette.accentSoft : Palette.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(isActive ? Palette.noticeBorder : Palette.line, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

struct RecordCard: View {
    let record: Record
    let action: () -> Void

    var body: some View {
        let tone = record.kind == .meeting ? SpeakerTonePalette.tone(4) : SpeakerTonePalette.tone(0)
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(record.kind == .meeting ? "会议" : "翻译")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(tone.text)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 2)
                        .background(tone.background, in: Capsule())
                        .overlay(Capsule().strokeBorder(tone.border, lineWidth: 1))
                    Spacer()
                    if record.kind == .meeting, record.summary?.phase != .ready {
                        Text("待联网处理")
                            .font(.system(size: 11))
                            .foregroundStyle(CaptionPalette.warnText)
                    }
                }
                HStack(spacing: 6) {
                    Text(record.title)
                        .font(AppFont.bodyMedium)
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                    if record.isStarred == true {
                        Image(systemName: "star.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.accent)
                    }
                }
                Text(record.subtitle())
                    .font(AppFont.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface, in: shape)
            .overlay(shape.strokeBorder(Palette.line, lineWidth: 1))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(record.kind == .meeting ? "会议" : "翻译")记录，\(record.isStarred == true ? "星标，" : "")\(record.title)，\(record.subtitle())")
        .accessibilityHint("双击查看详情")
    }
}
