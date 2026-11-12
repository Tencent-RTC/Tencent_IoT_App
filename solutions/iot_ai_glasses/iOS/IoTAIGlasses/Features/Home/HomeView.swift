import SwiftUI

struct HomeView: View {
    @AppStorage(AppTheme.storageKey) private var theme: AppTheme = .soft
    @Environment(AppState.self) private var state
    @Environment(AppRouter.self) private var router
    @State private var compact = false

    var body: some View {
        TabScreen(spacing: 14) {
            header
                .padding(.bottom, Spacing.section - 14)
            Button {
                router.select(.device)
            } label: {
                ProductHero(isConnected: state.isConnected, batteryLevel: state.batteryLevel)
            }
            .buttonStyle(.plain)
            .accessibilityHint("打开我的眼镜")

            if let session = state.session {
                SessionBanner(status: state.sessionStatus(session), seconds: session.seconds) {
                    router.push(.live(session.kind))
                }
            }

            features
            recent
        }
    }

    private var header: some View {
        HStack {
            Wordmark()
            Spacer()
            CircleIconButton(
                icon: theme == .dark ? .sun : .moon,
                accessibilityLabel: theme == .dark ? "切换到浅色主题" : "切换到深色主题"
            ) {
                withAnimation(.easeInOut(duration: 0.25)) {
                    theme = theme.toggled
                }
            }
        }
        .frame(height: 44)
    }

    private var features: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("让每一次交流，都有回响。")
                    .font(.system(size: 18, weight: theme == .dark ? .medium : .semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .frame(height: 30)
                    .accessibilityAddTraits(.isHeader)
                Text("AI 功能 · 语音经眼镜采集")
                    .font(AppFont.caption)
                    .foregroundStyle(Palette.textSecondary)
            }
            HStack(spacing: compact ? 10 : 12) {
                FeatureCard(feature: .listen, compact: compact) { open(.listen) }
                FeatureCard(feature: .meeting, compact: compact) { open(.meeting) }
            }
            HStack(spacing: compact ? 8 : 10) {
                FeatureCard(feature: .call, compact: compact) { open(.call) }
                FeatureCard(feature: .chat, compact: compact) { open(.chat) }
            }
        }
        .onGeometryChange(for: Bool.self) { $0.size.width < 347 } action: { compact = $0 }
    }

    private func open(_ feature: Feature) {
        if let kind = feature.sessionKind, let session = state.session {
            if session.kind == kind {
                router.push(.live(kind))
            } else {
                state.dialog = .conflict
            }
            return
        }
        if feature == .meeting || feature == .listen {
            let kind: SessionKind = feature == .meeting ? .meeting : .translation
            if state.startSession(kind) {
                router.replaceTop(with: .live(kind))
            } else {
                state.showToast(state.captureBlocker ?? "已有任务进行中，请先结束")
            }
            return
        }
        router.push(feature.route)
    }

    private var recent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("最近记录")
                    .font(.system(size: 15, weight: theme == .dark ? .medium : .semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if !state.records.isEmpty {
                    Button("共 \(state.records.count) 条 · 全部") { router.select(.records) }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(light: 0xD9552E, dark: 0xE8A184))
                        .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
                        .accessibilityLabel("查看全部记录，共 \(state.records.count) 条")
                }
            }
            .frame(height: 44)

            if state.records.isEmpty {
                Text("你的第一条记录，会从这里开始。")
                    .font(AppFont.caption)
                    .foregroundStyle(Palette.textSecondary)
            } else {
                VStack(spacing: 10) {
                    ForEach(state.records.prefix(3)) { record in
                        RecentRecordRow(record: record) {
                            router.push(.recordDetail(record.id))
                        }
                    }
                }
            }
        }
    }
}

struct RecentRecordRow: View {
    let record: Record
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var badge: (text: String, fg: UInt32, bg: UInt32) {
        if record.kind == .meeting {
            return ("纪要", 0x2F6BD8, 0xE9F1FE)
        }
        if record.isInterpret == true {
            return ("传译", 0x1F8A5A, 0xE4F5EC)
        }
        return ("翻译", 0x5B4CF0, 0xEEEBFE)
    }

    private var icon: AppIcon {
        record.kind == .meeting ? .meeting : .language
    }

    var body: some View {
        let dark = colorScheme == .dark
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        let badge = badge
        Button(action: action) {
            HStack(spacing: 12) {
                AppIconView(icon, size: 20)
                    .foregroundStyle(Color(light: badge.fg, dark: badge.fg))
                    .frame(width: 36, height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(light: badge.bg, dark: badge.bg))
                    )
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(record.title)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Palette.textPrimary)
                            .lineLimit(1)
                        if record.isStarred == true {
                            Image(systemName: "star.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(Palette.accent)
                                .accessibilityLabel("星标")
                        }
                        Text(badge.text)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color(light: 0xD9552E, dark: 0xE8A184))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1.5)
                            .background(
                                Capsule().fill(Color(light: 0xFDEDE3, dark: 0x3A2A22))
                            )
                            .accessibilityHidden(true)
                    }
                    Text(record.subtitle())
                        .font(AppFont.caption)
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                AppIconView(.arrow, size: 18)
                    .foregroundStyle(Palette.textSecondary)
                    .opacity(0.72)
            }
            .padding(.horizontal, dark ? 14 : 12)
            .padding(.vertical, 10)
            .background {
                if !dark {
                    shape.fill(Palette.surfaceRaised)
                }
            }
            .overlay {
                if !dark {
                    shape.strokeBorder(Palette.glassStroke, lineWidth: 1)
                }
            }
            .elevation(dark ? .none : .raised)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

struct Wordmark: View {
    var body: some View {
        HStack(spacing: 11) {
            Text("AI眼镜")
                .font(AppFont.wordmark)
                .tracking(-0.5)
                .foregroundStyle(Palette.textPrimary)
            Text("AI GLASSES")
                .font(AppFont.wordmarkCaption)
                .tracking(1.1)
                .foregroundStyle(Palette.textSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("AI眼镜")
        .accessibilityAddTraits(.isHeader)
    }
}

#Preview {
    RootView()
}
