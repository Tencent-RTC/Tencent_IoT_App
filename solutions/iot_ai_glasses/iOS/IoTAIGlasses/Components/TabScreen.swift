import SwiftUI

struct TabScreen<Content: View>: View {
    var spacing: CGFloat = Spacing.section
    @ViewBuilder let content: Content

    @Environment(AppRouter.self) private var router

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: spacing) {
                content
            }
            .padding(.horizontal, Spacing.screenHorizontal)
            .padding(.top, Spacing.screenTop)
            .padding(.bottom, Spacing.screenBottom)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .safeAreaPadding(.bottom, router.showsTabBar ? BottomTabBar.reservedHeight : 0)
        .scrollIndicators(.hidden)
        .background(AppBackdrop().ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }
}

struct ScreenTitle<Trailing: View>: View {
    let title: String
    @ViewBuilder let trailing: Trailing

    init(_ title: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack {
            Text(title)
                .font(AppFont.pageTitle)
                .tracking(-0.5)
                .foregroundStyle(Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            trailing
        }
        .frame(height: 44)
    }
}

extension ScreenTitle where Trailing == EmptyView {
    init(_ title: String) {
        self.init(title) { EmptyView() }
    }
}
