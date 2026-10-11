import SwiftUI

// MARK: - 书籍封面

/// 书籍封面：优先加载远程 coverUrl，失败或缺失时退化为「首字 + 书脊」本地书封，
/// 与书架的书脊卡片保持同一视觉语言。
struct SYCoverView: View {
    let book: SYBook
    var width: CGFloat = 104
    var height: CGFloat = 148
    var cornerRadius: CGFloat = 12
    var tint: Color = SYPalette.accent

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(tint.opacity(0.13))

            if let url = coverURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .clipped()
                    case .failure:
                        placeholder
                    case .empty:
                        ZStack {
                            placeholder
                            ProgressView()
                                .tint(SYPalette.inkTertiary)
                        }
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(SYPalette.border, lineWidth: 0.8)
        )
    }

    private var coverURL: URL? {
        guard let raw = book.coverUrl?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        return URL(string: raw)
    }

    private var placeholder: some View {
        ZStack {
            Text(String(book.name.prefix(1)))
                .font(SYFont.serif(44, .bold))
                .foregroundStyle(tint)
                .padding(.horizontal, SYMetric.gapS)

            HStack {
                Capsule()
                    .fill(tint)
                    .frame(width: 4)
                    .padding(.vertical, 16)
                    .padding(.leading, 9)
                Spacer()
            }
        }
    }
}