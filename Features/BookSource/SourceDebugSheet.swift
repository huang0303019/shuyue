import SwiftUI

/// 书源规则调试面板：搜索 / 详情 / 目录 / 正文 / 全流程 五个阶段，
/// 实时展示网络请求、原始数据、规则拆解、逐步提取与最终结果。
@MainActor
struct SourceDebugSheet: View {
    let source: SYBookSource

    @StateObject private var engine: SYSourceDebugEngine
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab: DebugTab = .search
    @State private var keyword = ""
    @State private var page = 1
    @State private var inputURL = ""

    enum DebugTab: String, CaseIterable, Identifiable {
        case search = "搜索"
        case detail = "详情"
        case toc = "目录"
        case content = "正文"
        case fullPipeline = "全流程"
        var id: String { rawValue }
    }

    init(source: SYBookSource) {
        self.source = source
        _engine = StateObject(wrappedValue: SYSourceDebugEngine(source: source))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                tabPicker
                inputArea
                logHeader

                if engine.logs.isEmpty {
                    emptyState
                } else {
                    logList
                }
            }
            .background(SYPalette.paper.ignoresSafeArea())
            .navigationTitle("规则调试")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(SYPalette.ink)
                    }
                    .accessibilityLabel("关闭")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        engine.clear()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(SYPalette.ink)
                    }
                    .disabled(engine.isRunning)
                    .accessibilityLabel("清空日志")
                }
            }
            .onChange(of: selectedTab) { _ in
                engine.clear()
                inputURL = ""
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - 顶部

    private var tabPicker: some View {
        Picker("解析阶段", selection: $selectedTab) {
            ForEach(DebugTab.allCases) { tab in
                Text(tab.rawValue).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, SYMetric.pagePadding)
        .padding(.vertical, SYMetric.gapM)
    }

    @ViewBuilder
    private var inputArea: some View {
        VStack(alignment: .leading, spacing: SYMetric.gapS) {
            switch selectedTab {
            case .search:
                HStack(spacing: SYMetric.gapS) {
                    TextField("搜索关键词", text: $keyword)
                        .textFieldStyle(.roundedBorder)
                        .font(SYFont.body)
                    Stepper("页码 \(page)", value: $page, in: 1...999)
                        .fixedSize()
                }
            case .detail, .toc, .content:
                TextField(
                    selectedTab == .content ? "章节 URL" : "\(selectedTab.rawValue) URL",
                    text: $inputURL
                )
                .textFieldStyle(.roundedBorder)
                .font(SYFont.body)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            case .fullPipeline:
                TextField("输入关键词，自动搜索 → 详情 → 目录 → 正文", text: $keyword)
                    .textFieldStyle(.roundedBorder)
                    .font(SYFont.body)
            }

            HStack(spacing: SYMetric.gapS) {
                Button {
                    Task { await runCurrent() }
                } label: {
                    HStack(spacing: 6) {
                        if engine.isRunning {
                            ProgressView()
                                .controlSize(.small)
                                .tint(SYPalette.accent)
                        } else {
                            Image(systemName: "play.fill")
                                .font(.system(size: 11, weight: .bold))
                        }
                        Text(engine.isRunning ? "运行中…" : "开始运行")
                            .font(SYFont.callout.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: SYMetric.controlHeight)
                    .background(SYPalette.accent, in: RoundedRectangle(cornerRadius: SYMetric.radiusControl))
                }
                .buttonStyle(.plain)
                .disabled(engine.isRunning || inputEmpty)
            }
        }
        .padding(.horizontal, SYMetric.pagePadding)
        .padding(.bottom, SYMetric.gapM)
    }

    private var inputEmpty: Bool {
        switch selectedTab {
        case .search, .fullPipeline:
            return keyword.trimmingCharacters(in: .whitespaces).isEmpty
        case .detail, .toc, .content:
            return inputURL.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    private func runCurrent() async {
        switch selectedTab {
        case .search:
            await engine.runSearch(keyword: keyword, page: page)
        case .detail:
            await engine.runDetail(url: inputURL)
        case .toc:
            await engine.runToc(url: inputURL)
        case .content:
            await engine.runContent(url: inputURL)
        case .fullPipeline:
            await engine.runFullPipeline(keyword: keyword)
        }
    }

    private var logHeader: some View {
        HStack {
            Text("调试日志")
                .font(SYFont.sectionTitle)
                .foregroundStyle(SYPalette.ink)
            Spacer()
            if !engine.logs.isEmpty {
                Text("\(engine.logs.count) 条")
                    .font(SYFont.caption)
                    .foregroundStyle(SYPalette.inkTertiary)
            }
        }
        .padding(.horizontal, SYMetric.pagePadding)
        .padding(.bottom, SYMetric.gapS)
    }

    private var emptyState: some View {
        VStack(spacing: SYMetric.gapM) {
            Spacer()
            Image(systemName: "wrench.and.screwdriver")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(SYPalette.inkTertiary)
            Text("输入参数后点击「开始运行」")
                .font(SYFont.body)
                .foregroundStyle(SYPalette.inkSecondary)
            Text("将依次展示请求、响应、规则拆解与提取结果")
                .font(SYFont.caption)
                .foregroundStyle(SYPalette.inkTertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var logList: some View {
        ScrollView {
            LazyVStack(spacing: SYMetric.gapS) {
                ForEach(engine.logs) { entry in
                    SYDebugLogRow(entry: entry)
                }
            }
            .padding(.horizontal, SYMetric.pagePadding)
            .padding(.bottom, SYMetric.gapXL)
        }
    }
}

/// 单条调试日志：级别图标 + 步骤 + 摘要，带详情可展开。
struct SYDebugLogRow: View {
    let entry: SYDebugLogEntry

    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: SYMetric.gapXS) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: Self.icon(for: entry.level))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Self.tint(for: entry.level))
                    .frame(width: 18, alignment: .leading)
                Text(entry.step)
                    .font(SYFont.caption)
                    .foregroundStyle(SYPalette.inkTertiary)
                Spacer(minLength: 8)
                Text(Self.timeFormatter.string(from: entry.timestamp))
                    .font(SYFont.micro)
                    .foregroundStyle(SYPalette.inkTertiary)
                if entry.detail != nil {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(SYPalette.inkTertiary)
                }
            }

            Text(entry.summary)
                .font(SYFont.body)
                .foregroundStyle(SYPalette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)

            if expanded, let detail = entry.detail {
                Text(detail)
                    .font(SYFont.micro)
                    .foregroundStyle(SYPalette.inkSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(.top, 2)
            }
        }
        .padding(SYMetric.gapM)
        .background(SYPalette.surface, in: RoundedRectangle(cornerRadius: SYMetric.radiusControl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SYMetric.radiusControl, style: .continuous)
                .stroke(SYPalette.border, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if entry.detail != nil { expanded.toggle() }
        }
    }

    static func icon(for level: SYDebugLevel) -> String {
        switch level {
        case .info: return "info.circle"
        case .success: return "checkmark.circle"
        case .warning: return "exclamationmark.triangle"
        case .error: return "xmark.octagon"
        case .pipeline: return "arrow.right.circle"
        }
    }

    static func tint(for level: SYDebugLevel) -> Color {
        switch level {
        case .info: return SYPalette.inkTertiary
        case .success: return SYPalette.accent
        case .warning: return SYPalette.gold
        case .error: return SYPalette.danger
        case .pipeline: return SYPalette.inkSecondary
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

#Preview("规则调试") {
    SourceDebugSheet(source: SYBookSource(bookSourceName: "示例书源", bookSourceUrl: "https://example.com"))
        .environmentObject(SYAppState())
}
