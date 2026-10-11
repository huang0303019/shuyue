import SwiftUI
import Foundation

/// 书悦全局状态：导航 + 书源 / 书架 / 历史 / 阅读设置，并作为 Legado 引擎的唯一入口。
@MainActor
final class SYAppState: ObservableObject {
    // 导航
    @Published var section: SYSection = .bookshelf
    @Published var isDrawerOpen = false
    @Published var path = NavigationPath()

    // 数据
    @Published private(set) var sources: [SYBookSource] = []
    @Published private(set) var shelf: [SYBookshelfItem] = []
    @Published private(set) var history: [SYHistoryEntry] = []
    @Published var settings = SYReaderSettings()

    private let engineCache = SYEngineCache()

    init() {
        loadAll()
    }

    // MARK: - 导航

    func present(_ section: SYSection) {
        self.section = section
        isDrawerOpen = false
        path = NavigationPath()
    }

    func toggleDrawer() {
        isDrawerOpen.toggle()
    }

    func open(_ route: SYRoute) {
        path.append(route)
    }

    // MARK: - 持久化

    private func loadAll() {
        sources = SYLibraryPersistence.load([SYBookSource].self, key: "sources") ?? []
        shelf = SYLibraryPersistence.load([SYBookshelfItem].self, key: "shelf") ?? []
        history = SYLibraryPersistence.load([SYHistoryEntry].self, key: "history") ?? []
        settings = SYLibraryPersistence.load(SYReaderSettings.self, key: "settings") ?? SYReaderSettings()
    }

    private func persistSources() { SYLibraryPersistence.save(sources, key: "sources") }
    private func persistShelf() { SYLibraryPersistence.save(shelf, key: "shelf") }
    private func persistHistory() { SYLibraryPersistence.save(history, key: "history") }
    func persistSettings() { SYLibraryPersistence.save(settings, key: "settings") }

    // MARK: - 书源

    var enabledSources: [SYBookSource] { sources.filter { $0.enabled } }
    var exploreSources: [SYBookSource] { sources.filter { $0.enabled && $0.enabledExplore } }
    var enabledSearchCount: Int { sources.filter { $0.enabled && $0.enabledSearch }.count }

    func source(url: String) -> SYBookSource? {
        sources.first { $0.bookSourceUrl == url }
    }

    /// 从一段文本导入书源（本地粘贴或文件内容）。
    @discardableResult
    func importSources(text: String) -> SYImportSummary {
        let parsed = SYBookSourceStore.parse(text)
        guard !parsed.isEmpty else {
            return .failure("未解析到任何书源，请确认是标准 Legado 书源 JSON（对象或数组）。")
        }
        var added = 0
        var updated = 0
        var issues: [String] = []
        for source in parsed {
            guard !source.bookSourceUrl.isEmpty else {
                issues.append("跳过缺少 bookSourceUrl 的条目")
                continue
            }
            if let index = sources.firstIndex(where: { $0.bookSourceUrl == source.bookSourceUrl }) {
                sources[index] = source
                updated += 1
            } else {
                sources.append(source)
                added += 1
            }
        }
        persistSources()
        return SYImportSummary(added: added, updated: updated, issues: issues)
    }

    /// 从网络地址导入书源（订阅链接）。
    func importSources(remote urlString: String) async -> SYImportSummary {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme != nil else {
            return .failure("地址无效，请填写完整的 http(s) 链接。")
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
            return importSources(text: text)
        } catch {
            return .failure("网络导入失败：\(error.localizedDescription)")
        }
    }

    func toggleSource(_ source: SYBookSource) {
        guard let index = sources.firstIndex(where: { $0.bookSourceUrl == source.bookSourceUrl }) else { return }
        sources[index].enabled.toggle()
        persistSources()
    }

    func deleteSource(_ source: SYBookSource) {
        sources.removeAll { $0.bookSourceUrl == source.bookSourceUrl }
        persistSources()
    }

    func removeAllSources() {
        sources = []
        persistSources()
    }

    func exportSourcesText() -> String {
        SYBookSourceStore.serialize(sources)
    }

    func validate(_ source: SYBookSource) -> [String] {
        SYBookSourceStore.validate(source)
    }

    // MARK: - 引擎

    private func engine(for source: SYBookSource) async -> SYLegadoEngine {
        await engineCache.engine(for: source)
    }

    // MARK: - 搜索

    /// 跨书源并发搜索，返回按书源分组的结果。
    func search(keyword: String, page: Int = 1) async -> [SYSearchGroup] {
        let active = sources.filter { $0.enabled && $0.enabledSearch }
        guard !active.isEmpty else { return [] }

        var jobs: [(url: String, name: String, engine: SYLegadoEngine)] = []
        for source in active {
            let engine = await engine(for: source)
            jobs.append((source.bookSourceUrl, source.bookSourceName, engine))
        }

        let kw = keyword
        return await withTaskGroup(of: SYSearchGroup.self) { group in
            for job in jobs {
                group.addTask {
                    do {
                        let books = try await job.engine.search(keyword: kw, page: page)
                        return SYSearchGroup(sourceUrl: job.url, sourceName: job.name, books: books, error: nil)
                    } catch {
                        return SYSearchGroup(sourceUrl: job.url, sourceName: job.name, books: [], error: error.localizedDescription)
                    }
                }
            }
            var out: [SYSearchGroup] = []
            for await result in group { out.append(result) }
            out.sort { $0.sourceName < $1.sourceName }
            return out
        }
    }

    // MARK: - 发现

    /// exploreUrl 若是 JSON 分类数组则解析为分类列表；否则返回空（走整页发现）。
    func exploreCategories(for source: SYBookSource) -> [SYExploreCategory] {
        guard let raw = source.exploreUrl?.trimmingCharacters(in: .whitespacesAndNewlines),
              raw.hasPrefix("["),
              let data = raw.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return arr.compactMap { obj in
            let title = (obj["title"] as? String) ?? (obj["name"] as? String)
            guard let title, let url = obj["url"] as? String, !url.isEmpty else { return nil }
            return SYExploreCategory(title: title, url: url)
        }
    }

    func explore(source: SYBookSource, category: SYExploreCategory?) async throws -> [SYBook] {
        let engine = await engine(for: source)
        return try await engine.explore(url: category?.url)
    }

    // MARK: - 详情 / 目录 / 正文

    func detail(for book: SYBook) async throws -> SYBook {
        guard let source = source(url: book.sourceUrl) else {
            throw SYEngineError.emptyResult("未找到《\(book.name)》对应的书源")
        }
        let engine = await engine(for: source)
        return try await engine.bookInfo(book)
    }

    func chapters(for book: SYBook) async throws -> [SYChapter] {
        guard let source = source(url: book.sourceUrl) else {
            throw SYEngineError.emptyResult("未找到《\(book.name)》对应的书源")
        }
        let engine = await engine(for: source)
        return try await engine.toc(book)
    }

    /// 读取正文，并沿 nextContentUrl 追页拼接。
    func content(for chapter: SYChapter) async throws -> String {
        guard let source = source(url: chapter.sourceUrl) else {
            throw SYEngineError.emptyResult("未找到章节所属书源")
        }
        let engine = await engine(for: source)
        var result = try await engine.content(chapter)
        var text = result.content
        var hops = 0
        while let next = result.nextUrl, hops < 5 {
            hops += 1
            let nextChapter = SYChapter(title: chapter.title, url: next, sourceUrl: chapter.sourceUrl)
            result = try await engine.content(nextChapter)
            if result.content.isEmpty { break }
            text += "\n" + result.content
        }
        return text
    }

    // MARK: - 书架

    func isOnShelf(_ book: SYBook) -> Bool {
        shelf.contains { $0.book.id == book.id }
    }

    func shelfItem(for book: SYBook) -> SYBookshelfItem? {
        shelf.first { $0.book.id == book.id }
    }

    func addToShelf(_ book: SYBook, group: String = "想读") {
        if let index = shelf.firstIndex(where: { $0.book.id == book.id }) {
            shelf[index].group = group
            shelf[index].updatedAt = Date()
        } else {
            shelf.insert(SYBookshelfItem(book: book, group: group), at: 0)
        }
        persistShelf()
    }

    func removeFromShelf(_ book: SYBook) {
        shelf.removeAll { $0.book.id == book.id }
        persistShelf()
    }

    func setGroup(_ group: String, for book: SYBook) {
        guard let index = shelf.firstIndex(where: { $0.book.id == book.id }) else { return }
        shelf[index].group = group
        shelf[index].updatedAt = Date()
        persistShelf()
    }

    /// 记录阅读进度：同步更新书架进度与阅读历史。
    func updateProgress(book: SYBook, chapterIndex: Int, chapterTitle: String?, chapterCount: Int) {
        if let index = shelf.firstIndex(where: { $0.book.id == book.id }) {
            shelf[index].chapterIndex = chapterIndex
            shelf[index].chapterTitle = chapterTitle
            shelf[index].progress = chapterCount > 0 ? Double(chapterIndex + 1) / Double(chapterCount) : 0
            shelf[index].updatedAt = Date()
            if shelf[index].group == "想读" { shelf[index].group = "在读" }
            persistShelf()
        }
        recordHistory(book: book, chapterTitle: chapterTitle)
    }

    private func recordHistory(book: SYBook, chapterTitle: String?) {
        history.removeAll { $0.bookId == book.id }
        history.insert(SYHistoryEntry(bookId: book.id, book: book, chapterTitle: chapterTitle), at: 0)
        if history.count > 200 { history = Array(history.prefix(200)) }
        persistHistory()
    }

    func clearHistory() {
        history = []
        persistHistory()
    }

    // MARK: - 阅读设置

    func setTheme(_ theme: ReaderTheme) {
        settings.theme = theme
        persistSettings()
    }

    func setFontSize(_ value: Double) {
        settings.fontSize = min(30, max(13, value))
        persistSettings()
    }

    func setLineSpacing(_ value: Double) {
        settings.lineSpacing = min(20, max(2, value))
        persistSettings()
    }

    func setUseSerif(_ value: Bool) {
        settings.useSerif = value
        persistSettings()
    }
}