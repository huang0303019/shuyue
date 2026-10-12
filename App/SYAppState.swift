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

    // 分组展示
    /// 置顶 / 置底记录（bookSourceUrl -> 记录）。
    @Published private(set) var pinRecords: [String: SYSourcePinRecord] = [:]
    /// 折叠中的分组 id（其余默认展开）。
    @Published private(set) var collapsedGroupIDs: Set<String> = []
    /// 是否按分组折叠展示（关闭则回到平铺列表）。
    @Published var groupByList = true

    // 校验
    /// 实跑校验后的行内健康状态（bookSourceUrl -> 摘要），仅在完整校验后写入。
    @Published private(set) var healthBySource: [String: SYSourceValidationSummary] = [:]

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
        pinRecords = SYLibraryPersistence.load([String: SYSourcePinRecord].self, key: "sourcePins") ?? [:]
        collapsedGroupIDs = SYLibraryPersistence.load(Set<String>.self, key: "collapsedGroups") ?? []
        if let grouped = SYLibraryPersistence.load(Bool.self, key: "groupByList") {
            groupByList = grouped
        }
    }

    private func persistSources() { SYLibraryPersistence.save(sources, key: "sources") }
    private func persistShelf() { SYLibraryPersistence.save(shelf, key: "shelf") }
    private func persistHistory() { SYLibraryPersistence.save(history, key: "history") }
    func persistSettings() { SYLibraryPersistence.save(settings, key: "settings") }
    private func persistPins() { SYLibraryPersistence.save(pinRecords, key: "sourcePins") }
    private func persistGroupUI() { SYLibraryPersistence.save(groupByList, key: "groupByList") }

    // MARK: - 分组

    /// 按分组小节视图数据（置顶 -> 普通分组 -> 默认分组 -> 置底）。
    var groupedSections: [SYSourceGroupSection] {
        SYBookSourceGrouping.sections(sources: sources, pinRecords: pinRecords)
    }

    func setGroupByList(_ value: Bool) {
        groupByList = value
        persistGroupUI()
    }

    func toggleGroupCollapsed(_ groupID: String) {
        if collapsedGroupIDs.contains(groupID) {
            collapsedGroupIDs.remove(groupID)
        } else {
            collapsedGroupIDs.insert(groupID)
        }
        SYLibraryPersistence.save(collapsedGroupIDs, key: "collapsedGroups")
    }

    func isGroupCollapsed(_ groupID: String) -> Bool {
        collapsedGroupIDs.contains(groupID)
    }

    /// 置顶：记录 pin 并持久化（不改源数组顺序，由 groupedSections 按 pin 分组展示）。
    func pinToTop(_ source: SYBookSource) {
        pinRecords[source.bookSourceUrl] = SYSourcePinRecord(position: .top, pinnedAt: Date())
        persistPins()
    }

    /// 置底。
    func pinToBottom(_ source: SYBookSource) {
        pinRecords[source.bookSourceUrl] = SYSourcePinRecord(position: .bottom, pinnedAt: Date())
        persistPins()
    }

    /// 取消置顶 / 置底。
    func unpin(_ source: SYBookSource) {
        pinRecords[source.bookSourceUrl] = nil
        persistPins()
    }

    func pinRecord(for source: SYBookSource) -> SYSourcePinRecord? {
        pinRecords[source.bookSourceUrl]
    }

    /// 重命名 / 移动分组：把一组来源的 bookSourceGroup 设为新值；空值清除分组（回到默认分组）。
    func setGroup(_ group: String, for sourcesToMove: [SYBookSource]) {
        let trimmed = group.trimmingCharacters(in: .whitespacesAndNewlines)
        let ids = Set(sourcesToMove.map(\.bookSourceUrl))
        guard !ids.isEmpty else { return }
        var changed = false
        for idx in sources.indices where ids.contains(sources[idx].bookSourceUrl) {
            let newGroup = trimmed.isEmpty ? nil : trimmed
            if sources[idx].bookSourceGroup != newGroup {
                sources[idx].bookSourceGroup = newGroup
                changed = true
            }
        }
        if changed { persistSources() }
    }

    /// 每组数量（供「移动到分组」「按域名分组」清单使用）。
    func groupCounts(excluding excluded: String = "") -> [(name: String, count: Int)] {
        SYBookSourceGrouping.groupCounts(sources: sources, excluding: excluded)
    }

    /// 按域名分组：每个源的 bookSourceGroup 改为其 URL 主机名。返回改动的源数量。
    @discardableResult
    func groupByDomain() -> Int {
        var changed = 0
        for idx in sources.indices {
            let domain = SYBookSourceGrouping.domain(of: sources[idx].bookSourceUrl)
            let newGroup = domain.isEmpty ? nil : domain
            if sources[idx].bookSourceGroup != newGroup {
                sources[idx].bookSourceGroup = newGroup
                changed += 1
            }
        }
        if changed > 0 { persistSources() }
        return changed
    }

    /// 批量删除书源（删除整个分组时使用），同时清除 pin 与行内健康结论。
    func deleteSources(_ sourcesToDelete: [SYBookSource]) {
        let urls = Set(sourcesToDelete.map(\.bookSourceUrl))
        guard !urls.isEmpty else { return }
        sources.removeAll { urls.contains($0.bookSourceUrl) }
        for url in urls {
            pinRecords[url] = nil
            healthBySource[url] = nil
        }
        persistSources()
        persistPins()
    }

    /// 整组启用 / 停用：按 bookSourceUrl 集合批量设置 enabled。
    func setSourcesEnabled(_ urls: [String], enabled: Bool) {
        let set = Set(urls)
        guard !set.isEmpty else { return }
        var changed = false
        for idx in sources.indices where set.contains(sources[idx].bookSourceUrl) {
            if sources[idx].enabled != enabled {
                sources[idx].enabled = enabled
                changed = true
            }
        }
        if changed { persistSources() }
    }

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
                // 更新已存在的书源：保留本地自定义排序（与墨悦 manualDefaults 的 keepCustomOrder 一致）。
                var merged = source
                merged.customOrder = sources[index].customOrder
                sources[index] = merged
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

    // MARK: - 深链导入（shuyue://）

    /// 本次启动以来深链 / 分享扩展累计导入结果（分享扩展一次可回调多条，逐条归并展示）。
    @Published private(set) var deepLinkImported = 0
    @Published private(set) var deepLinkUpdated = 0
    @Published private(set) var deepLinkIssues: [String] = []
    /// 深链导入结果提示，由外壳在底部 toast 展示；置空即关闭。
    @Published var deepLinkNotice: String?

    /// 处理 `shuyue://` 深链：解析后导入书源并跳到书源页。返回 true 表示已消费。
    @discardableResult
    func handleDeepLink(_ url: URL) -> Bool {
        guard let action = SYDeepLinkParser.parse(url) else { return false }
        switch action {
        case .openSources:
            present(.sources)
        case .importText(let text):
            importFromDeepLink(text: text)
        case .importRemote(let remote):
            let notice = deepLinkNotice
            deepLinkNotice = notice ?? "正在导入远程书源…"
            Task { await importFromDeepLink(remote: remote) }
        }
        return true
    }

    private func importFromDeepLink(text: String) {
        let summary = importSources(text: text)
        accumulate(summary)
        present(.sources)
        deepLinkNotice = deepLinkSummaryText()
    }

    private func importFromDeepLink(remote urlString: String) async {
        let summary = await importSources(remote: urlString)
        accumulate(summary)
        present(.sources)
        deepLinkNotice = deepLinkSummaryText()
    }

    private func accumulate(_ summary: SYImportSummary) {
        if summary.isFailure {
            deepLinkIssues.append(summary.failureMessage ?? "导入失败")
        } else {
            deepLinkImported += summary.added
            deepLinkUpdated += summary.updated
            deepLinkIssues.append(contentsOf: summary.issues)
        }
    }

    private func deepLinkSummaryText() -> String {
        var parts: [String] = []
        if deepLinkImported > 0 { parts.append("新增 \(deepLinkImported) 个书源") }
        if deepLinkUpdated > 0 { parts.append("更新 \(deepLinkUpdated) 个书源") }
        if parts.isEmpty { parts.append("没有可导入的书源") }
        if !deepLinkIssues.isEmpty { parts.append(deepLinkIssues.joined(separator: "；")) }
        return parts.joined(separator: "，")
    }

    // MARK: 导入审查流程

    /// 网络订阅地址解析（不写库），供导入确认清单先行展示。
    func parseRemote(urlString: String) async -> Result<[SYBookSource], Error> {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme != nil else {
            return .failure(SYImportMessage(message: "地址无效，请填写完整的 http(s) 链接。"))
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
            let parsed = SYBookSourceStore.parse(text)
            guard !parsed.isEmpty else {
                return .failure(SYImportMessage(message: "未解析到任何书源，请确认是标准 Legado 书源 JSON。"))
            }
            return .success(parsed)
        } catch {
            return .failure(SYImportMessage(message: "网络导入失败：\(error.localizedDescription)"))
        }
    }

    /// 把已解析结果构建成导入确认计划（不写库）。库的 lastUpdateTime 快照一次，
    /// 供条目标记 新增 / 更新 / 已有。
    func importPlan(from parsed: [SYBookSource]) -> SYImportPlan {
        let clocks = Dictionary(
            uniqueKeysWithValues: sources.map { ($0.bookSourceUrl, $0.lastUpdateTime ?? 0) }
        )
        return SYImportPlan(incoming: parsed) { clocks[$0] }
    }

    /// 确认导入：把计划中勾选的行按选项合并后写入本地库。
    @discardableResult
    func confirmImport(_ plan: SYImportPlan, options: SYImportOptions) -> SYImportSummary {
        let selected = plan.selectedSources
        guard !selected.isEmpty else {
            return .failure("未选择任何书源。")
        }
        var added = 0
        var updated = 0
        var issues: [String] = []
        for incoming in selected {
            guard !incoming.bookSourceUrl.isEmpty else {
                issues.append("跳过缺少 bookSourceUrl 的条目：\(incoming.bookSourceName)")
                continue
            }
            let merged = options.merged(incoming: incoming, local: source(url: incoming.bookSourceUrl))
            if let index = sources.firstIndex(where: { $0.bookSourceUrl == merged.bookSourceUrl }) {
                sources[index] = merged
                updated += 1
            } else {
                sources.append(merged)
                added += 1
            }
        }
        persistSources()
        return SYImportSummary(added: added, updated: updated, issues: issues)
    }

    func toggleSource(_ source: SYBookSource) {
        guard let index = sources.firstIndex(where: { $0.bookSourceUrl == source.bookSourceUrl }) else { return }
        sources[index].enabled.toggle()
        persistSources()
    }

    /// 保存规则编辑器写回的书源：同 URL 原地替换（保持顺序），否则按新书源追加。
    /// 规则可能已变化，旧实跑校验结论与缓存引擎（携带旧规则与旧源变量）一并失效。
    func updateSource(_ updated: SYBookSource) {
        if let index = sources.firstIndex(where: { $0.bookSourceUrl == updated.bookSourceUrl }) {
            sources[index] = updated
        } else {
            sources.append(updated)
        }
        healthBySource[updated.bookSourceUrl] = nil
        let url = updated.bookSourceUrl
        Task { await engineCache.dropEngine(for: url) }
        persistSources()
    }

    func deleteSource(_ source: SYBookSource) {
        sources.removeAll { $0.bookSourceUrl == source.bookSourceUrl }
        pinRecords[source.bookSourceUrl] = nil
        healthBySource[source.bookSourceUrl] = nil
        persistSources()
        persistPins()
    }

    func removeAllSources() {
        sources = []
        persistSources()
    }

    func exportSourcesText() -> String {
        SYBookSourceStore.serialize(sources)
    }

    /// 按指定 bookSourceUrl 子集导出 JSON（供「复制分组 JSON」使用）。
    func exportSourcesText(ids: [String]) -> String {
        let set = Set(ids)
        guard !set.isEmpty else { return "[]" }
        return SYBookSourceStore.serialize(sources.filter { set.contains($0.bookSourceUrl) })
    }

    func validate(_ source: SYBookSource) -> [String] {
        SYBookSourceStore.validate(source)
    }

    /// 记录一次完整实跑校验的行内健康结论。
    func recordHealth(_ summary: SYSourceValidationSummary, for url: String) {
        healthBySource[url] = summary
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

    // MARK: - 登录

    /// 解析书源登录界面（兼容数组 / `{title,params,urls}` 与动态 JS 形态）。
    func loadLoginUi(for source: SYBookSource) async -> SYLoginUi? {
        let engine = await engine(for: source)
        return await engine.loadLoginUi()
    }

    /// 执行书源登录：表单值填充 loginUrl → Cookie 自动保存 → loginCheckJs 校验。
    /// `urlAction` 为对象形态 loginUi 中选中的提交目标；为空时使用书源 loginUrl。
    func login(source: SYBookSource, formValues: [String: String], urlAction: SYLoginUrlAction? = nil) async throws -> SYLoginResult {
        let engine = await engine(for: source)
        return try await engine.login(formValues: formValues, urlAction: urlAction)
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
