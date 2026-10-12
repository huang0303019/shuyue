import SwiftUI

/// 书源实跑校验面板：实时展示 搜索/发现/详情/目录/正文 五阶段进展与整体结论。
@MainActor
struct SourceCheckSheet: View {
    @ObservedObject var checker: SYHealthChecker
    let onFinished: (SYSourceValidationSummary?) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: SYMetric.gapL) {
                headerCard

                VStack(spacing: SYMetric.gapS) {
                    ForEach(SYValidationStage.allCases) { stage in
                        stageRow(stage, outcome: checker.item?.outcome(stage) ?? SYStageOutcome())
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(SYMetric.gapXL)
            .background(SYPalette.paper.ignoresSafeArea())
            .navigationTitle("校验书源")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .onAppear { notifyIfFinished() }
            .onChange(of: checker.isFinished) { _ in notifyIfFinished() }
        }
        .presentationDetents([.medium, .large])
        .onDisappear {
            checker.cancel()
        }
    }

    // MARK: - 头部总结

    private var headerCard: some View {
        let item = checker.item
        return VStack(alignment: .leading, spacing: SYMetric.gapS) {
            HStack(spacing: SYMetric.gapS) {
                Image(systemName: headerIcon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(headerColor)
                    .frame(width: 38, height: 38)
                    .background(headerColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 11, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(item?.source.bookSourceName ?? "书源")
                        .font(SYFont.body.weight(.semibold))
                        .foregroundStyle(SYPalette.ink)
                    Text(headerSubtitle)
                        .font(SYFont.caption)
                        .foregroundStyle(SYPalette.inkTertiary)
                }

                Spacer(minLength: 0)

                if checker.isRunning {
                    ProgressView()
                        .controlSize(.small)
                        .tint(SYPalette.accent)
                } else if let failure = item?.failureCategory {
                    Text(failure.title)
                        .font(SYFont.micro.weight(.semibold))
                        .foregroundStyle(headerColor)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(headerColor.opacity(0.12), in: Capsule())
                } else {
                    Text("通过")
                        .font(SYFont.micro.weight(.semibold))
                        .foregroundStyle(headerColor)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(headerColor.opacity(0.12), in: Capsule())
                }
            }

            if let item, item.isFinished {
                Text(headerTimingText(item))
                    .font(SYFont.micro)
                    .foregroundStyle(SYPalette.inkTertiary)
            } else {
                Text("正在实跑网络请求，请稍候…")
                    .font(SYFont.micro)
                    .foregroundStyle(SYPalette.inkTertiary)
            }
        }
        .padding(SYMetric.gapL)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SYPalette.surface, in: RoundedRectangle(cornerRadius: SYMetric.radiusCard, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SYMetric.radiusCard, style: .continuous)
                .stroke(SYPalette.border, lineWidth: 0.8)
        )
    }

    private var headerIcon: String {
        if checker.isRunning { return "arrow.triangle.2.circlepath" }
        if let health = checker.item?.health {
            switch health {
            case .passed: return "checkmark.shield"
            case .contentError: return "exclamationmark.triangle"
            case .fetchError: return "xmark.shield"
            }
        }
        return "checkmark.shield"
    }

    private var headerColor: Color {
        if checker.isRunning { return SYPalette.accent }
        if let health = checker.item?.health {
            switch health {
            case .passed: return SYPalette.accent
            case .contentError: return SYPalette.gold
            case .fetchError: return SYPalette.danger
            }
        }
        return SYPalette.inkTertiary
    }

    private var headerSubtitle: String {
        let item = checker.item
        if let item, item.isFinished {
            return item.overallPass ? "五阶段均通过" : "发现 \(item.failureCategory?.title ?? "问题")"
        }
        return item?.source.bookSourceUrl ?? ""
    }

    private func headerTimingText(_ item: SYCheckItem) -> String {
        let ms = item.responseTime
        if ms >= 1000 {
            return String(format: "总耗时 %.1f 秒", Double(ms) / 1000.0)
        }
        return "总耗时 \(ms) 毫秒"
    }

    // MARK: - 阶段行

    private func stageRow(_ stage: SYValidationStage, outcome: SYStageOutcome) -> some View {
        HStack(spacing: SYMetric.gapM) {
            Image(systemName: stage.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SYPalette.inkSecondary)
                .frame(width: 30, height: 30)
                .background(SYPalette.surfaceAlt, in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(stage.title)
                    .font(SYFont.callout.weight(.medium))
                    .foregroundStyle(SYPalette.ink)
                Text(stageSummary(outcome))
                    .font(SYFont.micro)
                    .foregroundStyle(SYPalette.inkTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: SYMetric.gapS)

            statusBadge(outcome.status)
        }
        .padding(.horizontal, SYMetric.gapM)
        .padding(.vertical, SYMetric.gapS)
        .background(SYPalette.surface, in: RoundedRectangle(cornerRadius: SYMetric.radiusControl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SYMetric.radiusControl, style: .continuous)
                .stroke(SYPalette.border, lineWidth: 0.8)
        )
    }

    private func stageSummary(_ outcome: SYStageOutcome) -> String {
        switch outcome.status {
        case .pending: return "等待中"
        case .running: return outcome.summary.isEmpty ? "正在执行…" : outcome.summary
        case .pass: return outcome.summary.isEmpty ? "通过" : outcome.summary
        case .fail: return outcome.summary.isEmpty ? "失败" : outcome.summary
        case .skipped: return outcome.summary == "—" ? "已跳过" : outcome.summary
        }
    }

    @ViewBuilder
    private func statusBadge(_ status: SYStageStatus) -> some View {
        switch status {
        case .pending:
            Text("等待")
                .font(SYFont.micro.weight(.medium))
                .foregroundStyle(SYPalette.inkTertiary)
        case .running:
            HStack(spacing: 5) {
                ProgressView()
                    .controlSize(.mini)
                    .tint(SYPalette.accent)
                Text("进行中")
                    .font(SYFont.micro.weight(.medium))
                    .foregroundStyle(SYPalette.accent)
            }
        case .pass:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(SYPalette.accent)
        case .fail:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(SYPalette.danger)
        case .skipped:
            Text("跳过")
                .font(SYFont.micro.weight(.medium))
                .foregroundStyle(SYPalette.inkTertiary)
        }
    }

    private func notifyIfFinished() {
        guard checker.isFinished,
              let item = checker.item,
              let health = item.health else { return }
        onFinished(SYSourceValidationSummary(health: health, responseMs: item.responseTime))
    }
}