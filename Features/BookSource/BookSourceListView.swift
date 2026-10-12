import SwiftUI
import UIKit

/// 书源管理 —— 统计、启停、导入、校验与删除 Legado 书源。
@MainActor
struct BookSourceListView: View {
    let onMenu: () -> Void

    @EnvironmentObject private var state: SYAppState

    @State private var showImport = false
    @State private var pendingDelete: SYBookSource?
    @State private var checkSheet: SYHealthChecker?
    @State private var pendingGroupMove: SYBookSource?
    @State private var editingSource: SYBookSource?
    @State private var editingVariable: SYBookSource?
    @State private var loggingInSource: SYBookSource?
    @State private var debuggingSource: SYBookSource?
    @State private var showGroupByDomainConfirm = false
    @State private var groupNaming: PendingGroupNaming?
    @State private var groupNameText = ""
    @State private var pendingMergeGroup: SYSourceGroupSection?
    @State private var pendingDeleteGroup: SYSourceGroupSection?
    @State private var notice: String?

    var body: some View {
        SYScreen(
            title: "书源",
            subtitle: "共 \(state.sources.count) 个 · 启用 \(state.enabledSources.count)",
            onMenu: onMenu,
            trailing: { trailingActions }
        ) {
            if state.sources.isEmpty {
                SYEmptyState(
                    systemImage: "square.stack.3d.up",
                    title: "还没有书源",
                    message: "支持粘贴文本或输入订阅链接导入标准 Legado JSON 书源数组，可与「阅读」等客户端互通。",
                    actionTitle: "导入书源",
                    action: { showImport = true }
                )
            } else {
                HStack(spacing: SYMetric.gapM) {
                    statCard(title: "书源总数", value: "\(state.sources.count)", image: "square.stack.3d.up", tint: SYPalette.accent)
                    statCard(title: "已启用", value: "\(state.enabledSources.count)", image: "checkmark.seal", tint: SYPalette.gold)
                }

                groupToggle

                if state.groupByList {
                    groupedList
                } else {
                    VStack(spacing: SYMetric.gapM) {
                        ForEach(state.sources) { source in
                            sourceRow(source)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showImport) {
            ImportSourceSheet()
        }
        .sheet(item: $checkSheet) { checker in
            SourceCheckSheet(checker: checker) { summary in
                if let summary, let source = checker.item?.source {
                    state.recordHealth(summary, for: source.bookSourceUrl)
                }
            }
            .environmentObject(state)
        }
        .sheet(item: $pendingGroupMove) { source in
            GroupMoveSheet(source: source) { group in
                state.setGroup(group, for: [source])
            }
        }
        .sheet(item: $editingSource) { source in
            SourceRuleEditorView(source: source) { updated in
                state.updateSource(updated)
            }
            .environmentObject(state)
        }
        .sheet(item: $editingVariable) { source in
            SourceVariableSheet(source: source) { updated in
                state.updateSource(updated)
            }
            .environmentObject(state)
        }
        .sheet(item: $loggingInSource) { source in
            SourceLoginSheet(source: source)
                .environmentObject(state)
        }
        .sheet(item: $debuggingSource) { source in
            SourceDebugSheet(source: source)
                .environmentObject(state)
        }
        .confirmationDialog(
            "移出「\(pendingDelete?.bookSourceName ?? "书源")」？",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("删除书源", role: .destructive) {
                if let pendingDelete { state.deleteSource(pendingDelete) }
                pendingDelete = nil
            }
            Button("取消", role: .cancel) { pendingDelete = nil }
        }
        .sheet(item: $pendingMergeGroup) { group in
            GroupMoveSheet(
                title: "合并到其他分组",
                subtitle: "\(group.name) · \(group.sourceIDs.count) 个书源",
                currentGroup: group.name == SYBookSourceGrouping.defaultGroupName ? "" : group.name,
                allowsNewGroup: false,
                excludedGroups: [group.name]
            ) { target in
                mergeGroup(group, to: target)
            }
            .environmentObject(state)
        }
        .alert("按域名分组", isPresented: $showGroupByDomainConfirm) {
            Button("取消", role: .cancel) {}
            Button("确定") {
                let changed = state.groupByDomain()
                showNotice(changed > 0
                    ? "已按域名分组 \(changed) 个书源"
                    : "书源已全部按域名分组")
            }
        } message: {
            Text("按域名分组将覆盖现有分组，确定继续？")
        }
        .alert(
            groupNaming?.title ?? "分组名称",
            isPresented: Binding(get: { groupNaming != nil }, set: { if !$0 { groupNaming = nil } })
        ) {
            TextField("分组名称", text: $groupNameText)
            Button("取消", role: .cancel) { groupNaming = nil }
            Button("确定") { commitGroupNaming() }
        } message: {
            if let pending = groupNaming {
                Text(pending.subtitle)
            }
        }
        .alert(
            "删除分组",
            isPresented: Binding(get: { pendingDeleteGroup != nil }, set: { if !$0 { pendingDeleteGroup = nil } })
        ) {
            Button("取消", role: .cancel) { pendingDeleteGroup = nil }
            Button("删除", role: .destructive) {
                if let group = pendingDeleteGroup { deleteGroup(group) }
                pendingDeleteGroup = nil
            }
        } message: {
            if let group = pendingDeleteGroup {
                Text("将删除分组「\(group.name)」及其中的 \(group.sourceIDs.count) 个书源，该操作不可恢复。")
            }
        }
        .overlay(alignment: .bottom) {
            if let notice {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(SYPalette.accent)
                    Text(notice)
                        .font(SYFont.callout.weight(.medium))
                        .foregroundStyle(SYPalette.ink)
                }
                .padding(.horizontal, SYMetric.gapL)
                .padding(.vertical, 10)
                .background(SYPalette.surface, in: Capsule())
                .overlay(
                    Capsule().stroke(SYPalette.border, lineWidth: 0.8)
                )
                .shadow(color: SYPalette.ink.opacity(0.10), radius: 14, y: 5)
                .padding(.bottom, 20)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .task(id: notice) {
            guard notice != nil else { return }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation(.easeOut(duration: 0.25)) { notice = nil }
        }
    }

    // MARK: - 分组管理

    private func showNotice(_ text: String) {
        withAnimation(.easeOut(duration: 0.2)) { notice = text }
    }

    /// 重命名分组：默认分组起始为空（无真实 bookSourceGroup），输入新名称即为其书源落组。
    private func beginRenameGroup(_ group: SYSourceGroupSection) {
        groupNameText = group.name == SYBookSourceGrouping.defaultGroupName ? "" : group.name
        groupNaming = PendingGroupNaming(
            title: "重命名分组",
            subtitle: "\(group.name) · \(group.sourceIDs.count) 个书源",
            sourceIDs: group.sourceIDs,
            currentName: group.name
        )
    }

    private func commitGroupNaming() {
        guard let pending = groupNaming else { return }
        groupNaming = nil
        let trimmed = groupNameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != pending.currentName else { return }
        let urls = Set(pending.sourceIDs)
        let sourcesToMove = state.sources.filter { urls.contains($0.bookSourceUrl) }
        let newGroup = trimmed == SYBookSourceGrouping.defaultGroupName ? "" : trimmed
        state.setGroup(newGroup, for: sourcesToMove)
    }

    /// 合并分组到目标分组；目标为空或缺省名时清除 bookSourceGroup 回到默认分组。
    private func mergeGroup(_ group: SYSourceGroupSection, to target: String) {
        let urls = Set(group.sourceIDs)
        let sourcesToMove = state.sources.filter { urls.contains($0.bookSourceUrl) }
        let targetGroup = target == SYBookSourceGrouping.defaultGroupName ? "" : target
        state.setGroup(targetGroup, for: sourcesToMove)
        let displayTarget = target.isEmpty ? SYBookSourceGrouping.defaultGroupName : target
        showNotice("已合并「\(group.name)」到「\(displayTarget)」")
    }

    private func deleteGroup(_ group: SYSourceGroupSection) {
        let urls = Set(group.sourceIDs)
        let sourcesToDelete = state.sources.filter { urls.contains($0.bookSourceUrl) }
        state.deleteSources(sourcesToDelete)
        showNotice("已删除分组「\(group.name)」及 \(sourcesToDelete.count) 个书源")
    }

    private func copyGroupJSON(_ group: SYSourceGroupSection) {
        let json = state.exportSourcesText(ids: group.sourceIDs)
        UIPasteboard.general.string = json
        showNotice("已复制 \(group.sourceIDs.count) 个书源到剪贴板")
    }

    /// 分组 / 平铺切换胶囊。
    private var groupToggle: some View {
        HStack(spacing: 0) {
            toggleItem(title: "分组", systemImage: "folder", isOn: state.groupByList) {
                state.setGroupByList(true)
            }
            toggleItem(title: "平铺", systemImage: "list.bullet", isOn: !state.groupByList) {
                state.setGroupByList(false)
            }
            Spacer(minLength: 0)
        }
        .padding(SYMetric.gapXS)
        .background(SYPalette.surface, in: RoundedRectangle(cornerRadius: SYMetric.radiusControl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SYMetric.radiusControl, style: .continuous)
                .stroke(SYPalette.border, lineWidth: 0.8)
        )
    }

    private func toggleItem(title: String, systemImage: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(SYFont.callout.weight(isOn ? .semibold : .regular))
            }
            .foregroundStyle(isOn ? Color.white : SYPalette.inkSecondary)
            .padding(.horizontal, SYMetric.gapL)
            .frame(height: 32)
            .background(isOn ? SYPalette.accent : Color.clear, in: RoundedRectangle(cornerRadius: SYMetric.radiusControl - 2, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// 按分组折叠展示。
    private var groupedList: some View {
        let sourceMap = Dictionary(uniqueKeysWithValues: state.sources.map { ($0.bookSourceUrl, $0) })
        return VStack(spacing: SYMetric.gapM) {
            ForEach(state.groupedSections) { section in
                groupSection(section, sourceMap: sourceMap)
            }
        }
    }

    private func groupSection(_ section: SYSourceGroupSection, sourceMap: [String: SYBookSource]) -> some View {
        let collapsed = state.isGroupCollapsed(section.id)
        let visibleSources = section.sourceIDs.compactMap { sourceMap[$0] }
        return VStack(spacing: SYMetric.gapS) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    state.toggleGroupCollapsed(section.id)
                }
            } label: {
                HStack(spacing: SYMetric.gapS) {
                    Image(systemName: section.kind == .pinnedTop ? "pin.fill"
                            : section.kind == .pinnedBottom ? "pin"
                            : section.kind == .default ? "tray"
                            : "folder")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(
                            section.kind == .normal ? SYPalette.accent
                            : section.kind == .default ? SYPalette.inkTertiary
                            : SYPalette.gold
                        )
                        .frame(width: 26, height: 26)
                        .background(
                            (section.kind == .normal ? SYPalette.accentSoft : SYPalette.surfaceAlt),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )

                    Text(section.name)
                        .font(SYFont.body.weight(.semibold))
                        .foregroundStyle(SYPalette.ink)

                    Text("\(visibleSources.count)")
                        .font(SYFont.micro.weight(.medium))
                        .foregroundStyle(SYPalette.inkTertiary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(SYPalette.surfaceAlt, in: Capsule())

                    Spacer(minLength: 0)

                    Image(systemName: collapsed ? "chevron.down" : "chevron.up")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(SYPalette.inkTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contextMenu {
                if section.kind == .normal || section.kind == .default {
                    Button {
                        beginRenameGroup(section)
                    } label: {
                        Label("重命名分组", systemImage: "pencil")
                    }

                    Button {
                        pendingMergeGroup = section
                    } label: {
                        Label("合并到其他分组", systemImage: "arrow.triangle.merge")
                    }

                    Button {
                        state.setSourcesEnabled(Array(section.sourceIDs), enabled: true)
                        showNotice("已启用「\(section.name)」全部书源")
                    } label: {
                        Label("启用组内全部", systemImage: "checkmark.circle")
                    }

                    Button {
                        state.setSourcesEnabled(Array(section.sourceIDs), enabled: false)
                        showNotice("已停用「\(section.name)」全部书源")
                    } label: {
                        Label("停用组内全部", systemImage: "circle.slash")
                    }

                    Button {
                        copyGroupJSON(section)
                    } label: {
                        Label("复制分组 JSON", systemImage: "doc.on.doc")
                    }

                    if section.kind == .normal {
                        Divider()
                        Button(role: .destructive) {
                            pendingDeleteGroup = section
                        } label: {
                            Label("删除分组", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(.horizontal, SYMetric.gapM)
            .padding(.vertical, 6)

            if !collapsed {
                VStack(spacing: SYMetric.gapS) {
                    ForEach(visibleSources) { source in
                        sourceRow(source)
                    }
                }
            }
        }
    }

    private var importButton: some View {
        Button {
            showImport = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(SYPalette.ink)
                .frame(width: 38, height: 38)
                .background(SYPalette.surfaceAlt, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("导入书源")
    }

    /// 顶栏右侧动作：导入 + 更多（按域名分组 / 复制全部）。
    private var trailingActions: some View {
        HStack(spacing: SYMetric.gapS) {
            importButton
            Menu {
                Button {
                    showGroupByDomainConfirm = true
                } label: {
                    Label("按域名分组", systemImage: "globe")
                }
                Button {
                    UIPasteboard.general.string = state.exportSourcesText()
                    showNotice("已复制全部 \(state.sources.count) 个书源到剪贴板")
                } label: {
                    Label("复制全部书源", systemImage: "doc.on.doc")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(SYPalette.ink)
                    .frame(width: 38, height: 38)
                    .background(SYPalette.surfaceAlt, in: Circle())
            }
            .accessibilityLabel("更多")
        }
    }

    private func sourceRow(_ source: SYBookSource) -> some View {
        SYRowCard(
            title: source.bookSourceName,
            subtitle: subtitle(for: source),
            systemImage: "square.stack.3d.up",
            accent: source.enabled ? SYPalette.accent : SYPalette.inkTertiary
        ) {
            HStack(spacing: SYMetric.gapS) {
                if let summary = state.healthBySource[source.bookSourceUrl] {
                    Image(systemName: Self.healthIcon(summary.health))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Self.healthColor(summary.health))
                        .accessibilityLabel(Self.healthTitle(summary.health))
                }
                Button {
                    state.toggleSource(source)
                } label: {
                    SYPillToggle(isOn: source.enabled)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(source.enabled ? "停用 \(source.bookSourceName)" : "启用 \(source.bookSourceName)")
            }
        }
        .contextMenu {
            Button {
                editingSource = source
            } label: {
                Label("编辑规则", systemImage: "slider.horizontal.3")
            }

            Button {
                editingVariable = source
            } label: {
                Label("设置源变量", systemImage: "curlybraces")
            }

            Button {
                loggingInSource = source
            } label: {
                Label("登录", systemImage: "key.horizontal")
            }

            Button {
                let checker = SYHealthChecker()
                checker.start(source: source)
                checkSheet = checker
            } label: {
                Label("实跑校验", systemImage: "checkmark.shield")
            }

            Button {
                debuggingSource = source
            } label: {
                Label("规则调试", systemImage: "wrench.and.screwdriver")
            }

            if let record = state.pinRecord(for: source) {
                Button {
                    state.unpin(source)
                } label: {
                    Label(record.position == .top ? "取消置顶" : "取消置底", systemImage: "xmark.circle")
                }
            } else {
                Button {
                    state.pinToTop(source)
                } label: {
                    Label("置顶", systemImage: "pin")
                }
                Button {
                    state.pinToBottom(source)
                } label: {
                    Label("置底", systemImage: "pin.slash")
                }
            }

            Button {
                pendingGroupMove = source
            } label: {
                Label("移动到分组", systemImage: "folder")
            }

            Button(role: .destructive) {
                pendingDelete = source
            } label: {
                Label("删除书源", systemImage: "trash")
            }
        }
    }

    // MARK: - 行内健康徽章

    private static func healthIcon(_ health: SYSourceHealth) -> String {
        switch health {
        case .passed: return "checkmark.circle.fill"
        case .contentError: return "exclamationmark.triangle.fill"
        case .fetchError: return "xmark.circle.fill"
        }
    }

    private static func healthColor(_ health: SYSourceHealth) -> Color {
        switch health {
        case .passed: return SYPalette.accent
        case .contentError: return SYPalette.gold
        case .fetchError: return SYPalette.danger
        }
    }

    private static func healthTitle(_ health: SYSourceHealth) -> String {
        switch health {
        case .passed: return "校验通过"
        case .contentError: return "正文异常"
        case .fetchError: return "抓取异常"
        }
    }

    private func subtitle(for source: SYBookSource) -> String {
        var parts: [String] = []
        if let group = source.bookSourceGroup, !group.isEmpty { parts.append(group) }
        parts.append(source.bookSourceUrl)
        return parts.joined(separator: " · ")
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

// MARK: - 移动到分组 / 合并分组

@MainActor
private struct GroupMoveSheet: View {
    let title: String
    let subtitle: String?
    let currentGroup: String?
    let allowsNewGroup: Bool
    let excludedGroups: Set<String>
    let onSelect: (String) -> Void

    @EnvironmentObject private var state: SYAppState
    @Environment(\.dismiss) private var dismiss
    @State private var newGroupName = ""

    /// 单书源移动分组（保留原有入口语义）。
    init(source: SYBookSource, onSelect: @escaping (String) -> Void) {
        self.init(
            title: "移动到分组",
            subtitle: source.bookSourceName,
            currentGroup: source.bookSourceGroup,
            allowsNewGroup: true,
            excludedGroups: [],
            onSelect: onSelect
        )
    }

    init(
        title: String,
        subtitle: String?,
        currentGroup: String?,
        allowsNewGroup: Bool,
        excludedGroups: Set<String> = [],
        onSelect: @escaping (String) -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.currentGroup = currentGroup
        self.allowsNewGroup = allowsNewGroup
        self.excludedGroups = excludedGroups
        self.onSelect = onSelect
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(SYFont.caption)
                            .foregroundStyle(SYPalette.inkSecondary)
                    }
                }

                Section("现有分组") {
                    if !(currentGroup ?? "").isEmpty {
                        Button {
                            onSelect("")
                            dismiss()
                        } label: {
                            Label("移出分组（默认分组）", systemImage: "tray")
                        }
                    }
                    ForEach(existingGroups, id: \.self) { group in
                        Button {
                            onSelect(group)
                            dismiss()
                        } label: {
                            HStack {
                                Label(group, systemImage: "folder")
                                Spacer()
                                if currentGroup == group {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(SYPalette.accent)
                                }
                            }
                        }
                    }
                }

                if allowsNewGroup {
                    Section("新建分组") {
                        TextField("分组名称", text: $newGroupName)
                        Button {
                            let name = newGroupName.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !name.isEmpty else { return }
                            onSelect(name)
                            dismiss()
                        } label: {
                            Label("创建并移动", systemImage: "plus.circle")
                        }
                        .disabled(newGroupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// 现有分组（按名称升序）+ 置顶/置底不作为可选项；来源组保留原样。
    private var existingGroups: [String] {
        state.groupCounts()
            .map { $0.name }
            .filter { $0 != SYBookSourceGrouping.defaultGroupName && !excludedGroups.contains($0) }
            .sorted()
    }
}

// MARK: - 重命名分组

private struct PendingGroupNaming {
    let title: String
    let subtitle: String
    let sourceIDs: [String]
    let currentName: String
}

// MARK: - 导入面板

@MainActor
private struct ImportSourceSheet: View {
    @EnvironmentObject private var state: SYAppState
    @Environment(\.dismiss) private var dismiss

    private enum Mode: String, CaseIterable, Identifiable {
        case text
        case url

        var id: String { rawValue }
        var title: String {
            switch self {
            case .text: return "粘贴文本"
            case .url: return "订阅链接"
            }
        }
    }

    @State private var mode: Mode = .text
    @State private var text = ""
    @State private var url = ""
    @State private var isImporting = false
    @State private var result: String?
    @State private var pendingPlan: SYImportPlan?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: SYMetric.gapL) {
                HStack(spacing: SYMetric.gapS) {
                    ForEach(Mode.allCases) { item in
                        let active = item == mode
                        Button {
                            withAnimation(.easeOut(duration: 0.18)) { mode = item }
                        } label: {
                            Text(item.title)
                                .font(SYFont.caption.weight(active ? .semibold : .regular))
                                .foregroundStyle(active ? Color.white : SYPalette.inkSecondary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(active ? SYPalette.accent : SYPalette.surfaceAlt, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                }

                if mode == .text {
                    textEditor
                } else {
                    urlField
                }

                if let result {
                    Text(result)
                        .font(SYFont.callout)
                        .foregroundStyle(SYPalette.accent)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(SYMetric.gapM)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(SYPalette.accentSoft, in: RoundedRectangle(cornerRadius: SYMetric.radiusControl, style: .continuous))
                }

                Spacer(minLength: 0)

                if isImporting {
                    HStack(spacing: SYMetric.gapS) {
                        Spacer()
                        ProgressView()
                            .tint(SYPalette.accent)
                        Text("正在导入")
                            .font(SYFont.caption)
                            .foregroundStyle(SYPalette.inkTertiary)
                        Spacer()
                    }
                    .padding(.vertical, SYMetric.gapS)
                } else {
                    SYButton(
                        title: "导入",
                        systemImage: "square.and.arrow.down",
                        kind: .primary
                    ) {
                        performImport()
                    }
                    .disabled(!canImport)
                }
            }
            .padding(SYMetric.gapXL)
            .background(SYPalette.paper.ignoresSafeArea())
            .navigationTitle("导入书源")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .sheet(item: $pendingPlan) { plan in
            ImportConfirmSheet(plan: plan) { summary in
                result = summary.text
            }
            .environmentObject(state)
        }
    }

    private var textEditor: some View {
        TextEditor(text: $text)
            .font(SYFont.callout)
            .foregroundStyle(SYPalette.ink)
            .scrollContentBackground(.hidden)
            .padding(SYMetric.gapM)
            .background(SYPalette.surfaceAlt, in: RoundedRectangle(cornerRadius: SYMetric.radiusControl, style: .continuous))
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text("粘贴一份 Legado 书源 JSON（对象或数组）")
                        .font(SYFont.callout)
                        .foregroundStyle(SYPalette.inkTertiary)
                        .padding(.top, 20)
                        .padding(.leading, 18)
                        .allowsHitTesting(false)
                }
            }
            .frame(minHeight: 200)
    }

    private var urlField: some View {
        VStack(alignment: .leading, spacing: SYMetric.gapS) {
            HStack(spacing: SYMetric.gapS) {
                Image(systemName: "link")
                    .foregroundStyle(SYPalette.inkTertiary)
                TextField("https://.../bookSource.json", text: $url)
                    .font(SYFont.body)
                    .foregroundStyle(SYPalette.ink)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            .padding(.horizontal, SYMetric.gapM)
            .frame(height: 46)
            .background(SYPalette.surface, in: RoundedRectangle(cornerRadius: SYMetric.radiusControl, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SYMetric.radiusControl, style: .continuous)
                    .stroke(SYPalette.border, lineWidth: 0.8)
            )
            Text("书悦将直接请求该地址并解析返回的 JSON 文本。")
                .font(SYFont.micro)
                .foregroundStyle(SYPalette.inkTertiary)
        }
    }

    private var canImport: Bool {
        switch mode {
        case .text: return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .url: return !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    @MainActor
    private func performImport() {
        guard !isImporting else { return }
        isImporting = true
        result = nil
        Task {
            let parsed: Result<[SYBookSource], Error>
            switch mode {
            case .text:
                let sources = SYBookSourceStore.parse(text)
                parsed = sources.isEmpty
                    ? .failure(SYImportMessage(message: "未解析到任何书源，请确认是标准 Legado 书源 JSON（对象或数组）。"))
                    : .success(sources)
            case .url:
                parsed = await state.parseRemote(urlString: url)
            }
            isImporting = false
            switch parsed {
            case .success(let sources):
                pendingPlan = state.importPlan(from: sources)
            case .failure(let error):
                result = error.localizedDescription
            }
        }
    }
}
