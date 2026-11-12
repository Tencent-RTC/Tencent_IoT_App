import SwiftUI

struct AudioWave: View {
    let isActive: Bool
    var speed: Double = 1

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let heights: [CGFloat] = [9, 18, 12, 25, 15, 29, 20, 12, 24, 16, 8, 20, 29, 16, 23, 12, 7]

    var body: some View {
        TimelineView(.animation(paused: !isActive || reduceMotion)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 4) {
                ForEach(Self.heights.indices, id: \.self) { index in
                    Capsule()
                        .fill(Palette.accent)
                        .frame(width: 2, height: Self.heights[index] * scale(index, time))
                }
            }
            .frame(height: 32)
        }
        .opacity(isActive ? 1 : 0.35)
        .accessibilityHidden(true)
    }

    private func scale(_ index: Int, _ time: TimeInterval) -> CGFloat {
        guard isActive, !reduceMotion else { return 1 }
        let period = (0.9 + Double(index % 5) * 0.12) * speed
        let phase = Double(index) * 0.37
        let wave = (sin((time / period) * .pi * 2 + phase) + 1) / 2
        return 0.45 + 0.55 * wave
    }
}
