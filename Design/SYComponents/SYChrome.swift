import SwiftUI

// MARK: - 顶部应用栏

/// 书悦的顶部应用栏：左抽屉按钮 + 衬线大标题 + 右侧自定义动作。
/// 取代「閱讀」/墨悦的底部标签栏。
struct SYTopBar<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    var onMenu: () -> Void
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: SYMetric.gapM) {
            Button(action: onMenu) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(SYPalette.ink)
                    .frame(width: 38, height: 38)
                    .background(SYPalette.surfaceAlt, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("打开导航")

            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(SYFont.appTitle)
                    .foregroundStyle(SYPalette.ink)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(SYFont.micro)
                        .foregroundStyle(SYPalette.inkTertiary)
                }
            }

            Spacer(minLength: SYMetric.gapS)
            trailing()
        }
        .padding(.horizontal, SYMetric.pagePadding)
        .padding(.vertical, SYMetric.gapS)
        .frame(minHeight: SYMetric.controlHeight + SYMetric.gapS * 2)
        .background(SYPalette.paper)
    }
}

extension SYTopBar where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, onMenu: @escaping () -> Void) {
        self.init(title: title, subtitle: subtitle, onMenu: onMenu, trailing: { EmptyView() })
    }
}

// MARK: - 胶囊页签

/// 顶部胶囊分组页签，用于书架分组、书源分组等处切换。
struct SYCapsuleTabs<Item: Hashable>: View {
    let items: [Item]
    let label: (Item) -> String
    @Binding var selection: Item

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: SYMetric.gapS) {
                ForEach(items, id: \.self) { item in
                    let active = item == selection
                    Button {
                        withAnimation(.easeOut(duration: 0.18)) { selection = item }
                    } label: {
                        Text(label(item))
                            .font(SYFont.callout.weight(active ? .semibold : .regular))
                            .foregroundStyle(active ? Color.white : SYPalette.inkSecondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(active ? SYPalette.accent : SYPalette.surfaceAlt, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, SYMetric.pagePadding)
            .padding(.vertical, SYMetric.gapS)
        }
    }
}

// MARK: - 悬浮操作球

struct SYFloatingAction: View {
    let systemImage: String
    var accessibility: String = "新建"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(SYPalette.accent, in: Circle())
        }
        .buttonStyle(.plain)
        .syFloatShadow()
        .accessibilityLabel(accessibility)
    }
}

// MARK: - 按钮

struct SYButton: View {
    enum Kind { case primary, secondary, quiet }

    let title: String
    var systemImage: String? = nil
    var kind: Kind = .primary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .font(SYFont.callout.weight(.semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, SYMetric.gapL)
            .frame(height: SYMetric.controlHeight)
            .frame(maxWidth: kind == .quiet ? nil : .infinity)
            .background(
                RoundedRectangle(cornerRadius: SYMetric.radiusControl, style: .continuous)
                    .fill(background)
            )
            .overlay(
                RoundedRectangle(cornerRadius: SYMetric.radiusControl, style: .continuous)
                    .stroke(SYPalette.border, lineWidth: kind == .secondary ? 0.8 : 0)
            )
        }
        .buttonStyle(.plain)
    }

    private var foreground: Color {
        kind == .primary ? .white : SYPalette.ink
    }

    private var background: Color {
        switch kind {
        case .primary: return SYPalette.accent
        case .secondary: return SYPalette.surface
        case .quiet: return .clear
        }
    }
}

// MARK: - 标签

struct SYChip: View {
    let text: String
    var tint: Color = SYPalette.accent

    var body: some View {
        Text(text)
            .font(SYFont.micro.weight(.medium))
            .foregroundStyle(tint)
            .padding(.horizontal, SYMetric.gapS)
            .padding(.vertical, 3)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

/// 启用 / 停用胶囊（避免出现「啟」「停」这类单字繁体泄漏）。
struct SYPillToggle: View {
    let isOn: Bool
    var onLabel: String = "启用"
    var offLabel: String = "停用"

    var body: some View {
        Text(isOn ? onLabel : offLabel)
            .font(SYFont.micro.weight(.semibold))
            .foregroundStyle(isOn ? Color.white : SYPalette.inkTertiary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(isOn ? SYPalette.accent : SYPalette.surfaceAlt, in: Capsule())
    }
}