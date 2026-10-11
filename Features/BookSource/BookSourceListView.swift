import SwiftUI

/// 书源管理 —— 导入 / 导出 / 校验 / 调试 Legado 书源。
struct BookSourceListView: View {
    let onMenu: () -> Void

    private let sourceCount = 0
    private let enabledCount = 0

    var body: some View {
        SYScreen(title: "书源", subtitle: "共 \(sourceCount) 个 · 启用 \(enabledCount)", onMenu: onMenu) {
            HStack(spacing: SYMetric.gapM) {
                statCard(title: "书源总数", value: "\(sourceCount)", image: "square.stack.3d.up", tint: SYPalette.accent)
                statCard(title: "已启用", value: "\(enabledCount)", image: "checkmark.seal", tint: SYPalette.gold)
            }

            SYEmptyState(
                systemImage: "square.stack.3d.up",
                title: "还没有书源",
                message: "支持导入标准 Legado JSON 书源数组，可与「阅读」等客户端互通。"
            )
        }
    }

    private func statCard(title: String, value: String, image: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: SYMetric.gapS) {
            Image(systemName: image)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text(value)
                .font(SYFont.serif(24, .bold))
                .foregroundStyle(SYPalette.ink)
            Text(title)
                .font(SYFont.micro)
                .foregroundStyle(SYPalette.inkTertiary)
        }
        .padding(SYMetric.gapL)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SYPalette.surface, in: RoundedRectangle(cornerRadius: SYMetric.radiusCard, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SYMetric.radiusCard, style: .continuous)
                .stroke(tint.opacity(0.16), lineWidth: 0.8)
        )
    }
}

#if DEBUG
struct BookSourceListView_Previews: PreviewProvider {
    static var previews: some View {
        BookSourceListView(onMenu: {})
    }
}
#endif