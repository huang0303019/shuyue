import SwiftUI

/// 搜索 —— 跨书源并发搜索并汇总结果，按书源分组展示。
@MainActor
struct SearchView: View {
    let onMenu: () -> Void

    @EnvironmentObject private var state: SYAppState

    @State private var query = ""
    @State private var results: [SYSearchGroup] = []
    @State private var isSearching = false
    @State private var hasSearched = false

    var body: some View {
        SYScreen(title: "搜索", subtitle: "跨书源搜书", onMenu: onMenu) {
            searchField

            if isSearching {
                HStack(spacing: SYMetric.gapS) {
                    Spacer()
                    ProgressView()
                        .tint(SYPalette.accent)
                    Text("正在搜索 \(max(1, state.enabledSearchCount)) 个书源")
                        .font(SYFont.caption)
                        .foregroundStyle(SYPalette.inkTertiary)
                    Spacer()
                }
                .padding(.vertical, SYMetric.gapL)
            } else if !hasSearched {
                SYEmptyState(
                    systemImage: "magnifyingglass",
                    title: state.enabledSearchCount == 0 ? "没有可用的搜索书源" : "输入关键词开始搜索",
                    message: state.enabledSearchCount == 0
                        ? "请在「书源」页启用带有搜索能力的书源，书源需要配置 searchUrl 与 ruleSearch。"
                        : "书悦会同时向 \(state.enabledSearchCount) 个已启用的书源发起搜索，并把结果按来源汇总。",
                    actionTitle: state.enabledSearchCount == 0 ? "去书源" : nil,
                    action: state.enabledSearchCount == 0 ? { state.present(.sources) } : nil
                )
            } else if results.isEmpty {
                SYEmptyState(
                    systemImage: "text.magnifyingglass",
                    title: "没有找到相关书籍",
                    message: "换个关键词试试，或检查书源是否可用。"
                )
            } else {
                ForEach(results) { group in
                    resultGroup(group)
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: SYMetric.gapS) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(SYPalette.inkTertiary)

            TextField("书名 / 作者 / 关键词", text: $query)
                .font(SYFont.body)
                .foregroundStyle(SYPalette.ink)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit {
                    Task { await performSearch() }
                }

            if isSearching {
                ProgressView()
                    .tint(SYPalette.accent)
            } else if !query.isEmpty {
                Button {
                    query = ""
                    results = []
                    hasSearched = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(SYPalette.inkTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清空")
            }
        }
        .padding(.horizontal, SYMetric.gapM)
        .frame(height: 46)
        .background(SYPalette.surface, in: RoundedRectangle(cornerRadius: SYMetric.radiusControl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SYMetric.radiusControl, style: .continuous)
                .stroke(SYPalette.border, lineWidth: 0.8)
        )
    }

    private func resultGroup(_ group: SYSearchGroup) -> some View {
        VStack(alignment: .leading, spacing: SYMetric.gapS) {
            HStack(spacing: SYMetric.gapS) {
                Text(group.sourceName)
                    .font(SYFont.sectionTitle)
                    .foregroundStyle(SYPalette.ink)
                Text("\(group.books.count) 本")
                    .font(SYFont.micro)
                    .foregroundStyle(SYPalette.inkTertiary)
                Spacer(minLength: 0)
                if let error = group.error, !error.isEmpty {
                    Text("出错")
                        .font(SYFont.micro.weight(.semibold))
                        .foregroundStyle(SYPalette.danger)
                }
            }

            if group.books.isEmpty {
                Text(group.error ?? "该书源没有返回结果。")
                    .font(SYFont.caption)
                    .foregroundStyle(SYPalette.inkTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, SYMetric.gapS)
            } else {
                VStack(spacing: SYMetric.gapM) {
                    ForEach(group.books) { book in
                        SYBookRow(book: book) {
                            state.open(.bookDetail(book))
                        }
                    }
                }
            }
        }
    }

    @MainActor
    private func performSearch() async {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty, !isSearching else { return }
        isSearching = true
        hasSearched = true
        results = await state.search(keyword: keyword)
        isSearching = false
    }
}