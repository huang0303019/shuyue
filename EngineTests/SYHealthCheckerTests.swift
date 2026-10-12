import XCTest
@testable import ShuYue

// MARK: - 五阶段实跑校验（离线，Mock 网络）

@MainActor
final class SYHealthCheckerTests: XCTestCase {

    override func setUp() {
        super.setUp()
        MockURLProtocol.handler = nil
    }

    // MARK: - 全链路通过

    func testFiveStagesAllPass() async throws {
        MockURLProtocol.handler = { request in
            self.respond(for: request, search: Self.searchHTML, detailToc: Self.detailTocHTML, content: Self.contentHTML)
        }
        let source = makeHTMLSource()
        let item = try await runCheck(source: source)

        XCTAssertEqual(item.health, .passed, "全阶段通过应判定为 passed")
        XCTAssertNil(item.failureCategory, "通过时不应有失败分类")
        XCTAssertEqual(item.outcome(.search).status, .pass, "搜索应通过")
        XCTAssertEqual(item.outcome(.discovery).status, .skipped, "未配置发现应跳过")
        XCTAssertEqual(item.outcome(.detail).status, .pass, "详情应通过")
        XCTAssertEqual(item.outcome(.toc).status, .pass, "目录应通过")
        XCTAssertEqual(item.outcome(.content).status, .pass, "正文应通过")
        XCTAssertGreaterThanOrEqual(item.responseTime, 0)
    }

    // MARK: - 搜索无结果 -> searchFailed

    func testSearchEmptyIsSearchFailed() async throws {
        MockURLProtocol.handler = { request in
            self.respond(for: request, search: "<ul id=\"list\"></ul>", detailToc: Self.detailTocHTML, content: Self.contentHTML)
        }
        let item = try await runCheck(source: makeHTMLSource())

        XCTAssertEqual(item.failureCategory, .searchFailed, "搜索无结果应为 searchFailed")
        XCTAssertEqual(item.outcome(.search).status, .fail)
        XCTAssertEqual(item.outcome(.detail).status, .skipped, "无书可跑时详情应跳过")
        XCTAssertEqual(item.outcome(.toc).status, .skipped)
        XCTAssertEqual(item.outcome(.content).status, .skipped)
        XCTAssertEqual(item.health, .fetchError, "搜索失败应属抓取异常")
    }

    // MARK: - 网络错误 -> siteError

    func testNetworkErrorIsSiteError() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FailingURLProtocol.self]
        let session = URLSession(configuration: config)
        let item = try await runCheck(source: makeHTMLSource(), session: session)

        XCTAssertEqual(item.failureCategory, .siteError, "网络错误应为 siteError")
        XCTAssertEqual(item.outcome(.search).status, .fail)
        XCTAssertEqual(item.outcome(.detail).status, .skipped, "致命错误后详情应跳过")
        XCTAssertEqual(item.health, .fetchError)
    }

    // MARK: - 无搜索无发现 -> ruleMissing

    func testNoSearchNoExploreIsRuleMissing() async throws {
        let source = makeHTMLSource(searchEnabled: false, searchURL: nil, exploreEnabled: false)
        let item = try await runCheck(source: source)

        XCTAssertEqual(item.failureCategory, .ruleMissing, "无入口应判规则缺失")
        XCTAssertEqual(item.outcome(.search).status, .skipped)
        XCTAssertEqual(item.outcome(.discovery).status, .skipped)
        XCTAssertEqual(item.health, .fetchError)
    }

    // MARK: - 正文为空 -> contentEmpty / contentError

    func testContentEmptyIsContentError() async throws {
        MockURLProtocol.handler = { request in
            self.respond(for: request, search: Self.searchHTML, detailToc: Self.detailTocHTML, content: "<div id=\"content\"></div>")
        }
        let item = try await runCheck(source: makeHTMLSource())

        XCTAssertEqual(item.failureCategory, .contentEmpty, "正文为空应为 contentEmpty")
        XCTAssertEqual(item.outcome(.search).status, .pass)
        XCTAssertEqual(item.outcome(.toc).status, .pass)
        XCTAssertEqual(item.outcome(.content).status, .fail)
        XCTAssertEqual(item.health, .contentError, "仅正文失败应属正文异常")
    }

    // MARK: - checkKeyWord 覆盖默认关键词

    func testKeywordFromCheckKeyWord() async throws {
        var observedURL: String?
        MockURLProtocol.handler = { request in
            observedURL = request.url?.absoluteString ?? ""
            return self.respond(for: request, search: Self.searchHTML, detailToc: Self.detailTocHTML, content: Self.contentHTML)
        }
        let source = makeHTMLSource()
        var withSearch = source
        withSearch.ruleSearch.checkKeyWord = "测试"
        let item = try await runCheck(source: withSearch)

        XCTAssertEqual(item.health, .passed)
        let url = try XCTUnwrap(observedURL, "应捕获搜索请求")
        XCTAssertTrue(url.contains("q=%E6%B5%8B%E8%AF%95"), "应使用书源配置的关键词「测试」，实际 URL：\(url)")
    }

    // MARK: - 辅助

    private func runCheck(source: SYBookSource, session: URLSession? = nil) async throws -> SYCheckItem {
        let checker = SYHealthChecker(session: session)
        checker.start(source: source)
        var waited = 0
        while !checker.isFinished {
            if waited > 200 {
                XCTFail("校验在 5 秒内未完成，当前状态：\(checker.item?.stages.map { $0.status } ?? [])")
                return await checker.item ?? SYCheckItem(source: source)
            }
            try await Task.sleep(nanoseconds: 25_000_000)
            waited += 1
        }
        return await checker.item ?? SYCheckItem(source: source)
    }

    private func makeHTMLSource(
        searchEnabled: Bool = true,
        searchURL: String? = "https://example.com/search?q={{key}}",
        exploreEnabled: Bool = false
    ) -> SYBookSource {
        SYBookSource(
            bookSourceName: "测试书源",
            bookSourceUrl: "https://example.com",
            enabledExplore: exploreEnabled,
            enabledSearch: searchEnabled,
            searchUrl: searchURL,
            ruleSearch: SYRuleSearch(
                bookList: "css:ul#list li.item",
                name: "css:.name@text",
                bookUrl: "css:a.bk@href"
            ),
            ruleBookInfo: SYRuleBookInfo(name: "css:h1@text", intro: "css:.intro@text"),
            ruleToc: SYRuleToc(
                chapterList: "css:ul#toc li",
                chapterName: "css:a@text",
                chapterUrl: "css:a@href"
            ),
            ruleContent: SYRuleContent(content: "css:#content@text")
        )
    }

    private func respond(for request: URLRequest, search: String, detailToc: String, content: String) -> (HTTPURLResponse, Data) {
        let url = request.url?.absoluteString ?? ""
        let html: String
        if url.contains("/search") {
            html = search
        } else if url.contains("/chapter/") {
            html = content
        } else {
            html = detailToc
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "text/html; charset=utf-8"]
        )!
        return (response, Data(html.utf8))
    }

    // MARK: - HTML 样本

    private static let searchHTML = """
    <html><body>
    <ul id="list">
      <li class="item"><a class="bk" href="/book/1">书一</a><span class="name">书一</span></li>
      <li class="item"><a class="bk" href="/book/2">书二</a><span class="name">书二</span></li>
    </ul>
    </body></html>
    """

    private static let detailTocHTML = """
    <html><body>
    <h1>书一</h1>
    <p class="intro">简介内容</p>
    <ul id="toc">
      <li><a href="/chapter/1">第一章</a></li>
      <li><a href="/chapter/2">第二章</a></li>
    </ul>
    </body></html>
    """

    private static let contentHTML = """
    <html><body>
    <div id="content">这是第一章的正文内容，用于验证正文抓取是否正常。</div>
    </body></html>
    """
}

// MARK: - 恒定失败 Mock

final class FailingURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }

    override func stopLoading() {}
}