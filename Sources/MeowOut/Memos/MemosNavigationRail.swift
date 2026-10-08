import SwiftUI

struct MemosNavigationRail: View {
    @Binding var selectedPage: MemosRootPage

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
                .frame(height: 28)

            ForEach(MemosRootPage.allCases) { page in
                Button {
                    selectedPage = page
                } label: {
                    Image(systemName: page.systemImage)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(selectedPage == page ? Color.accentColor : Color.secondary)
                        .frame(width: 44, height: 44)
                        .background(selectedPage == page ? Color.accentColor.opacity(0.16) : Color.clear)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help(page.title)
                .accessibilityLabel(page.title)
                .accessibilityValue(selectedPage == page ? "已选择" : "未选择")
            }

            Spacer()
        }
        // 宽度必须一并撑满：父视图给的列宽是 72，而 VStack 的固有宽度只有图标按钮的 44，
        // 只约束高度的话背景只会画中间 44pt，两侧各留一条底色窄边，看起来像被截断的窄条。
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
    }
}
