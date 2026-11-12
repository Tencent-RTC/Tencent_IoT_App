import SwiftUI

struct FlowScreen<Header: View, Content: View, Footer: View>: View {
    var spacing: CGFloat = 28
    var background: Color?
    @ViewBuilder let header: Header
    @ViewBuilder let content: Content
    @ViewBuilder let footer: Footer

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                header
                    .padding(.top, Spacing.screenTop)
                    .padding(.bottom, spacing)
                content
                    .frame(maxHeight: .infinity, alignment: .top)
                footer
                    .padding(.bottom, proxy.safeAreaInsets.bottom > 0 ? 8 : 20)
            }
            .padding(.horizontal, Spacing.screenHorizontal)
        }
        .background {
            if let background {
                background.ignoresSafeArea()
            } else {
                AppBackdrop().ignoresSafeArea()
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}
