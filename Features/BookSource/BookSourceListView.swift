import SwiftUI

/// 书源管理 —— 统计、启停、导入、校验与删除 Legado 书源。
@MainActor
struct BookSourceListView: View {
    let onMenu: () -> Void

    @EnvironmentObject private var state: SYAppState

    @State private var showImport = false
    @State private var pendingDelete: SYBookSource?
    @State private var validationNotice: SourceValidationNotice?

    var body: some View {
        SYScreen(
            title: "书源",
            subtitle: "共 \(state.sources.count) 个 · 启用 \(state.enabledSources.count)",
            onMenu: onMenu,
            trailing: { importButton }
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

                VStack(spacing: SYMetric.gapM) {
                    ForEach(state.sources) { source in
                        sourceRow(source)
                    }
                }
            }
        }
        .sheet(isPresented: $showImport) {
            ImportSourceSheet()
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
        .alert(item: $validationNotice) { notice in
            Alert(
                title: Text(notice.issues.isEmpty ? "校验通过" : "校验发现问题"),
                message: Text(notice.message),
                dismissButton: .default(Text("好"))
            )
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

    private func sourceRow(_ source: SYBookSource) -> some View {
        SYRowCard(
            title: source.bookSourceName,
            subtitle: subtitle(for: source),
            systemImage: "square.stack.3d.up",
            accent: source.enabled ? SYPalette.accent : SYPalette.inkTertiary
        ) {
            Button {
                state.toggleSource(source)
            } label: {
                SYPillToggle(isOn: source.enabled)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(source.enabled ? "停用 \(source.bookSourceName)" : "启用 \(source.bookSourceName)")
        }
        .contextMenu {
            Button {
                validationNotice = SourceValidationNotice(source: source, issues: state.validate(source))
            } label: {
                Label("校验书源", systemImage: "checkmark.shield")
            }
            Button(role: .destructive) {
                pendingDelete = source
            } label: {
                Label("删除书源", systemImage: "trash")
            }
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

// MARK: - 校验结果

private struct SourceValidationNotice: Identifiable {
    let source: SYBookSource
    let issues: [String]

    var id: String { source.bookSourceUrl }
    var message: String {
        if issues.isEmpty { return "「\(source.bookSourceName)」规则完整，可以正常使用。" }
        return issues.joined(separator: "\n")
    }
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
            let summary: SYImportSummary
            switch mode {
            case .text:
                summary = state.importSources(text: text)
            case .url:
                summary = await state.importSources(remote: url)
            }
            isImporting = false
            result = summary.text
        }
    }
}