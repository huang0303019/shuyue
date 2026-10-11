import SwiftUI

/// 搜索 —— 跨书源并发搜索并汇总结果。
struct SearchView: View {
    let onMenu: () -> Void

    @State private var query: String = ""

    var body: some View {
        SYScreen(title: "搜索", subtitle: "跨书源搜书", onMenu: onMenu) {
            HStack(spacing: SYMetric.gapS) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(SYPalette.inkTertiary)

                TextField("书名 / 作者 / 关键词", text: $query)
                    .font(SYFont.body)
                    .foregroundStyle(SYPalette.ink)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)

                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(SYPalette.inkTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, SYMetric.gapM)
            .frame(height: 46)
            .background(SYPalette.surface, in: RoundedRectangle(cornerRadius: SYMetric.radiusControl, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SYMetric.radiusControl, style: .continuous)
                    .stroke(SYPalette.border, lineWidth: 0.8)
            )

            SYEmptyState(
                systemImage: "magnifyingglass",
                title: "输入关键词开始搜索",
                message: "书悦会同时向已启用的书源发起搜索，并把结果按来源汇总。"
            )
        }
    }
}

#if DEBUG
struct SearchView_Previews: PreviewProvider {
    static var previews: some View {
        SearchView(onMenu: {})
    }
}
#endif