import Foundation
import Combine

// MARK: - 五阶段校验模型（对齐 Legado CheckSource 语义）

/// 校验阶段：搜索 / 发现 / 详情 / 目录 / 正文，按运行顺序排列。
enum SYValidationStage: Int, CaseIterable, Identifiable {
    case search = 0
    case discovery
    case detail
    case toc
    case content

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .search: return "搜索"
        case .discovery: return "发现"
        case .detail: return "详情"
        case .toc: return "目录"
        case .content: return "正文"
        }
    }

    var explanation: String {
        switch self {
        case .search: return "用测试关键词搜索并解析结果"
        case .discovery: return "请求发现页并解析书单"
        case .detail: return "获取并解析书籍详情"
        case .toc: return "解析第一本书的章节目录"
        case .content: return "获取第一章正文内容"
        }
    }

    var symbol: String {
        switch self {
        case .search: return "magnifyingglass"
        case .discovery: return "safari"
        case .detail: return "book"
        case .toc: return "list.bullet.rectangle"
        case .content: return "text.alignleft"
        }
    }
}

enum SYStageStatus: Equatable {
    case pending, running, pass, fail, skipped
}

/// 失败分类：与 Legado 写入书源的分类名称保持一致。
enum SYFailureCategory: Equatable {
    /// 搜索链接规则为空或站点响应但缺少规则。
    case ruleMissing
    /// 搜索已运行但没有搜到书。
    case searchFailed
    /// 发现已运行但没有发现书。
    case discoveryFailed
    /// 目录解析结果为空。
    case tocEmpty
    /// 正文解析结果为空。
    case contentEmpty
    /// 整个校验超过整体超时。
    case timeout
    /// JS 异常逸出规则管道。
    case jsError
    /// 网络 / 超时 / 运行时错误。
    case siteError

    var title: String {
        switch self {
        case .ruleMissing: return "规则缺失"
        case .searchFailed: return "搜索失效"
        case .discoveryFailed: return "发现失效"
        case .tocEmpty: return "目录失效"
        case .contentEmpty: return "正文失效"
        case .timeout: return "校验超时"
        case .jsError: return "JS 失效"
        case .siteError: return "网站失效"
        }
    }

    /// 过滤桶，供结果列表归类。
    enum Bucket { case ruleMissing, parseFailed, environment }

    var bucket: Bucket {
        switch self {
        case .ruleMissing: return .ruleMissing
        case .searchFailed, .discoveryFailed, .tocEmpty, .contentEmpty: return .parseFailed
        case .timeout, .jsError, .siteError: return .environment
        }
    }

    /// 传输 / 运行时异常逸出某个探测后中止当前源；普通空解析结果继续另一条轨道。
    var stopsCurrentSource: Bool {
        switch self {
        case .timeout, .jsError, .siteError: return true
        case .ruleMissing, .searchFailed, .discoveryFailed, .tocEmpty, .contentEmpty:
            return false
        }
    }
}

struct SYStageOutcome: Equatable {
    var status: SYStageStatus = .pending
    var summary: String = ""
}

/// 整体结论，作为书源列表中的行内徽章。
enum SYSourceHealth: Equatable {
    case passed          // 所有阶段通过 → 验证通过
    case fetchError      // 除正文外任一段失败 → 抓取异常
    case contentError    // 仅正文失败 → 正文异常
}

/// 每次校验后持久化到行内徽章的最小摘要。
struct SYSourceValidationSummary: Equatable {
    var health: SYSourceHealth
    var responseMs: Int64
}

/// 单个书源的校验进度与结果。
struct SYCheckItem: Identifiable {
    let id = UUID()
    let source: SYBookSource
    var stages: [SYStageOutcome] = SYValidationStage.allCases.map { _ in SYStageOutcome() }
    var responseTime: Int64 = 0
    var failureCategory: SYFailureCategory? = nil

    func outcome(_ stage: SYValidationStage) -> SYStageOutcome { stages[stage.rawValue] }

    var isFinished: Bool {
        !stages.contains { $0.status == .pending || $0.status == .running }
    }

    /// 仅用于 UI 汇总显示；最终健康由 health 判断（无入口的全跳过不算通过）。
    var overallPass: Bool {
        stages.allSatisfy { $0.status == .pass || $0.status == .skipped }
    }

    var health: SYSourceHealth? {
        guard isFinished else { return nil }
        if failureCategory != nil {
            let failed = stages.filter { $0.status == .fail }
            if failed.count == 1, outcome(.content).status == .fail {
                return .contentError
            }
            return .fetchError
        }
        return .passed
    }
}

// MARK: - 单源五阶段校验器

/// 对单个书源实跑 搜索 → 发现 → 详情 → 目录 → 正文 五阶段。
/// 引擎是 actor，本类在主线程持有可观察状态，供校验面板实时刷新。
@MainActor
final class SYHealthChecker: ObservableObject, Identifiable {
    let id = UUID()

    @Published private(set) var item: SYCheckItem?
    @Published private(set) var isRunning = false

    /// 测试注入的 URLSession；nil 时使用引擎默认网络。
    private let session: URLSession?
    /// 单书源整体校验超时（秒）。
    var timeoutSeconds: TimeInterval = 120
    /// 默认测试关键词，书源 ruleSearch.checkKeyWord 可覆盖。
    var defaultKeyword = "我的"

    private var runningTask: Task<Void, Never>?

    init(session: URLSession? = nil) {
        self.session = session
    }

    func start(source: SYBookSource) {
        runningTask?.cancel()
        item = SYCheckItem(source: source)
        isRunning = true

        let engine = SYLegadoEngine(source: source, session: session)
        let keyword = Self.keyword(for: source, defaultKeyword: defaultKeyword)
        let t0 = CFAbsoluteTimeGetCurrent()

        runningTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.withOverallTimeout(seconds: self.timeoutSeconds) {
                    await self.runStages(source: source, engine: engine, keyword: keyword)
                }
            } catch is SYCheckTimeoutError {
                self.markTimedOut()
            } catch is CancellationError {
                // 用户取消：保留已有进度结果。
            } catch {
                if self.item?.failureCategory == nil {
                    self.recordFailure(.siteError)
                }
            }
            // 致命错误 / 提前返回路径下，剩余的 pending 阶段统一标记为跳过，
            // 保证 item.isFinished 永远收敛（避免 UI 卡在“进行中”）。
            self.skipPendingStages()
            self.finish(t0: t0)
        }
    }

    func cancel() {
        runningTask?.cancel()
        runningTask = nil
        isRunning = false
    }

    // MARK: - 阶段执行

    private func runStages(source: SYBookSource, engine: SYLegadoEngine, keyword: String) async {
        let searchAvailable = source.enabledSearch
            && !(source.searchUrl?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let discoveryAvailable = source.enabledExplore
            && !(source.exploreUrl?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)

        var hasBook = false

        // 1. 搜索轨道
        if searchAvailable {
            setStage(.search, .running, "用「\(keyword)」搜索")
            do {
                let books = try await engine.search(keyword: keyword, page: 1)
                if books.isEmpty {
                    setStage(.search, .fail, "搜索无结果")
                    recordFailure(.searchFailed)
                } else {
                    setStage(.search, .pass, "命中 \(books.count) 本")
                    hasBook = true
                    guard await runBookTrack(book: books[0], engine: engine) else { return }
                }
            } catch {
                let category = category(for: error, stage: .search)
                setStage(.search, .fail, message(for: error))
                recordFailure(category)
                if category.stopsCurrentSource { return }
            }
        } else {
            setStage(.search, .skipped, "未配置搜索")
        }

        // 2. 发现轨道（搜索未提供可用书籍时才继续跑详情链）
        if discoveryAvailable {
            setStage(.discovery, .running, "请求发现页")
            do {
                let books = try await engine.explore(url: nil)
                if books.isEmpty {
                    setStage(.discovery, .fail, "发现无结果")
                    recordFailure(.discoveryFailed)
                } else {
                    setStage(.discovery, .pass, "命中 \(books.count) 本")
                    if !hasBook {
                        hasBook = true
                        guard await runBookTrack(book: books[0], engine: engine) else { return }
                    }
                }
            } catch {
                let category = category(for: error, stage: .discovery)
                setStage(.discovery, .fail, message(for: error))
                recordFailure(category)
                if category.stopsCurrentSource { return }
            }
        } else {
            setStage(.discovery, .skipped, "未配置发现")
        }

        // 3. 两个入口都不可用 → 整源缺少可用规则
        if !searchAvailable && !discoveryAvailable, item?.failureCategory == nil {
            recordFailure(.ruleMissing)
        }

        // 4. 未运行的阶段标记为跳过
        skipPendingStages()
    }

    /// 详情 → 目录 → 正文 的书籍链路。返回 false 表示应中止当前源（致命错误）。
    private func runBookTrack(book: SYBook, engine: SYLegadoEngine) async -> Bool {
        // 详情
        setStage(.detail, .running, "请求详情页")
        do {
            let updated = try await engine.bookInfo(book)
            let name = updated.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else {
                setStage(.detail, .fail, "详情名为空")
                recordFailure(.ruleMissing)
                return false
            }
            setStage(.detail, .pass, "《\(name)》")
        } catch {
            let category = category(for: error, stage: .detail)
            setStage(.detail, .fail, message(for: error))
            recordFailure(category)
            return !category.stopsCurrentSource
        }

        // 目录
        setStage(.toc, .running, "解析章节目录")
        do {
            let chapters = try await engine.toc(book)
            guard let first = chapters.first(where: { !$0.title.isEmpty }) else {
                setStage(.toc, .fail, "目录为空")
                recordFailure(.tocEmpty)
                return true
            }
            setStage(.toc, .pass, "\(chapters.count) 章")

            // 正文
            setStage(.content, .running, "抓取第一章正文")
            do {
                let result = try await engine.content(first)
                let count = result.content.trimmingCharacters(in: .whitespacesAndNewlines).count
                guard count > 0 else {
                    setStage(.content, .fail, "正文为空")
                    recordFailure(.contentEmpty)
                    return true
                }
                setStage(.content, .pass, "\(count) 字")
                return true
            } catch {
                let category = category(for: error, stage: .content)
                setStage(.content, .fail, message(for: error))
                recordFailure(category)
                return !category.stopsCurrentSource
            }
        } catch {
            let category = category(for: error, stage: .toc)
            setStage(.toc, .fail, message(for: error))
            recordFailure(category)
            return !category.stopsCurrentSource
        }
    }

    // MARK: - 状态维护

    private func setStage(_ stage: SYValidationStage, _ status: SYStageStatus, _ summary: String = "") {
        guard var item else { return }
        item.stages[stage.rawValue] = SYStageOutcome(status: status, summary: summary)
        self.item = item
    }

    /// 只记录首次根因失败，后续阶段不覆盖。
    private func recordFailure(_ category: SYFailureCategory) {
        guard var item, item.failureCategory == nil else { return }
        item.failureCategory = category
        self.item = item
    }

    private func skipPendingStages() {
        guard var item else { return }
        for stage in SYValidationStage.allCases where item.stages[stage.rawValue].status == .pending {
            item.stages[stage.rawValue] = SYStageOutcome(status: .skipped, summary: "—")
        }
        self.item = item
    }

    private func markTimedOut() {
        guard var item else { return }
        for stage in SYValidationStage.allCases {
            switch item.stages[stage.rawValue].status {
            case .running:
                item.stages[stage.rawValue] = SYStageOutcome(status: .fail, summary: "校验超时")
            case .pending:
                item.stages[stage.rawValue] = SYStageOutcome(status: .skipped, summary: "—")
            default:
                break
            }
        }
        self.item = item
        recordFailure(.timeout)
    }

    private func finish(t0: CFAbsoluteTime) {
        let elapsed = Int64((CFAbsoluteTimeGetCurrent() - t0) * 1000)
        if var item {
            item.responseTime = elapsed
            self.item = item
        }
        isRunning = false
    }

    // MARK: - 错误分类

    private func category(for error: Error, stage: SYValidationStage) -> SYFailureCategory {
        switch error {
        case SYEngineError.network, SYEngineError.badURL:
            return .siteError
        case SYEngineError.jsError:
            return .jsError
        case SYEngineError.emptyResult:
            switch stage {
            case .search: return .searchFailed
            case .discovery: return .discoveryFailed
            case .toc: return .tocEmpty
            case .content: return .contentEmpty
            case .detail: return .ruleMissing
            }
        case SYEngineError.ruleNotMatched, SYEngineError.jsonPathNotFound, SYEngineError.unsupportedRule:
            return .ruleMissing
        default:
            return .siteError
        }
    }

    private func message(for error: Error) -> String {
        if let e = error as? SYEngineError {
            return e.errorDescription ?? "校验失败"
        }
        return error.localizedDescription
    }

    static func keyword(for source: SYBookSource, defaultKeyword: String = "我的") -> String {
        let custom = source.ruleSearch.checkKeyWord?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return custom.isEmpty ? defaultKeyword : custom
    }

    // MARK: - 整体超时

    private struct SYCheckTimeoutError: Error {}

    private func withOverallTimeout<T>(
        seconds: TimeInterval,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(max(1, seconds) * 1_000_000_000))
                throw SYCheckTimeoutError()
            }
            guard let result = try await group.next() else {
                throw SYCheckTimeoutError()
            }
            group.cancelAll()
            return result
        }
    }
}