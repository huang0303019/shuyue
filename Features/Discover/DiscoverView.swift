import SwiftUI

/// 发现 —— 按书源抓取推荐与分类，横向卡片流。
struct DiscoverView: View {
    let onMenu: () -> Void

    var body: some View {
        SYScreen(title: "发现", subtitle: "按书源逛逛", onMenu: onMenu) {
            SYEmptyState(
                systemImage: "sparkles",
                title: "暂无可浏览的内容",
                message: "导入书源后，这里会按书源的发现页规则抓取分类与推荐。",
                actionTitle: nil
            )
        }
    }
}

#if DEBUG
struct DiscoverView_Previews: PreviewProvider {
    static var previews: some View {
        DiscoverView(onMenu: {})
    }
}
#endif