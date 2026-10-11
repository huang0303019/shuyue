import SwiftUI

/// 阅读历史 —— 按时间倒序展示最近读过的书。
struct HistoryView: View {
    let onMenu: () -> Void

    var body: some View {
        SYScreen(title: "阅读历史", subtitle: "最近读过的书", onMenu: onMenu) {
            SYEmptyState(
                systemImage: "clock.arrow.circlepath",
                title: "还没有阅读记录",
                message: "开始阅读后，这里会按时间倒序记录你的阅读轨迹。"
            )
        }
    }
}

#if DEBUG
struct HistoryView_Previews: PreviewProvider {
    static var previews: some View {
        HistoryView(onMenu: {})
    }
}
#endif