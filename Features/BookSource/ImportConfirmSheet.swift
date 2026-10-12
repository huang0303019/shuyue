import SwiftUI

/// 导入确认清单：先展示拆包结果（新增 / 更新 / 已有）、目标分组与勾选，
/// 用户确认后才把选中的书源写入本地库。
@MainActor
struct ImportConfirmSheet: View {
    @EnvironmentObject private var state: SYAppState
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var plan: SYImportPlan
    /// 确认完成后把结果摘要交还给打开的导入面板。
    var onDone: (SYImportSummary) -> Void

    // 导入设置（本次会话内有效）
    @State private var groupName = ""
    @State private var addsToExistingGroups = false
    @State private var keepName = false
    @State private var keepGroup = false
    @State private var keepEnable = false
    @State private var keepCustomOrder = true

    var body: some View {
        NavigationStack {
            listContent
                .background(SYPalette.paper.ignoresSafeArea())
                .navigationTitle("确认导入")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
        }
        .presentationDetents([.large])
    }

    // MARK: 列表

    @ViewBuilder
    private var listContent: some View {
        if plan.isEmpty {
            VStack(spacing: SYMetric.gapM) {
                Image(systemName: "tray")
                    .font(.system(size: 40))
                    .foregroundStyle(SYPalette.inkTertiary)
                Text("没有可导入的内容")
                    .font(SYFont.callout)
                    .foregroundStyle(SYPalette.inkSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                optionsSection
                entriesSection
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
    }

    /// 分组与保留策略 —— 只影响「确认写入」这一步，不写入任何持久化选项。
    private var optionsSection: some View {
        Section {
            HStack(spacing: SYMetric.gapM) {
                Image(systemName: "folder.badge.plus")
                    .foregroundStyle(SYPalette.inkTertiary)
                TextField("导入到分组（留空不改动）", text: $groupName)
                    .font(SYFont.body)
                    .foregroundStyle(SYPalette.ink)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            Toggle("追加到已有分组", isOn: $addsToExistingGroups)
                .font(SYFont.body)
                .tint(SYPalette.accent)
        } header: {
            Text("导入设置")
                .font(SYFont.caption)
                .foregroundStyle(SYPalette.inkSecondary)
        } footer: {
            Text("更新已有书源时会按勾选保留本地设置，避免被来源 JSON 覆盖。")
                .font(SYFont.micro)
                .foregroundStyle(SYPalette.inkTertiary)
        }

        Section {
            Toggle("保留本地排序", isOn: $keepCustomOrder)
                .font(SYFont.body)
                .tint(SYPalette.accent)
            Toggle("保留本地名称", isOn: $keepName)
                .font(SYFont.body)
                .tint(SYPalette.accent)
            Toggle("保留本地分组", isOn: $keepGroup)
                .font(SYFont.body)
                .tint(SYPalette.accent)
            Toggle("保留启用状态", isOn: $keepEnable)
                .font(SYFont.body)
                .tint(SYPalette.accent)
        } header: {
            Text("保留")
                .font(SYFont.caption)
                .foregroundStyle(SYPalette.inkSecondary)
        }
    }

    private var entriesSection: some View {
        Section {
            ForEach(plan.entries) { entry in
                ImportEntryRow(
                    name: entry.source.bookSourceName.isEmpty
                        ? entry.source.bookSourceUrl : entry.source.bookSourceName,
                    comment: entry.source.bookSourceComment,
                    state: entry.state,
                    isSelected: plan.isSelected(entry.id),
                    onToggle: { plan.toggle(entry.id) }
                )
            }
        } header: {
            Text(summaryText)
                .font(SYFont.caption)
                .foregroundStyle(SYPalette.inkSecondary)
        } footer: {
            Text("「已有」表示来源标记的更新时间不比本地新，默认不勾选。")
                .font(SYFont.micro)
                .foregroundStyle(SYPalette.inkTertiary)
        }
    }

    /// 共 N 个 · 新增 X · 更新 Y · 已有 Z
    private var summaryText: String {
        var parts: [String] = ["共 \(plan.totalCount) 个"]
        if plan.newCount > 0 { parts.append("新增 \(plan.newCount)") }
        if plan.updateCount > 0 { parts.append("更新 \(plan.updateCount)") }
        if plan.existingCount > 0 { parts.append("已有 \(plan.existingCount)") }
        return parts.joined(separator: " · ")
    }

    // MARK: 工具栏

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("取消") { dismiss() }
        }
        ToolbarItemGroup(placement: .bottomBar) {
            Button {
                plan.toggleSelectAll()
            } label: {
                HStack(spacing: SYMetric.gapXS) {
                    Image(systemName: plan.isSelectingAll ? "checkmark.square.fill" : "square")
                        .foregroundStyle(plan.isSelectingAll ? SYPalette.accent : SYPalette.inkTertiary)
                    Text(plan.isSelectingAll ? "取消全选" : "全选")
                        .font(SYFont.caption)
                }
            }
            Spacer()
            Text("已选 \(plan.selectedCount) 个")
                .font(SYFont.caption)
                .foregroundStyle(SYPalette.inkSecondary)
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("导入") {
                confirm()
            }
            .disabled(plan.selectedCount == 0)
        }
    }

    // MARK: 提交

    private func confirm() {
        let options = SYImportOptions(
            keepName: keepName,
            keepGroup: keepGroup,
            keepEnable: keepEnable,
            keepCustomOrder: keepCustomOrder,
            groupName: groupName,
            addsToExistingGroups: addsToExistingGroups
        )
        let summary = state.confirmImport(plan, options: options)
        onDone(summary)
        dismiss()
    }
}

// MARK: - 单行

/// 一行待确认书源：勾选框 + 名称 + 注释 + 状态徽章。
/// 直接取值而非 ObservedObject，勾选一次只重绘受影响行。
private struct ImportEntryRow: View {
    let name: String
    let comment: String?
    let state: SYImportItemState
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(alignment: .center, spacing: SYMetric.gapS) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? SYPalette.accent : SYPalette.inkTertiary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(name)
                        .font(SYFont.body)
                        .foregroundStyle(SYPalette.ink)
                        .lineLimit(2)
                    if let comment, !comment.isEmpty {
                        Text(comment)
                            .font(SYFont.micro)
                            .foregroundStyle(SYPalette.inkTertiary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: SYMetric.gapS)
                stateBadge
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityValue(title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var stateBadge: some View {
        Text(title)
            .font(SYFont.micro)
            .foregroundStyle(color)
            .padding(.horizontal, SYMetric.gapS)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
            .accessibilityHidden(true)
    }

    private var title: String {
        switch state {
        case .new: return "新增"
        case .update: return "更新"
        case .existing: return "已有"
        }
    }

    private var color: Color {
        switch state {
        case .new: return SYPalette.accent
        case .update: return SYPalette.gold
        case .existing: return SYPalette.inkSecondary
        }
    }
}