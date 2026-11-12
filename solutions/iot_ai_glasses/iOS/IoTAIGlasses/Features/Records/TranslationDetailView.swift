import SwiftUI

struct TranslationDetailView: View {
    let recordID: UUID

    @Environment(AppState.self) private var state
    @Environment(AppRouter.self) private var router

    var body: some View {
        if let record = state.records.first(where: { $0.id == recordID }), record.kind == .translation {
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
            PageHeader(title: record.translationHeading, subtitle: record.translationSubtitle(), backLabel: "返回", onBack: router.pop) {
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
                    let lines = record.transcript ?? []
                    if lines.isEmpty {
                        Text("没有识别到文字")
                            .font(AppFont.footnote)
                            .foregroundStyle(Palette.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 28)
                    } else {
                        ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                            SentenceCard(index: index, line: line, isLatest: false)
                        }
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

    private func exportText(_ record: Record) -> String {
        var lines = ["\(record.title)", record.subtitle(), "", "—— 双语对照 ——"]
        for line in record.transcript ?? [] {
            lines.append("\(line.translated)")
            lines.append(line.original)
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}
