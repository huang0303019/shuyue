import SwiftUI

/// 左侧抽屉导航：书悦的唯一主导航入口。
struct SYDrawer: View {
    @ObservedObject var state: SYAppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Rectangle()
                .fill(SYPalette.border)
                .frame(height: 0.8)
                .padding(.horizontal, SYMetric.gapL)

            ScrollView {
                VStack(spacing: SYMetric.gapXS) {
                    ForEach(SYSection.allCases) { section in
                        row(for: section)
                    }
                }
                .padding(.vertical, SYMetric.gapM)
                .padding(.horizontal, SYMetric.gapS)
            }

            footer
        }
        .frame(width: SYMetric.drawerWidth)
        .background(SYPalette.surface.ignoresSafeArea())
        .syFloatShadow()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("书悦")
                .font(SYFont.serif(26, .bold))
                .foregroundStyle(SYPalette.ink)
            Text("开源阅读 · Legado 书源兼容")
                .font(SYFont.micro)
                .foregroundStyle(SYPalette.inkTertiary)
        }
        .padding(.horizontal, SYMetric.gapL)
        .padding(.top, SYMetric.gapHuge)
        .padding(.bottom, SYMetric.gapL)
    }

    private func row(for section: SYSection) -> some View {
        let selected = state.section == section
        return Button {
            withAnimation(.easeOut(duration: 0.2)) {
                state.present(section)
            }
        } label: {
            HStack(spacing: SYMetric.gapM) {
                Image(systemName: section.systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(selected ? Color.white : SYPalette.accent)
                    .frame(width: 34, height: 34)
                    .background(
                        selected ? SYPalette.accent : SYPalette.accentSoft,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 1) {
                    Text(section.title)
                        .font(SYFont.body.weight(selected ? .semibold : .regular))
                        .foregroundStyle(SYPalette.ink)
                    Text(section.caption)
                        .font(SYFont.micro)
                        .foregroundStyle(SYPalette.inkTertiary)
                }

                Spacer(minLength: 0)

                if selected {
                    Circle()
                        .fill(SYPalette.gold)
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, SYMetric.gapS)
            .padding(.vertical, SYMetric.gapS)
            .background(
                selected ? SYPalette.accentSoft : Color.clear,
                in: RoundedRectangle(cornerRadius: SYMetric.radiusControl, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: SYMetric.gapXS) {
            Rectangle()
                .fill(SYPalette.border)
                .frame(height: 0.8)

            Text("书悦 ShuYue · MPL-2.0")
                .font(SYFont.micro)
                .foregroundStyle(SYPalette.inkTertiary)
            Text("与「閱讀」「Legado」无从属关系")
                .font(SYFont.micro)
                .foregroundStyle(SYPalette.inkTertiary)
        }
        .padding(.horizontal, SYMetric.gapL)
        .padding(.vertical, SYMetric.gapL)
    }
}