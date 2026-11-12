import SwiftUI

private struct ContentFrameKey: PreferenceKey {
    static let defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

struct CaptionTranscript<Card: View>: View {
    let entries: [TranscriptLine]
    let isPaused: Bool
    @ViewBuilder let card: (Int, TranscriptLine) -> Card

    @State private var follows = true
    @State private var programmaticScroll = false
    @State private var viewportHeight: CGFloat = 0
    @State private var lastMinY: CGFloat = 0

    private static var bottomID: String { "transcript-bottom" }
    private static var nearBottom: CGFloat { 48 }

    var body: some View {
        if entries.isEmpty {
            VStack(spacing: 12) {
                AppIconView(.mic, size: 30)
                    .foregroundStyle(Palette.accent)
                Text(isPaused ? "已暂停收音" : "准备聆听")
                    .font(.system(size: 17))
                    .foregroundStyle(Palette.textPrimary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .combine)
        } else {
            ScrollViewReader { proxy in
                ZStack(alignment: .bottom) {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(Array(entries.enumerated()), id: \.element.id) { index, line in
                                card(index, line)
                            }
                            Color.clear.frame(height: 1).id(Self.bottomID)
                        }
                        .padding(.bottom, follows ? 0 : 44)
                        .padding(1)
                        .background {
                            GeometryReader { geometry in
                                Color.clear.preference(key: ContentFrameKey.self, value: geometry.frame(in: .named("transcript")))
                            }
                        }
                        .scrollShadowProbe()
                    }
                    .coordinateSpace(name: "transcript")
                    .topScrollShadow()
                    .scrollIndicators(.hidden)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { viewportHeight = $0 }
                    .onPreferenceChange(ContentFrameKey.self) { frame in
                        updateFollow(frame, proxy)
                    }
                    .accessibilityLabel("双语字幕")

                    if !follows {
                        Button {
                            scrollToLatest(proxy, animated: true)
                        } label: {
                            Text("回到最新 ↓")
                                .font(AppFont.caption)
                                .foregroundStyle(CaptionPalette.returnText)
                                .padding(.horizontal, 16)
                                .frame(height: 36)
                                .background(CaptionPalette.returnBackground, in: Capsule())
                                .overlay(Capsule().strokeBorder(CaptionPalette.returnBorder, lineWidth: 1))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .animation(.easeOut(duration: 0.15), value: follows)
                .onAppear { scrollToLatest(proxy, animated: false) }
                .onChange(of: entries.count) { _, _ in
                    if follows { scrollToLatest(proxy, animated: true) }
                }
            }
        }
    }

    private func updateFollow(_ frame: CGRect, _ proxy: ScrollViewProxy) {
        let inset: CGFloat = follows ? 0 : 44
        let distance = frame.maxY - inset - viewportHeight
        let scrolled = abs(frame.minY - lastMinY) > 0.5
        lastMinY = frame.minY
        if distance < Self.nearBottom {
            if !follows {
                if distance > 1 {
                    scrollToLatest(proxy, animated: true)
                } else {
                    follows = true
                }
            }
            if distance <= 1 { programmaticScroll = false }
        } else if scrolled && !programmaticScroll && follows {
            follows = false
        }
    }

    private func scrollToLatest(_ proxy: ScrollViewProxy, animated: Bool) {
        follows = true
        programmaticScroll = true
        if animated {
            withAnimation(.easeOut(duration: 0.3)) { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
        } else {
            proxy.scrollTo(Self.bottomID, anchor: .bottom)
        }
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            programmaticScroll = false
        }
    }
}
