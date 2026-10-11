import SwiftUI

// MARK: - 空状态

struct SYEmptyState: View {
    let systemImage: String
    let title: String
    var message: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: SYMetric.gapM) {
            Image(systemName: systemImage)
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(SYPalette.accent)
                .frame(width: 84, height: 84)
                .background(SYPalette.accentSoft, in: Circle())

            Text(title)
                .font(SYFont.sectionTitle)
                .foregroundStyle(SYPalette.ink)
                .multilineTextAlignment(.center)

            if let message, !message.isEmpty {
                Text(message)
                    .font(SYFont.callout)
                    .foregroundStyle(SYPalette.inkSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let actionTitle, let action {
                SYButton(title: actionTitle, kind: .secondary, action: action)
                    .frame(maxWidth: 240)
                    .padding(.top, SYMetric.gapXS)
            }
        }
        .padding(SYMetric.gapXXL)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 进度环

struct SYProgressRing: View {
    var progress: Double = 0
    var size: CGFloat = 22
    var lineWidth: CGFloat = 3
    var tint: Color = SYPalette.accent

    var body: some View {
        ZStack {
            Circle().stroke(SYPalette.border, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0, min(1, progress)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
    }
}

// MARK: - 页面骨架

/// 统一页面骨架：顶部应用栏 + 可滚动内容区。所有功能页共用，避免底部标签栏。
struct SYScreen<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    var onMenu: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            SYTopBar(title: title, subtitle: subtitle, onMenu: onMenu)

            ScrollView {
                VStack(alignment: .leading, spacing: SYMetric.gapL) {
                    content()
                }
                .padding(.horizontal, SYMetric.pagePadding)
                .padding(.bottom, SYMetric.gapHuge * 2)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(SYPalette.paper.ignoresSafeArea())
    }
}