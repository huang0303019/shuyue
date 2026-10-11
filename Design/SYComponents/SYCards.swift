import SwiftUI

// MARK: - 通用卡片

struct SYCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(SYMetric.gapL)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SYPalette.surface, in: RoundedRectangle(cornerRadius: SYMetric.radiusCard, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SYMetric.radiusCard, style: .continuous)
                    .stroke(SYPalette.border, lineWidth: 0.8)
            )
            .syCardShadow()
    }
}

// MARK: - 行卡片

struct SYRowCard<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    var systemImage: String? = nil
    var accent: Color = SYPalette.accent
    var onTap: (() -> Void)? = nil
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        Group {
            if let onTap {
                Button(action: onTap) { rowContent }
                    .buttonStyle(.plain)
            } else {
                rowContent
            }
        }
    }

    private var rowContent: some View {
        HStack(spacing: SYMetric.gapM) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 38, height: 38)
                    .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(SYFont.body.weight(.medium))
                    .foregroundStyle(SYPalette.ink)
                    .lineLimit(1)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(SYFont.caption)
                        .foregroundStyle(SYPalette.inkTertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: SYMetric.gapS)
            trailing()
        }
        .padding(.horizontal, SYMetric.gapL)
        .padding(.vertical, SYMetric.gapM)
        .background(SYPalette.surface, in: RoundedRectangle(cornerRadius: SYMetric.radiusCard, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SYMetric.radiusCard, style: .continuous)
                .stroke(SYPalette.border, lineWidth: 0.8)
        )
    }
}

extension SYRowCard where Trailing == EmptyView {
    init(
        title: String,
        subtitle: String? = nil,
        systemImage: String? = nil,
        accent: Color = SYPalette.accent,
        onTap: (() -> Void)? = nil
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            systemImage: systemImage,
            accent: accent,
            onTap: onTap,
            trailing: { EmptyView() }
        )
    }
}

// MARK: - 书脊卡片

/// 书架的主视觉单元：左侧书脊色条 + 衬线首字封面 + 底部进度「书签线」。
struct SYSpineCard: View {
    let title: String
    var author: String? = nil
    var progress: Double = 0
    var tint: Color = SYPalette.accent

    var body: some View {
        VStack(alignment: .leading, spacing: SYMetric.gapS) {
            ZStack {
                RoundedRectangle(cornerRadius: SYMetric.radiusCard, style: .continuous)
                    .fill(tint.opacity(0.13))
                Text(String(title.prefix(1)))
                    .font(SYFont.serif(36, .bold))
                    .foregroundStyle(tint)
            }
            .frame(height: 124)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(tint)
                    .frame(width: 4)
                    .padding(.vertical, 14)
                    .padding(.leading, 9)
            }
            .overlay(
                RoundedRectangle(cornerRadius: SYMetric.radiusCard, style: .continuous)
                    .stroke(SYPalette.border, lineWidth: 0.8)
            )

            Text(title)
                .font(SYFont.bookTitle)
                .foregroundStyle(SYPalette.ink)
                .lineLimit(1)

            if let author, !author.isEmpty {
                Text(author)
                    .font(SYFont.micro)
                    .foregroundStyle(SYPalette.inkTertiary)
                    .lineLimit(1)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(SYPalette.border)
                    Capsule()
                        .fill(tint)
                        .frame(width: max(0, min(1, progress)) * geo.size.width)
                }
            }
            .frame(height: 3)
        }
        .contentShape(Rectangle())
    }
}

// MARK: - 区块标题

struct SYSectionHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: SYMetric.gapS) {
            Text(title)
                .font(SYFont.sectionTitle)
                .foregroundStyle(SYPalette.ink)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(SYFont.caption)
                    .foregroundStyle(SYPalette.inkTertiary)
            }
            Spacer(minLength: 0)
        }
    }
}