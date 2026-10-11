import SwiftUI

// MARK: - 书籍行卡片

/// 书籍行卡片 —— 搜索 / 发现 / 历史共用：小封面 + 书名 + 来源与进度。
struct SYBookRow: View {
    let book: SYBook
    var subtitle: String? = nil
    var progress: Double? = nil
    var tint: Color = SYPalette.accent
    var onTap: (() -> Void)? = nil

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
            SYCoverView(book: book, width: 52, height: 72, cornerRadius: 8, tint: tint)

            VStack(alignment: .leading, spacing: 3) {
                Text(book.name)
                    .font(SYFont.body.weight(.medium))
                    .foregroundStyle(SYPalette.ink)
                    .lineLimit(1)

                if let author = book.author, !author.isEmpty {
                    Text(author)
                        .font(SYFont.caption)
                        .foregroundStyle(SYPalette.inkSecondary)
                        .lineLimit(1)
                }

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(SYFont.micro)
                        .foregroundStyle(SYPalette.inkTertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: SYMetric.gapS)

            if let progress {
                SYProgressRing(progress: progress, size: 30, lineWidth: 3, tint: tint)
            } else {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SYPalette.inkTertiary)
            }
        }
        .padding(.horizontal, SYMetric.gapM)
        .padding(.vertical, SYMetric.gapM)
        .background(SYPalette.surface, in: RoundedRectangle(cornerRadius: SYMetric.radiusCard, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SYMetric.radiusCard, style: .continuous)
                .stroke(SYPalette.border, lineWidth: 0.8)
        )
    }
}