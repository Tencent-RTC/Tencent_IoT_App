import SwiftUI

struct InterpretPrepView: View {
    @Environment(AppState.self) private var state
    @Environment(AppRouter.self) private var router
    @State private var openSide: LanguageSide?

    var body: some View {
        @Bindable var state = state
        FlowScreen {
            PageHeader(title: "双向传译", backLabel: "返回首页", onBack: router.pop)
        } content: {
            ScrollView {
                VStack(spacing: 18) {
                    languageCard
                    SettingsGroup {
                        SettingRow(icon: .records, title: "保存双语文字") {
                            SoftSwitch(isOn: $state.savesTranslationText, label: "保存双语文字")
                        }
                    }
                }
                .padding(1)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
        } footer: {
            VStack(spacing: 12) {
                if let reason = blockedReason {
                    Text(reason)
                        .font(AppFont.caption)
                        .foregroundStyle(Palette.danger)
                        .accessibilityAddTraits(.updatesFrequently)
                }
                Button {
                    openSide = nil
                    if state.startSession(.interpret) { router.replaceTop(with: .live(.interpret)) }
                } label: {
                    HStack(spacing: 9) {
                        AppIconView(.mic, size: 20)
                        Text("开始同传")
                    }
                }
                .buttonStyle(.primary)
                .disabled(!state.canStartCapture)
            }
            .padding(.top, 24)
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
    }

    private var languageCard: some View {
        HStack(spacing: 6) {
            LanguageTrigger(side: .source, label: "对方说", value: state.sourceLanguage, isOpen: openSide == .source) {
                toggle(.source)
            }
            Button {
                openSide = nil
                withAnimation(.snappy(duration: 0.2)) { state.swapLanguages() }
            } label: {
                AppIconView(.swap, size: 22)
                    .foregroundStyle(Palette.iconMuted)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("交换语言")
            .padding(.top, 24)
            LanguageTrigger(side: .target, label: "我说", value: state.targetLanguage, isOpen: openSide == .target) {
                toggle(.target)
            }
        }
        .padding(12)
        .surface(radius: 22)
    }

    private var blockedReason: String? { state.captureBlocker }

    private func toggle(_ side: LanguageSide) {
        openSide = openSide == side ? nil : side
    }
}
