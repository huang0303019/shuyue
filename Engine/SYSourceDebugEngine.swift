import Foundation
import Combine

// MARK: - 书源规则调试引擎

/// 面向单个书源的分阶段规则调试器：搜索 / 详情 / 目录 / 正文 / 全流程。
///
/// 每次运行清空日志，执行对应引擎链路，并把链路中注入的 `SYDebugEvent`
/// 转换为面板日志条目实时追加。事件在后台线程产生，通过 `@MainActor`
/// 任务回到主线程更新 `@Published` 状态。
@MainActor
final class SYSourceDebugEngine: ObservableObject {

    @Published private(set) var logs: [SYDebugLogEntry] = []
    @Published private(set) var isRunning = false

    let source: SYBookSource

    /// 网络会话；nil 时使用引擎默认（生产调用不传，测试注入 MockURLProtocol）。
    private let session: URLSession?

    /// 日志条目上限：一次全流程可能产出上千条规则事件，保留最近部分。
    private static let entryLimit = 800

    private var currentStage = "搜索"

    init(source: SYBookSource, session: URLSession? = nil) {
        self.source = source
        self.session = session
    }

    // MARK: - 日志维护

    func clear() {
        logs.removeAll()
    }

    private func append(_ entry: SYDebugLogEntry) {
        logs.append(entry)
        if logs.count > Self.entryLimit {
            logs.removeFirst(logs.count - Self.entryLimit)
        }
    }

    private func appendLog(_ level: SYDebugLevel, step: String, summary: String, detail: String? = nil) {
        append(SYDebugLogEntry(level: level, step: step, summary: summary, detail: detail))
    }

    /// 生成事件接收器：捕获当前阶段名，事件回到主线程追加。
    private func makeSink() -> SYDebugSink {
        let stage = currentStage
        return { [weak self] event in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.append(SYDebugLogEntry.make(event: event, stage: stage))
            }
        }
    }

    private func resetRun(stage: String) {
        currentStage = stage
        logs.removeAll()
        isRunning = true
    }

    private func finishRun() {
        isRunning = false
    }

    private func elapsed(_ t0: Date) -> String {
        String(format: "%.2fs", Date().timeIntervalSince(t0))
    }

    // MARK: - 搜索

    func runSearch(keyword: String, page: Int = 1) async {
        guard !keyword.trimmingCharacters(in: .whitespaces).isEmpty else {
            appendLog(.warning, step: "搜索", summary: "请输入搜索关键词")
            return
        }
        resetRun(stage: "搜索")
        appendLog(.info, step: "搜索", summary: "关键词: \(keyword)，页码: \(page)")

        let engine = SYLegadoEngine(source: source, session: session)
        let t0 = Date()
        do {
            let books = try await engine.search(keyword: keyword, page: page, debug: makeSink())
            if books.isEmpty {
                appendLog(.warning, step: "搜索结果", summary: "没有搜到结果（\(elapsed(t0))）")
            } else {
                appendLog(.success, step: "搜索结果", summary: "搜到 \(books.count) 本（\(elapsed(t0))）")
                for book in books.prefix(5) {
                    appendLog(.info, step: "搜索结果", summary: book.name + (book.author.map { " · \($0)" } ?? ""))
                }
            }
        } catch {
            appendLog(.error, step: "搜索", summary: error.localizedDescription)
        }
        finishRun()
    }

    // MARK: - 详情

    func runDetail(url: String) async {
        await runBookStage(stage: "详情", url: url) { engine, book in
            try await engine.bookInfo(book, debug: self.makeSink())
        }
    }

    // MARK: - 目录

    func runToc(url: String) async {
        await runBookStage(stage: "目录", url: url) { engine, book in
            try await engine.toc(book, debug: self.makeSink())
        }
    }

    // MARK: - 正文

    func runContent(url: String) async {
        guard !url.trimmingCharacters(in: .whitespaces).isEmpty else {
            appendLog(.warning, step: "正文", summary: "请输入章节 URL")
            return
        }
        resetRun(stage: "正文")
        appendLog(.info, step: "正文", summary: "章节 URL: \(url)")

        let engine = SYLegadoEngine(source: source, session: session)
        let chapter = SYChapter(title: "调试章节", url: url, sourceUrl: source.bookSourceUrl)
        let t0 = Date()
        do {
            let result = try await engine.content(chapter, debug: makeSink())
            let chars = result.content.count
            appendLog(
                .success,
                step: "正文",
                summary: "正文 \(chars) 字符（\(elapsed(t0))）" + (result.nextUrl.map { " · 下一页: \($0)" } ?? ""),
                detail: result.content.prefix(500).description
            )
        } catch {
            appendLog(.error, step: "正文", summary: error.localizedDescription)
        }
        finishRun()
    }

    // MARK: - 全流程

    /// 搜索 → 第一本详情 → 目录 → 第一章正文，依次串联。
    func runFullPipeline(keyword: String) async {
        guard !keyword.trimmingCharacters(in: .whitespaces).isEmpty else {
            appendLog(.warning, step: "全流程", summary: "请输入搜索关键词")
            return
        }
        resetRun(stage: "流程")
        appendLog(.info, step: "流程", summary: "全流程调试，关键词: \(keyword)")

        let engine = SYLegadoEngine(source: source, session: session)
        do {
            // ① 搜索
            currentStage = "搜索"
            let t0 = Date()
            let books = try await engine.search(keyword: keyword, page: 1, debug: makeSink())
            guard let book = books.first else {
                appendLog(.warning, step: "全流程", summary: "搜索无结果，流程终止（\(elapsed(t0))）")
                finishRun()
                return
            }
            appendLog(.success, step: "全流程", summary: "搜索命中: \(book.name)（\(elapsed(t0))）")

            // ② 详情
            currentStage = "详情"
            let t1 = Date()
            let info = try await engine.bookInfo(book, debug: makeSink())
            appendLog(.success, step: "全流程", summary: "详情解析完成（\(elapsed(t1))）: \(info.name) · \(info.author ?? "-")")

            // ③ 目录
            currentStage = "目录"
            let t2 = Date()
            let chapters = try await engine.toc(info, debug: makeSink())
            guard let firstChapter = chapters.first else {
                appendLog(.warning, step: "全流程", summary: "目录为空，流程终止（\(elapsed(t2))）")
                finishRun()
                return
            }
            appendLog(.success, step: "全流程", summary: "目录 \(chapters.count) 章（\(elapsed(t2))）: 首章 \(firstChapter.title)")

            // ④ 正文
            currentStage = "正文"
            let t3 = Date()
            let content = try await engine.content(firstChapter, debug: makeSink())
            appendLog(.success, step: "全流程", summary: "正文 \(content.content.count) 字符（\(elapsed(t3))）")
        } catch {
            appendLog(.error, step: "全流程", summary: error.localizedDescription)
        }
        finishRun()
    }

    // MARK: - 共用

    /// 详情/目录共用：以单个 URL 构造书籍对象驱动引擎。
    private func runBookStage(stage: String, url: String, run: (SYLegadoEngine, SYBook) async throws -> Void) async {
        guard !url.trimmingCharacters(in: .whitespaces).isEmpty else {
            appendLog(.warning, step: stage, summary: "请输入 \(stage) URL")
            return
        }
        resetRun(stage: stage)
        appendLog(.info, step: stage, summary: "URL: \(url)")

        let engine = SYLegadoEngine(source: source, session: session)
        let book = SYBook(name: "调试书籍", sourceUrl: source.bookSourceUrl, bookUrl: url, detailRequestUrl: url)
        do {
            try await run(engine, book)
            appendLog(.success, step: stage, summary: "\(stage) 解析完成")
        } catch {
            appendLog(.error, step: stage, summary: error.localizedDescription)
        }
        finishRun()
    }
}
