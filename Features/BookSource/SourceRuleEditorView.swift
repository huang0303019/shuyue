import SwiftUI

// MARK: - 书源规则编辑器（单页多段式）

/// 单页规则编辑器：基本 / 搜索 / 发现 / 详情 / 目录 / 正文 六段，
/// 每个字段以卡片行列出当前值，点按进入底部编辑器（带规则插入 chips）。
/// 保存后将整份草稿书源写回本地库。
@MainActor
struct SourceRuleEditorView: View {
    @EnvironmentObject private var state: SYAppState
    @Environment(\.dismiss) private var dismiss

    let source: SYBookSource
    let onSave: (SYBookSource) -> Void

    @State private var draft: SYBookSource
    @State private var selectedTab: SourceEditTab = .base
    @State private var editingField: SYFieldSpec?
    @State private var showDiscardConfirm = false

    enum SourceEditTab: String, CaseIterable, Identifiable {
        case base = "基本"
        case search = "搜索"
        case explore = "发现"
        case info = "详情"
        case toc = "目录"
        case content = "正文"

        var id: String { rawValue }
    }

    init(source: SYBookSource, onSave: @escaping (SYBookSource) -> Void) {
        self.source = source
        self.onSave = onSave
        _draft = State(initialValue: source)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SYCapsuleTabs(items: SourceEditTab.allCases, label: { $0.rawValue }, selection: $selectedTab)
                Divider()
                ScrollView {
                    VStack(spacing: SYMetric.gapS) {
                        ForEach(currentSpecs) { spec in
                            fieldRow(spec)
                        }
                    }
                    .padding(SYMetric.gapL)
                }
            }
            .background(SYPalette.paper.ignoresSafeArea())
            .navigationTitle(draft.bookSourceName.isEmpty ? "编辑书源" : draft.bookSourceName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { attemptCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onSave(draft)
                        dismiss()
                    } label: {
                        Text("保存").fontWeight(.semibold)
                    }
                    .disabled(!canSave)
                }
            }
            .sheet(item: $editingField) { spec in
                RuleFieldEditorSheet(
                    title: spec.label,
                    helpText: spec.dynamicHelp?(draft) ?? spec.helpText,
                    initialValue: spec.get(draft)
                ) { newValue in
                    var updated = draft
                    spec.set(&updated, newValue)
                    draft = updated
                }
            }
            .confirmationDialog(
                "尚未保存，是否退出？",
                isPresented: $showDiscardConfirm,
                titleVisibility: .visible
            ) {
                Button("继续编辑", role: .cancel) { }
                Button("放弃修改", role: .destructive) { dismiss() }
            }
        }
        .presentationDetents([.large])
    }

    // MARK: - 字段列表

    private var currentSpecs: [SYFieldSpec] {
        switch selectedTab {
        case .base: return SYFieldCatalog.base
        case .search: return SYFieldCatalog.search
        case .explore: return SYFieldCatalog.explore
        case .info: return SYFieldCatalog.info
        case .toc: return SYFieldCatalog.toc
        case .content: return SYFieldCatalog.content
        }
    }

    private func fieldRow(_ spec: SYFieldSpec) -> some View {
        Button {
            editingField = spec
        } label: {
            HStack(alignment: .center, spacing: SYMetric.gapM) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(spec.label)
                        .font(SYFont.caption)
                        .foregroundStyle(SYPalette.inkSecondary)
                    Text(displayValue(for: spec))
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(isEmpty(spec) ? SYPalette.inkTertiary.opacity(0.7) : SYPalette.ink)
                        .lineLimit(1)
                }
                Spacer(minLength: SYMetric.gapS)
                Image(systemName: "chevron.right")
                    .font(SYFont.caption)
                    .foregroundStyle(SYPalette.inkTertiary)
            }
            .contentShape(Rectangle())
            .padding(.horizontal, SYMetric.gapM)
            .padding(.vertical, 10)
            .background(SYPalette.surface, in: RoundedRectangle(cornerRadius: SYMetric.radiusControl, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SYMetric.radiusControl, style: .continuous)
                    .stroke(SYPalette.border, lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(spec.label)
        .accessibilityValue(displayValue(for: spec))
        .accessibilityHint("点按编辑规则")
    }

    private func displayValue(for spec: SYFieldSpec) -> String {
        let value = spec.get(draft)
        return value.isEmpty ? spec.placeholder : value
    }

    private func isEmpty(_ spec: SYFieldSpec) -> Bool {
        spec.get(draft).isEmpty
    }

    private var canSave: Bool {
        !draft.bookSourceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !draft.bookSourceUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func attemptCancel() {
        if draft != source {
            showDiscardConfirm = true
        } else {
            dismiss()
        }
    }
}

// MARK: - 字段规格

/// 一条可编辑规则字段：读 / 写均以整份书源为对象，支持嵌套规则值。
struct SYFieldSpec: Identifiable {
    let id = UUID()
    let label: String
    let placeholder: String
    let helpText: String?
    /// 动态帮助：以当前草稿为输入生成说明（优先级高于 helpText），
    /// 用于源变量等需要展示 `variableComment` 当前内容的字段。
    let dynamicHelp: ((SYBookSource) -> String?)?
    let get: (SYBookSource) -> String
    let set: (inout SYBookSource, String) -> Void

    init(
        _ label: String,
        placeholder: String = "",
        helpText: String? = nil,
        dynamicHelp: ((SYBookSource) -> String?)? = nil,
        get: @escaping (SYBookSource) -> String,
        set: @escaping (inout SYBookSource, String) -> Void
    ) {
        self.label = label
        self.placeholder = placeholder
        self.helpText = helpText
        self.dynamicHelp = dynamicHelp
        self.get = get
        self.set = set
    }
}

/// 全量字段目录：与 Legado 编辑页字段集对齐，仅暴露当前模型已承载的字段。
private enum SYFieldCatalog {
    // MARK: 基本

    static let base: [SYFieldSpec] = [
        string("书源名称", placeholder: "如：某某小说网", \.bookSourceName, required: true),
        string("书源地址", placeholder: "https://example.com", \.bookSourceUrl, required: true),
        string("书源分组", placeholder: "如：玄幻、言情", \.bookSourceGroup),
        string("源注释", \.bookSourceComment),
        string(
            "请求头",
            placeholder: #"{"User-Agent":"..."}"#,
            helpText: "JSON 格式，如：{\"Cookie\":\"...\"}",
            \.header
        ),
        string("并发率", placeholder: "0", \.concurrentRate),
        string("登录页 URL", placeholder: "https://...", \.loginUrl),
        string("登录 UI", placeholder: "JSON", \.loginUi),
        string(
            "登录校验 JS",
            placeholder: "result?.status == 200",
            helpText: "登录后以响应文本为 result 执行，返回 true 表示登录成功。",
            \.loginCheckJs
        ),
        string("书籍 URL 正则", \.bookUrlPattern),
        string("jsLib", helpText: "书源共用 JS 库，可在规则中调用。", \.jsLib),
        intString("响应超时", placeholder: "15000", \.respondTime),
        string("源变量说明", placeholder: "供用户填写源变量时参考的说明", \.variableComment),
        SYFieldSpec(
            "源变量",
            placeholder: #"{"token":"..."}"#,
            helpText: "JSON 文本，书源 JS 可通过 source.getVariable() 读取。",
            dynamicHelp: { source in
                let own = (source.variableComment ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let hint = "JSON 文本，书源 JS 可通过 source.getVariable() 读取。"
                return own.isEmpty ? hint : "\(own)\n\(hint)"
            },
            get: { $0.variable ?? "" },
            set: { source, value in source.variable = trimmedNil(value) }
        ),
    ]

    // MARK: 搜索

    static let search: [SYFieldSpec] = [
        string(
            "搜索 URL",
            placeholder: "https://example.com/search?q={{key}}",
            helpText: "{{key}} 为搜索关键词占位符。POST 格式：URL,POST,body",
            \.searchUrl
        ),
        nestedString(
            "预处理 JS",
            helpText: "获取搜索页 HTML 后先执行此 JS 再解析其余规则（字段名 init）。",
            keyPath: \.ruleSearch.initScript
        ),
        nestedString("校验关键字", placeholder: "我的", keyPath: \.ruleSearch.checkKeyWord),
        nestedString("书籍列表规则", placeholder: "ul.book-list li", keyPath: \.ruleSearch.bookList),
        nestedString("书籍列表 URL", keyPath: \.ruleSearch.bookListUrl),
        nestedString("书名规则", placeholder: "h3.title@text", keyPath: \.ruleSearch.name),
        nestedString("作者规则", placeholder: ".author@text", keyPath: \.ruleSearch.author),
        nestedString("分类规则", placeholder: ".kind@text", keyPath: \.ruleSearch.kind),
        nestedString("字数规则", placeholder: ".word-count@text", keyPath: \.ruleSearch.wordCount),
        nestedString("最新章节规则", placeholder: ".last-chapter@text", keyPath: \.ruleSearch.lastChapter),
        nestedString("简介规则", placeholder: ".intro@text", keyPath: \.ruleSearch.intro),
        nestedString("封面规则", placeholder: "img@src", keyPath: \.ruleSearch.coverUrl),
        nestedString("详情页 URL 规则", placeholder: "a@href", keyPath: \.ruleSearch.bookUrl),
        nestedString("标签规则", keyPath: \.ruleSearch.tag),
        nestedString("搜索类型", placeholder: "0", keyPath: \.ruleSearch.searchType),
    ]

    // MARK: 发现

    static let explore: [SYFieldSpec] = [
        string(
            "发现地址",
            placeholder: "https://example.com/category",
            helpText: "多地址用 && 分隔；POST 格式：URL,POST,body",
            \.exploreUrl
        ),
        nestedString(
            "预处理 JS",
            helpText: "获取发现页 HTML 后先执行此 JS 再解析其余规则（字段名 init）。",
            keyPath: \.ruleExplore.initScript
        ),
        nestedString("书籍列表规则", placeholder: "ul.book-list li", keyPath: \.ruleExplore.bookList),
        nestedString("书名规则", placeholder: "h3.title@text", keyPath: \.ruleExplore.name),
        nestedString("作者规则", placeholder: ".author@text", keyPath: \.ruleExplore.author),
        nestedString("分类规则", placeholder: ".kind@text", keyPath: \.ruleExplore.kind),
        nestedString("字数规则", placeholder: ".word-count@text", keyPath: \.ruleExplore.wordCount),
        nestedString("最新章节规则", placeholder: ".last-chapter@text", keyPath: \.ruleExplore.lastChapter),
        nestedString("简介规则", placeholder: ".intro@text", keyPath: \.ruleExplore.intro),
        nestedString("封面规则", placeholder: "img@src", keyPath: \.ruleExplore.coverUrl),
        nestedString("详情页 URL 规则", placeholder: "a@href", keyPath: \.ruleExplore.bookUrl),
    ]

    // MARK: 详情

    static let info: [SYFieldSpec] = [
        nestedString(
            "预处理规则",
            helpText: "获取书籍详情页后先执行此 JS 再解析其余规则（字段名 init）。",
            keyPath: \.ruleBookInfo.initRule
        ),
        nestedString("书名规则", placeholder: "h1@text", keyPath: \.ruleBookInfo.name),
        nestedString("作者规则", placeholder: ".author@text", keyPath: \.ruleBookInfo.author),
        nestedString("分类规则", placeholder: ".kind@text", keyPath: \.ruleBookInfo.kind),
        nestedString("字数规则", placeholder: ".word-count@text", keyPath: \.ruleBookInfo.wordCount),
        nestedString("简介规则", placeholder: "#intro@text", keyPath: \.ruleBookInfo.intro),
        nestedString("封面规则", placeholder: ".cover img@src", keyPath: \.ruleBookInfo.coverUrl),
        nestedString(
            "目录 URL 规则",
            placeholder: "留空使用书籍页 URL",
            keyPath: \.ruleBookInfo.bookUrlPattern
        ),
        nestedString("头像 URL", keyPath: \.ruleBookInfo.touxiangUrl),
    ]

    // MARK: 目录

    static let toc: [SYFieldSpec] = [
        nestedString(
            "更新之前 JS",
            helpText: "preUpdateJs：加载目录页后先执行此 JS 再解析。",
            keyPath: \.ruleToc.preUpdateJs
        ),
        nestedString("目录 URL", keyPath: \.ruleToc.url),
        nestedString("章节目录规则", placeholder: "#chapter-list a", keyPath: \.ruleToc.chapterList),
        nestedString("章节名称规则", placeholder: "@text", keyPath: \.ruleToc.chapterName),
        nestedString("章节 URL 规则", placeholder: "@href", keyPath: \.ruleToc.chapterUrl),
        nestedString("下一页规则", placeholder: ".next@href", keyPath: \.ruleToc.nextTocUrl),
        nestedString("格式化规则", keyPath: \.ruleToc.formatJs),
        nestedString("卷标识", helpText: "标记分卷条目的规则。", keyPath: \.ruleToc.isVolume),
        nestedString("VIP 标识", keyPath: \.ruleToc.isVip),
        nestedString("购买标识", keyPath: \.ruleToc.isPay),
        nestedString("付费类型", keyPath: \.ruleToc.payType),
    ]

    // MARK: 正文

    static let content: [SYFieldSpec] = [
        nestedString("正文规则", placeholder: "#chapter-content", keyPath: \.ruleContent.content),
        nestedString("章节名称规则", placeholder: "@text", keyPath: \.ruleContent.title),
        nestedString("正文 URL", keyPath: \.ruleContent.url),
        nestedString("下一页 URL 规则", placeholder: ".next-page@href", keyPath: \.ruleContent.nextContentUrl),
        nestedString("WebView JS", helpText: "webJs：通过 WebView 加载正文时执行的规则。", keyPath: \.ruleContent.webJs),
        nestedString(
            "替换规则",
            helpText: "替换规则每行格式：regex@@@replacement（空 replacement 表示删除）",
            keyPath: \.ruleContent.replaceRegex
        ),
        nestedString("图片样式", keyPath: \.ruleContent.imageStyle),
    ]

    // MARK: 工厂

    /// 顶层可选字符串字段：空值保存为 nil。
    private static func string(
        _ label: String,
        placeholder: String = "",
        helpText: String? = nil,
        _ keyPath: WritableKeyPath<SYBookSource, String?>
    ) -> SYFieldSpec {
        SYFieldSpec(label, placeholder: placeholder, helpText: helpText,
                    get: { $0[keyPath: keyPath] ?? "" },
                    set: { src, v in src[keyPath: keyPath] = trimmedNil(v) })
    }

    /// 顶层必填字符串字段：保留原值（含空串）。
    private static func string(
        _ label: String,
        placeholder: String = "",
        helpText: String? = nil,
        _ keyPath: WritableKeyPath<SYBookSource, String>,
        required: Bool = false
    ) -> SYFieldSpec {
        SYFieldSpec(label, placeholder: placeholder, helpText: helpText,
                    get: { $0[keyPath: keyPath] },
                    set: { src, v in src[keyPath: keyPath] = v })
    }

    /// 顶层整数字段：编辑为文本，保存时解析为 Int，失败回退当前值。
    private static func intString(
        _ label: String,
        placeholder: String = "",
        _ keyPath: WritableKeyPath<SYBookSource, Int>
    ) -> SYFieldSpec {
        SYFieldSpec(label, placeholder: placeholder,
                    get: { String($0[keyPath: keyPath]) },
                    set: { src, v in
                        if let parsed = Int(v.trimmingCharacters(in: .whitespacesAndNewlines)) {
                            src[keyPath: keyPath] = parsed
                        }
                    })
    }

    /// 嵌套规则里的可选字符串字段。
    private static func nestedString(
        _ label: String,
        placeholder: String = "",
        helpText: String? = nil,
        keyPath: WritableKeyPath<SYBookSource, String?>
    ) -> SYFieldSpec {
        SYFieldSpec(label, placeholder: placeholder, helpText: helpText,
                    get: { $0[keyPath: keyPath] ?? "" },
                    set: { src, v in src[keyPath: keyPath] = trimmedNil(v) })
    }

    private static func trimmedNil(_ v: String) -> String? {
        let t = v.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}