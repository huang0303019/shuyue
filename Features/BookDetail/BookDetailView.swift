import SwiftUI

/// 书籍详情页 —— 封面信息、简介、章节目录、加入书架与开始阅读。
/// 从任意书源点进一本书都会落在这一页，目录可逐章直达阅读器。
@MainActor
struct BookDetailView: View {
    let book: SYBook

    @EnvironmentObject private var state: SYAppState
    @Environment(\.dismiss) private var dismiss

    @State private var detailBook: SYBook
    @State private var chapters: [SYChapter] = []

    @State private var isLoadingDetail = true
    @State private var detailError: String?
    @State private var isLoadingTOC = true
    @State private var tocError: String?

    init(book: SYBook) {
        self.book = book
        _detailBook = State(initialValue: book)
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar

            ScrollView {
                VStack(alignment: .leading, spacing: SYMetric.gapL) {
                    header

                    if let detailError {
                        errorBanner(detailError) {
                            Task { await loadDetail() }
                        }
                    }

                    actions

                    if let intro = detailBook.intro, !intro.isEmpty {
                        introCard(intro)
                    }

                    tocSection
                }
                .padding(.horizontal, SYMetric.pagePadding)
                .padding(.vertical, SYMetric.gapM)
                .padding(.bottom, SYMetric.gapHuge * 2)
            }
        }
        .background(SYPalette.paper.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task { await load() }
    }

    // MARK: - 顶栏

    private var topBar: some View {
        HStack(spacing: SYMetric.gapM) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(SYPalette.ink)
                    .frame(width: 38, height: 38)
                    .background(SYPalette.surfaceAlt, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("返回")

            Text(detailBook.name)
                .font(SYFont.appTitle)
                .foregroundStyle(SYPalette.ink)
                .lineLimit(1)

            Spacer(minLength: SYMetric.gapS)
        }
        .padding(.horizontal, SYMetric.pagePadding)
        .padding(.vertical, SYMetric.gapS)
        .frame(minHeight: SYMetric.controlHeight + SYMetric.gapS * 2)
        .background(SYPalette.paper)
    }

    // MARK: - 书籍信息

    private var header: some View {
        HStack(alignment: .top, spacing: SYMetric.gapL) {
            SYCoverView(book: detailBook, width: 116, height: 164)

            VStack(alignment: .leading, spacing: SYMetric.gapS) {
                Text(detailBook.name)
                    .font(SYFont.screenTitle)
                    .foregroundStyle(SYPalette.ink)

                if let author = detailBook.author, !author.isEmpty {
                    Text(author)
                        .font(SYFont.body)
                        .foregroundStyle(SYPalette.inkSecondary)
                }

                if let sourceName = detailBook.sourceName, !sourceName.isEmpty {
                    SYChip(text: sourceName)
                }

                if let lastChapter = detailBook.lastChapter, !lastChapter.isEmpty {
                    Text("更新：" + lastChapter)
                        .font(SYFont.caption)
                        .foregroundStyle(SYPalette.inkTertiary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                metadataLine
            }

            Spacer(minLength: 0)
        }
    }

    private var metadataLine: some View {
        HStack(spacing: SYMetric.gapS) {
            if let count = detailBook.wordCount, !count.isEmpty {
                Text(count)
                    .font(SYFont.caption)
                    .foregroundStyle(SYPalette.inkTertiary)
            }
            if let kind = detailBook.kind, !kind.isEmpty {
                Text(kind)
                    .font(SYFont.caption)
                    .foregroundStyle(SYPalette.inkTertiary)
            }
        }
    }

    private func introCard(_ intro: String) -> some View {
        SYCard {
            VStack(alignment: .leading, spacing: SYMetric.gapS) {
                Text("简介")
                    .font(SYFont.sectionTitle)
                    .foregroundStyle(SYPalette.ink)
                Text(intro)
                    .font(SYFont.body)
                    .foregroundStyle(SYPalette.inkSecondary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - 操作

    private var isOnShelf: Bool { state.isOnShelf(detailBook) }
    private var shelfIndex: Int? {
        guard isOnShelf, let item = state.shelfItem(for: detailBook) else { return nil }
        return item.chapterIndex > 0 ? item.chapterIndex : nil
    }

    private var actions: some View {
        HStack(spacing: SYMetric.gapM) {
            SYButton(
                title: isOnShelf ? "已在书架" : "加入书架",
                systemImage: isOnShelf ? "bookmark.fill" : "bookmark",
                kind: .secondary
            ) {
                toggleShelf()
            }

            SYButton(
                title: shelfIndex == nil ? "开始阅读" : "继续阅读",
                systemImage: "text.book.closed",
                kind: .primary
            ) {
                startReading()
            }
        }
    }

    private func toggleShelf() {
        if isOnShelf {
            state.removeFromShelf(detailBook)
        } else {
            state.addToShelf(detailBook)
        }
    }

    private func startReading() {
        if let index = shelfIndex {
            state.open(.reader(detailBook, index))
        } else {
            state.open(.reader(detailBook, nil))
        }
    }

    // MARK: - 目录

    private var tocSection: some View {
        VStack(alignment: .leading, spacing: SYMetric.gapM) {
            SYSectionHeader(title: "目录", subtitle: chapters.isEmpty ? nil : "共 \(chapters.count) 章")

            if isLoadingTOC {
                HStack(spacing: SYMetric.gapS) {
                    Spacer()
                    ProgressView()
                        .tint(SYPalette.accent)
                    Text("正在加载目录")
                        .font(SYFont.caption)
                        .foregroundStyle(SYPalette.inkTertiary)
                    Spacer()
                }
                .padding(.vertical, SYMetric.gapL)
            } else if let tocError {
                errorBanner(tocError) {
                    Task { await loadTOC() }
                }
            } else if chapters.isEmpty {
                Text("还没有解析到章节，可返回重试或用书源内「详情」规则修正。")
                    .font(SYFont.callout)
                    .foregroundStyle(SYPalette.inkTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, SYMetric.gapM)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(chapters.enumerated()), id: \.offset) { index, chapter in
                        chapterRow(chapter)

                        if index < chapters.count - 1 {
                            Divider()
                                .overlay(SYPalette.border)
                                .padding(.leading, SYMetric.gapL)
                        }
                    }
                }
                .padding(.vertical, 4)
                .background(SYPalette.surface, in: RoundedRectangle(cornerRadius: SYMetric.radiusCard, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: SYMetric.radiusCard, style: .continuous)
                        .stroke(SYPalette.border, lineWidth: 0.8)
                )
                .syCardShadow()
            }
        }
    }

    private func chapterRow(_ chapter: SYChapter) -> some View {
        Button {
            state.open(.reader(detailBook, chapter.index))
        } label: {
            HStack(spacing: SYMetric.gapS) {
                if chapter.isVip {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(SYPalette.gold)
                }
                Text(chapter.title)
                    .font(SYFont.callout)
                    .foregroundStyle(SYPalette.ink)
                    .lineLimit(1)
                Spacer(minLength: SYMetric.gapXS)
                Text("\(chapter.index + 1)")
                    .font(SYFont.micro)
                    .foregroundStyle(SYPalette.inkTertiary)
            }
            .padding(.horizontal, SYMetric.gapL)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 错误横幅

    private func errorBanner(_ message: String, retry: @escaping () -> Void) -> some View {
        HStack(spacing: SYMetric.gapS) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13))
                .foregroundStyle(SYPalette.gold)

            Text(message)
                .font(SYFont.caption)
                .foregroundStyle(SYPalette.inkSecondary)
                .lineLimit(2)

            Spacer(minLength: SYMetric.gapS)

            Button("重试", action: retry)
                .font(SYFont.caption.weight(.semibold))
                .foregroundStyle(SYPalette.accent)
        }
        .padding(SYMetric.gapM)
        .background(SYPalette.surface, in: RoundedRectangle(cornerRadius: SYMetric.radiusControl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SYMetric.radiusControl, style: .continuous)
                .stroke(SYPalette.border, lineWidth: 0.8)
        )
    }

    // MARK: - 加载

    @MainActor
    private func load() async {
        await loadDetail()
        await loadTOC()
    }

    @MainActor
    private func loadDetail() async {
        isLoadingDetail = true
        detailError = nil
        do {
            let updated = try await state.detail(for: detailBook)
            detailBook = updated
        } catch {
            detailError = error.localizedDescription
        }
        isLoadingDetail = false
    }

    @MainActor
    private func loadTOC() async {
        isLoadingTOC = true
        tocError = nil
        do {
            chapters = try await state.chapters(for: detailBook)
        } catch {
            tocError = error.localizedDescription
        }
        isLoadingTOC = false
    }
}