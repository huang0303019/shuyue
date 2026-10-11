import SwiftUI

/// 书房 —— 书悦的核心页面：分组胶囊页签 + 书脊卡片书架。
struct BookshelfView: View {
    let onMenu: () -> Void

    @State private var group: String = "全部"
    private let groups = ["全部", "在读", "想读", "已读"]

    var body: some View {
        SYScreen(title: "书房", subtitle: "\(groups.count) 个分组", onMenu: onMenu) {
            SYCapsuleTabs(items: groups, label: { $0 }, selection: $group)
                .padding(.horizontal, -SYMetric.pagePadding)

            SYEmptyState(
                systemImage: "books.vertical",
                title: "书架还空着",
                message: "去「书源」导入 Legado 书源，搜索想读的书并加入书架，它们会以书脊卡片排在这里。"
            )
        }
    }
}

#if DEBUG
struct BookshelfView_Previews: PreviewProvider {
    static var previews: some View {
        BookshelfView(onMenu: {})
    }
}
#endif