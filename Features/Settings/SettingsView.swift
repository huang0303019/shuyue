import SwiftUI

/// 设置 —— 阅读偏好、Legado 兼容说明与开源许可。
struct SettingsView: View {
    let onMenu: () -> Void

    var body: some View {
        SYScreen(title: "设置", subtitle: "外观与阅读偏好", onMenu: onMenu) {
            SYSectionHeader(title: "外观")
            SYRowCard(title: "主题", subtitle: "跟随系统：宣纸 / 夜墨 / 护眼", systemImage: "circle.lefthalf.filled")
            SYRowCard(title: "字体与排版", subtitle: "衬线标题 · 系统正文字体", systemImage: "textformat")

            SYSectionHeader(title: "书源")
            SYRowCard(title: "Legado 兼容", subtitle: "支持 @json / @css / @XPath / @js 规则", systemImage: "arrow.triangle.2.circlepath")

            SYSectionHeader(title: "关于")
            SYRowCard(title: "开源许可", subtitle: "Mozilla Public License 2.0", systemImage: "doc.text")
            SYRowCard(title: "版本", subtitle: "0.1.0", systemImage: "info.circle")

            Text("书悦 ShuYue 为全新原创实现，与「閱讀」「Legado」等项目无从属关系；书源内容由使用者自行导入并自负其责。")
                .font(SYFont.micro)
                .foregroundStyle(SYPalette.inkTertiary)
                .padding(.top, SYMetric.gapS)
        }
    }
}

#if DEBUG
struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView(onMenu: {})
    }
}
#endif