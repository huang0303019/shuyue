import XCTest
@testable import ShuYue

// MARK: - 规则调试器离线校验

final class SYDebugTests: XCTestCase {

    override func setUp() {
        super.setUp()
        MockURLProtocol.handler = nil
    }

    // MARK: - 事件 → 日志条目转换

    func testEventToEntryMapping() {
        let stage = "搜索"

        let request = SYDebugLogEntry.make(
            event: .requestSent(url: "https://fanqienovel.com/api/search?key=x", method: "get", headers: [:]),
            stage: stage
        )
        XCTAssertEqual(request.level, .info)
        XCTAssertEqual(request.step, "[搜索] 请求")
        XCTAssertTrue(request.summary.contains("GET"))
        XCTAssertTrue(request.summary.contains("fanqienovel.com"))

        let response = SYDebugLogEntry.make(
            event: .responseReceived(url: "https://fanqienovel.com/api/search?key=x", statusCode: 200, bytes: 128, preview: "{\"data\":1}", truncated: false),
            stage: stage
        )
        XCTAssertEqual(response.level, .info)
        XCTAssertTrue(response.summary.contains("200"))

        let errorResponse = SYDebugLogEntry.make(
            event: .responseReceived(url: "https://fanqienovel.com/404", statusCode: 404, bytes: 0, preview: "", truncated: false),
            stage: stage
        )
        XCTAssertEqual(errorResponse.level, .warning, ">=400 状态码应标 warning")

        let js = SYDebugLogEntry.make(
            event: .jsExecuted(index: 1, script: "decodePua(result)", result: "神秘复苏"),
            stage: stage
        )
        XCTAssertEqual(js.level, .pipeline)
        XCTAssertTrue(js.summary.contains("神秘复苏"))
        XCTAssertNotNil(js.detail)
        XCTAssertTrue(js.detail!.contains("decodePua"))

        let final = SYDebugLogEntry.make(
            event: .finalResult(value: "我的治愈系游戏", elapsedMs: 0.5),
            stage: stage
        )
        XCTAssertEqual(final.level, .success)
        XCTAssertTrue(final.summary.contains("我的治愈系游戏"))
        XCTAssertTrue(final.summary.contains("0.5 ms"))

        let emptyFinal = SYDebugLogEntry.make(
            event: .finalResult(value: "", elapsedMs: 0.3),
            stage: stage
        )
        XCTAssertEqual(emptyFinal.level, .warning, "空最终值应标 warning")

        let err = SYDebugLogEntry.make(
            event: .error(step: "搜索", message: "网络不可用"),
            stage: stage
        )
        XCTAssertEqual(err.level, .error)
        XCTAssertTrue(err.summary.contains("网络不可用"))

        let content = SYDebugLogEntry.make(
            event: .contentSet(contentType: "JSON", length: 64, preview: "{\"a\":1}", url: "https://x"),
            stage: stage
        )
        XCTAssertEqual(content.level, .info)
        XCTAssertTrue(content.step.contains("原始数据"))
    }

    // MARK: - 规则求值器事件

    func testRuleEvaluatorEmitsDebugEvents() throws {
        let html = """
        <html><body><ul id="list"><li class="item"><a href="/book/1">书名一</a></li></ul></body></html>
        """
        let root = SYHTMLParser.parse(html)

        var events: [SYDebugEvent] = []
        let sink: SYDebugSink = { events.append($0) }

        let context = SYRuleContext(htmlRoot: root, debug: sink)
        let value = SYRuleEvaluator.string("css:#list .item@css:a@text", context: context)
        XCTAssertEqual(value, "书名一")

        let kinds = events.map { Self.kind(of: $0) }
        XCTAssertTrue(kinds.contains("rulesParsed"), "应发出规则解析事件，实际：\(kinds)")
        XCTAssertTrue(kinds.contains("beforeExtract"), "应发出子规则执行事件，实际：\(kinds)")
        XCTAssertTrue(kinds.contains("afterExtractValue"), "应发出提取结果事件，实际：\(kinds)")
        XCTAssertTrue(kinds.contains("finalResult"), "应发出最终结果事件，实际：\(kinds)")

        if case let .rulesParsed(_, segments) = events[0] {
            XCTAssertEqual(segments.count, 3, "css:@css:@text 应拆分为 3 段")
        } else {
            XCTFail("首事件应为规则解析")
        }
    }

    // MARK: - 搜索链路事件捕获（真实番茄书源 + Mock）

    func testSearchChainCapturesEvents() async throws {
        let json = try fixture("fanqie-source")
        let sources = SYBookSourceStore.parse(json)
        let source = try XCTUnwrap(sources.first)

        let responseText = try fixture("fanqie-search-response")
        MockURLProtocol.handler = { request in
            let data = Data(responseText.utf8)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, data)
        }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)

        var events: [SYDebugEvent] = []
        let sink: SYDebugSink = { events.append($0) }

        let engine = SYLegadoEngine(source: source, session: session)
        let books = try await engine.search(keyword: "治愈系", page: 1, debug: sink)
        XCTAssertEqual(books.count, 2, "搜索结果不受调试影响")

        let kinds = events.map { Self.kind(of: $0) }
        XCTAssertTrue(kinds.contains("requestSent"), "应捕获请求事件，实际：\(kinds)")
        XCTAssertTrue(kinds.contains("responseReceived"), "应捕获响应事件，实际：\(kinds)")
        XCTAssertTrue(kinds.contains("contentSet"), "应捕获原文进入事件，实际：\(kinds)")
        XCTAssertTrue(kinds.contains("finalResultList"), "应捕获搜索列表最终事件，实际：\(kinds)")

        // 请求 URL 中的模板变量应已被替换
        let requestEvents = events.compactMap { event -> String? in
            if case let .requestSent(url, _, _) = event { return url }
            return nil
        }
        let requestURL = try XCTUnwrap(requestEvents.first, "应捕获到请求事件")
        XCTAssertTrue(requestURL.contains("query_word="), "搜索模板应替换 key，实际 URL：\(requestURL)")
        XCTAssertTrue(requestURL.contains("page_index=0"), "搜索模板应替换 page-1，实际 URL：\(requestURL)")
        XCTAssertFalse(requestURL.contains(",{"), "逗号请求体配置已被剥离")
    }

    // MARK: - 调试器面板引擎

    @MainActor
    func testSourceDebugEngineRunSearchCollectsLogs() async throws {
        let json = try fixture("fanqie-source")
        let sources = SYBookSourceStore.parse(json)
        let source = try XCTUnwrap(sources.first)

        let responseText = try fixture("fanqie-search-response")
        MockURLProtocol.handler = { request in
            let data = Data(responseText.utf8)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, data)
        }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)

        let engine = SYSourceDebugEngine(source: source, session: session)
        XCTAssertTrue(engine.logs.isEmpty)

        await engine.runSearch(keyword: "治愈系", page: 1)

        XCTAssertFalse(engine.isRunning, "运行结束应复位 isRunning")
        XCTAssertFalse(engine.logs.isEmpty, "应有面板日志")
        let joined = engine.logs.map(\.summary).joined(separator: "\n")
        XCTAssertTrue(joined.contains("搜到 2 本"), "应展示搜索结果数量，实际：\n\(joined)")
        XCTAssertTrue(joined.contains("我的治愈系游戏"), "应列出结果书名，实际：\n\(joined)")
        XCTAssertTrue(engine.logs.contains { $0.level == .success }, "应有成功日志")
    }

    @MainActor
    func testSourceDebugEngineEmptyKeywordWarns() async {
        let source = SYBookSource(
            bookSourceName: "空源",
            bookSourceUrl: "https://example.com",
            searchUrl: "https://example.com/search?q={{key}}",
            ruleSearch: SYRuleSearch(bookList: "$.list", name: "$.name")
        )
        let engine = SYSourceDebugEngine(source: source)
        await engine.runSearch(keyword: "   ")
        XCTAssertFalse(engine.isRunning)
        let joined = engine.logs.map(\.summary).joined(separator: "\n")
        XCTAssertTrue(joined.contains("请输入搜索关键词"), "空关键词应提示，实际：\(joined)")
    }

    // MARK: - 辅助

    private static func kind(of event: SYDebugEvent) -> String {
        switch event {
        case .contentSet: return "contentSet"
        case .requestSent: return "requestSent"
        case .responseReceived: return "responseReceived"
        case .rulesParsed: return "rulesParsed"
        case .beforeExtract: return "beforeExtract"
        case .afterExtractValue: return "afterExtractValue"
        case .afterExtractList: return "afterExtractList"
        case .regexApplied: return "regexApplied"
        case .jsExecuted: return "jsExecuted"
        case .finalResult: return "finalResult"
        case .finalResultList: return "finalResultList"
        case .error: return "error"
        }
    }

    private func fixture(_ name: String) throws -> String {
        let bundle = Bundle(for: SYDebugTests.self)
        let url = try XCTUnwrap(bundle.url(forResource: name, withExtension: "json"), "缺少 fixture \(name).json")
        return try String(contentsOf: url, encoding: .utf8)
    }
}
