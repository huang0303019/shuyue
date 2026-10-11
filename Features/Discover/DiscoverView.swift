import SwiftUI

/// 发现 —— 按书源枚举分类与推荐，横向书籍卡片流，各书源独立加载。
@MainActor
struct DiscoverView: View {
    let onMenu: () -> Void

    @EnvironmentObject private var state: SYAppState

    var body: some View {
        SYScreen(title: "发现", subtitle: "按书源逛逛", onMenu: onMenu) {
            if state.exploreSources.isEmpty {
                SYEmptyState(
                    systemImage: "sparkles",
                    title: "暂无可浏览的内容",
                    message: "「书源」中勾选带发现能力的书源（enabledExplore）后，这里会按书源的发现页规则抓取分类与推荐。",
                    actionTitle: "去书源",
                    action: { state.present(.sources) }
                )
            } else {
                ForEach(state.exploreSources) { source in
                    DiscoverSourceSectionView(source: source)
                }
            }
        }
    }
}

/// 单个书源的发现区块：分类胶囊 + 横向书籍流，独立加载状态。
@MainActor
private struct DiscoverSourceSectionView: View {
    @EnvironmentObject private var state: SYAppState
    let source: SYBookSource

    @State private var categories: [SYExploreCategory] = []
    @State private var selectedIndex = 0
    @State private var books: [SYBook] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var hasLoadedCategories = false

    var body: some View {
        VStack(alignment: .leading, spacing: SYMetric.gapM) {
            SYSectionHeader(title: source.bookSourceName, subtitle: subtitle)

            if !categories.isEmpty {
                SYCapsuleTabs(items: Array(categories.indices), label: { categories[$0].title }, selection: $selectedIndex)
                    .padding(.horizontal, -SYMetric.pagePadding)
            }

            content
        }
        .onAppear {
            loadCategoriesIfNeeded()
            Task { await loadBooks() }
        }
        .onChange(of: selectedIndex) { _ in
            Task { await loadBooks() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && books.isEmpty {
            HStack(spacing: SYMetric.gapS) {
                Spacer()
                ProgressView()
                    .tint(SYPalette.accent)
                Text("正在加载")
                    .font(SYFont.caption)
                    .foregroundStyle(SYPalette.inkTertiary)
                Spacer()
            }
            .padding(.vertical, SYMetric.gapL)
        } else if books.isEmpty, let errorMessage {
            Text(errorMessage)
                .font(SYFont.caption)
                .foregroundStyle(SYPalette.danger)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, SYMetric.gapS)
        } else if books.isEmpty {
            Text("该分类暂时没有内容。")
                .font(SYFont.caption)
                .foregroundStyle(SYPalette.inkTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, SYMetric.gapS)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: SYMetric.gapM) {
                    ForEach(books) { book in
                        bookCard(book)
                    }
                }
                .padding(.horizontal, SYMetric.pagePadding)
            }
            .padding(.horizontal, -SYMetric.pagePadding)
        }
    }

    private var subtitle: String {
        if categories.isEmpty { return "整页发现" }
        return "\(categories.count) 个分类"
    }

    private func bookCard(_ book: SYBook) -> some View {
        Button {
            state.open(.bookDetail(book))
        } label: {
            VStack(alignment: .leading, spacing: SYMetric.gapS) {
                SYCoverView(book: book, width: 96, height: 136, cornerRadius: 10)
                Text(book.name)
                    .font(SYFont.caption.weight(.medium))
                    .foregroundStyle(SYPalette.ink)
                    .lineLimit(1)
                Text(book.author ?? "佚名")
                    .font(SYFont.micro)
                    .foregroundStyle(SYPalette.inkTertiary)
                    .lineLimit(1)
            }
            .frame(width: 96, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    private func loadCategoriesIfNeeded() {
        guard !hasLoadedCategories else { return }
        hasLoadedCategories = true
        categories = state.exploreCategories(for: source)
    }

    @MainActor
    private func loadBooks() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        do {
            let category = categories.isEmpty ? nil : categories[selectedIndex]
            books = try await state.explore(source: source, category: category)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}