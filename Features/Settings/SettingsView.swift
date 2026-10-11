import SwiftUI

/// 设置 —— 阅读偏好接入全局设置，另含 Legado 兼容说明与开源许可。
@MainActor
struct SettingsView: View {
    let onMenu: () -> Void

    @EnvironmentObject private var state: SYAppState

    var body: some View {
        SYScreen(title: "设置", subtitle: "外观与阅读偏好", onMenu: onMenu) {
            SYSectionHeader(title: "阅读外观")

            SYCard {
                VStack(alignment: .leading, spacing: SYMetric.gapL) {
                    Text("主题")
                        .font(SYFont.caption)
                        .foregroundStyle(SYPalette.inkSecondary)

                    HStack(spacing: SYMetric.gapXL) {
                        ForEach(ReaderTheme.allCases) { item in
                            themeButton(item)
                        }
                        Spacer(minLength: 0)
                    }

                    divider

                    HStack(spacing: SYMetric.gapM) {
                        Text("A")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(SYPalette.inkTertiary)
                        Slider(value: fontSizeBinding, in: 13...30, step: 1)
                            .tint(SYPalette.accent)
                        Text("\(Int(state.settings.fontSize))")
                            .font(SYFont.caption)
                            .foregroundStyle(SYPalette.inkSecondary)
                            .frame(width: 24, alignment: .trailing)
                    }

                    HStack(spacing: SYMetric.gapM) {
                        Image(systemName: "arrow.up.and.down")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(SYPalette.inkTertiary)
                        Slider(value: lineSpacingBinding, in: 2...20, step: 1)
                            .tint(SYPalette.accent)
                        Text("\(Int(state.settings.lineSpacing))")
                            .font(SYFont.caption)
                            .foregroundStyle(SYPalette.inkSecondary)
                            .frame(width: 24, alignment: .trailing)
                    }

                    divider

                    Toggle(isOn: serifBinding) {
                        Text("衬线字体")
                            .font(SYFont.callout)
                            .foregroundStyle(SYPalette.ink)
                    }
                    .tint(SYPalette.accent)
                }
            }

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

    private var divider: some View {
        Rectangle()
            .fill(SYPalette.border)
            .frame(height: 0.8)
    }

    private func themeButton(_ item: ReaderTheme) -> some View {
        let selected = item == state.settings.theme
        return Button {
            withAnimation(.easeOut(duration: 0.18)) { state.setTheme(item) }
        } label: {
            VStack(spacing: 6) {
                Circle()
                    .fill(item.background)
                    .frame(width: 46, height: 46)
                    .overlay(
                        Circle()
                            .stroke(selected ? SYPalette.accent : SYPalette.border, lineWidth: selected ? 3 : 1)
                    )
                Text(item.title)
                    .font(SYFont.micro.weight(selected ? .semibold : .regular))
                    .foregroundStyle(SYPalette.ink)
            }
        }
        .buttonStyle(.plain)
    }

    private var fontSizeBinding: Binding<Double> {
        Binding(
            get: { state.settings.fontSize },
            set: { state.setFontSize($0) }
        )
    }

    private var lineSpacingBinding: Binding<Double> {
        Binding(
            get: { state.settings.lineSpacing },
            set: { state.setLineSpacing($0) }
        )
    }

    private var serifBinding: Binding<Bool> {
        Binding(
            get: { state.settings.useSerif },
            set: { state.setUseSerif($0) }
        )
    }
}