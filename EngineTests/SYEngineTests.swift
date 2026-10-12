import XCTest
@testable import ShuYue

// MARK: - 可复现的离线引擎校验（不依赖真实网络）

final class SYEngineTests: XCTestCase {

    override func setUp() {
        super.setUp()
        MockURLProtocol.handler = nil
    }

    // MARK: - 书源解析（真实番茄书源互通基准）

    func testParseRealFanqieSource() throws {
        let json = try fixture("fanqie-source")
        let sources = SYBookSourceStore.parse(json)
        XCTAssertEqual(sources.count, 1, "书源 JSON 应为单对象数组")
        let source = try XCTUnwrap(sources.first)
        XCTAssertEqual(source.bookSourceName, "番茄小说(直连-小说版)")
        XCTAssertEqual(source.bookSourceUrl, "https://fanqienovel.com")
        XCTAssertEqual(source.ruleSearch.bookList, "$.data.search_book_data_list")
        XCTAssertEqual(source.ruleSearch.name, "$.book_name@js:decodePua(result)")
        XCTAssertNotNil(source.jsLib)
        XCTAssertTrue(source.jsLib!.contains("decodePua"), "jsLib 应包含 decodePua 实现")
        XCTAssertTrue(source.ruleToc.chapterList!.hasPrefix("<js>"), "目录规则应为 <js> 脚本")
        let issues = SYBookSourceStore.validate(source)
        XCTAssertTrue(issues.isEmpty, "书源校验应通过，问题：\(issues.joined(separator: "; "))")
    }

    func testBookSourceRoundTrip() throws {
        let json = try fixture("fanqie-source")
        let sources = SYBookSourceStore.parse(json)
        let exported = SYBookSourceStore.serialize(sources)
        let reparsed = SYBookSourceStore.parse(exported)
        XCTAssertEqual(reparsed.count, 1)
        XCTAssertEqual(reparsed.first?.bookSourceName, sources.first?.bookSourceName)
        XCTAssertEqual(reparsed.first?.ruleSearch.name, sources.first?.ruleSearch.name)
    }

    // MARK: - JSONPath

    func testJSONPath() throws {
        let obj: [String: Any] = [
            "data": [
                "list": [["name": "A", "author": "X"], ["name": "B", "author": "Y"]]
            ],
            "count": 2
        ]
        XCTAssertEqual(SYJSONPath.displayString(SYJSONPath.evaluate(path: "$.data.list[0].name", root: obj)), "A")
        XCTAssertEqual(SYJSONPath.displayString(SYJSONPath.evaluate(path: "$.data.list[1].author", root: obj)), "Y")
        XCTAssertEqual(SYJSONPath.displayString(SYJSONPath.evaluate(path: "$.count", root: obj)), "2")
        XCTAssertNil(SYJSONPath.evaluate(path: "$.missing.key", root: obj), "未命中应返回 nil")
        let slice = SYJSONPath.evaluate(path: "$.data.list[0:2]", root: obj) as? [Any]
        XCTAssertEqual(slice?.count, 2, "slice [0:2] 应返回 2 项")
    }

    // MARK: - JavaScript 求值

    func testJavaScriptContext() throws {
        let jsLib = """
        function double(x){ return x*2; }
        function decodePua(s){ return String(s); }
        """
        let context = try XCTUnwrap(SYJavaScriptContext(jsLib: jsLib))

        let out = try context.evaluate("double(result)", result: 21 as NSNumber, baseUrl: nil)
        XCTAssertEqual(out as? Double, 42, "jsLib 函数应可执行")

        let multi = try context.evaluate("var a = result + 1; a * 2", result: 10 as NSNumber, baseUrl: nil)
        XCTAssertEqual(multi as? Double, 22, "多语句脚本应取最后一条语句的值")

        let str = try context.evaluate("decodePua(result)", result: "你好PUA", baseUrl: nil)
        XCTAssertEqual(str as? String, "你好PUA")

        let object = try context.evaluate("JSON.parse(result)", result: "{\"a\":1}" as NSString, baseUrl: nil)
        let dict = object as? [String: Any]
        XCTAssertEqual(dict?["a"] as? Double, 1, "JS 对象应可桥接为字典")
    }

    // MARK: - 源变量（source.getVariable()）

    func testSourceVariableReadsKeyedValue() throws {
        let context = try XCTUnwrap(SYJavaScriptContext(
            jsLib: nil,
            sourceVariables: #"{"token":"abc","expire": 3600}"#
        ))
        let value = try context.evaluate("source.getVariable('token')", result: nil, baseUrl: nil)
        XCTAssertEqual(value as? String, "abc", "getVariable(key) 应返回 JSON 对象中对应 key 的值")
    }

    func testSourceVariableNoArgReturnsRawJSON() throws {
        let raw = #"{"token":"abc"}"#
        let context = try XCTUnwrap(SYJavaScriptContext(jsLib: nil, sourceVariables: raw))
        let value = try context.evaluate("source.getVariable()", result: nil, baseUrl: nil)
        XCTAssertEqual(value as? String, raw, "无参 getVariable() 应原样返回整段 JSON 文本")
        let parsed = try context.evaluate("JSON.parse(source.getVariable()).token", result: nil, baseUrl: nil)
        XCTAssertEqual(parsed as? String, "abc", "老式书源 JSON.parse(source.getVariable()) 用法应可用")
    }

    func testSourceVariableMissAndInvalidJSONReturnNull() throws {
        let valid = try XCTUnwrap(SYJavaScriptContext(jsLib: nil, sourceVariables: #"{"a":1}"#))
        let missing = try valid.evaluate("source.getVariable('missing')", result: nil, baseUrl: nil)
        XCTAssertNil(missing, "未命中 key 应返回 null")

        let invalid = try XCTUnwrap(SYJavaScriptContext(jsLib: nil, sourceVariables: "not-json"))
        let raw = try invalid.evaluate("source.getVariable()", result: nil, baseUrl: nil)
        XCTAssertEqual(raw as? String, "not-json", "非法 JSON 时无参调用仍应返回原文")
        let keyed = try invalid.evaluate("source.getVariable('k')", result: nil, baseUrl: nil)
        XCTAssertNil(keyed, "非法 JSON 时带 key 调用应返回 null")
    }

    func testBookSourceVariableDecoding() throws {
        let json = #"""
        {"bookSourceName":"变量源","bookSourceUrl":"https://example.com",
         "variable":"{\"apiKey\":\"x\"}","variableComment":"填入 API Key"}
        """#
        let source = try XCTUnwrap(SYBookSource(jsonData: Data(json.utf8)))
        XCTAssertEqual(source.variable, #"{"apiKey":"x"}"#)
        XCTAssertEqual(source.variableComment, "填入 API Key")
        let roundTrip = try XCTUnwrap(SYBookSource(jsonData: source.jsonData()!))
        XCTAssertEqual(roundTrip.variable, source.variable)
        XCTAssertEqual(roundTrip.variableComment, source.variableComment)
    }

    // MARK: - HTML 规则（CSS / XPath / Regex / Replace）

    func testHTMLRules() throws {
        let html = """
        <html><body><ul id="list">
          <li class="item" data-id="1"><a href="/book/1">书名一</a><span class="author">作者一</span></li>
          <li class="item" data-id="2"><a href="/book/2">书名二</a><span class="author">作者二</span></li>
        </ul></body></html>
        """
        let root = SYHTMLParser.parse(html)

        let items = SYRuleEvaluator.list("css:#list .item", context: SYRuleContext(htmlRoot: root))
        XCTAssertEqual(items.count, 2, "CSS 选择器应命中两条 li")
        guard case .nodes(let firstNode) = items[0] else {
            return XCTFail("bookList 应为节点")
        }
        let node = try XCTUnwrap(firstNode.first)
        let itemContext = SYRuleContext(htmlRoot: node)

        XCTAssertEqual(SYRuleEvaluator.string("css:a@text", context: itemContext), "书名一")
        XCTAssertEqual(SYRuleEvaluator.string("@css:a@text", context: itemContext), "书名一")
        XCTAssertEqual(SYRuleEvaluator.string("css:a@href", context: itemContext), "/book/1")
        XCTAssertEqual(SYRuleEvaluator.string("css:.author@text", context: itemContext), "作者一")
        XCTAssertEqual(SYRuleEvaluator.string("css:a@text@trim", context: itemContext), "书名一")
        XCTAssertEqual(SYRuleEvaluator.string("css:a@text@regex:书名(.+)", context: itemContext), "一")
        XCTAssertEqual(SYRuleEvaluator.string("css:a@text@replace:书名||Title", context: itemContext), "Title一")

        XCTAssertEqual(SYRuleEvaluator.string("//li[1]/a/text()", context: SYRuleContext(htmlRoot: root)), "书名一")
        XCTAssertEqual(SYRuleEvaluator.string("//li[@data-id='2']/a/@href", context: SYRuleContext(htmlRoot: root)), "/book/2")
    }

    // MARK: - 离线搜索链路（真实番茄书源 + Mock 响应）

    func testSearchOfflineWithRealFanqieSource() async throws {
        let json = try fixture("fanqie-source")
        let sources = SYBookSourceStore.parse(json)
        let source = try XCTUnwrap(sources.first)

        let responseText = try fixture("fanqie-search-response")
        MockURLProtocol.handler = { request in
            let url = request.url?.absoluteString ?? ""
            XCTAssertTrue(url.contains("page_index=0"), "page-1 模板应替换为 0，实际 URL：\(url)")
            XCTAssertTrue(url.contains("query_word="), "key 模板应替换，实际 URL：\(url)")
            XCTAssertFalse(url.contains(",{"), "逗号请求体配置应被剥离，实际 URL：\(url)")
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
        let engine = SYLegadoEngine(source: source, session: session)

        let books = try await engine.search(keyword: "治愈系", page: 1)
        XCTAssertEqual(books.count, 2, "应解析出两条搜索结果")
        let first = try XCTUnwrap(books.first)
        XCTAssertEqual(first.name, "我的治愈系游戏")
        XCTAssertEqual(first.author, "我会修空调")
        XCTAssertEqual(first.intro, "治愈系悬疑")
        XCTAssertEqual(first.bookUrl, "https://fanqienovel.com/page/12345", "book_url 规则应拼接页面 URL")
        XCTAssertEqual(first.sourceUrl, "https://fanqienovel.com")
        XCTAssertNotNil(first.coverUrl)
    }

    // MARK: - 辅助

    private func fixture(_ name: String) throws -> String {
        let bundle = Bundle(for: SYEngineTests.self)
        let url = try XCTUnwrap(bundle.url(forResource: name, withExtension: "json"), "缺少 fixture \(name).json")
        return try String(contentsOf: url, encoding: .utf8)
    }
}

// MARK: - Mock URLProtocol

final class MockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let (response, data) = handler(request)
        // 模拟系统 URLSession 的 cookie 行为：响应头带 Set-Cookie 时写入共享存储，
        // 否则自定义 URLProtocol 绕过系统 HTTP 协议栈，Cookie 永远不会落库。
        if let http = response as? HTTPURLResponse,
           let url = request.url,
           let setCookie = http.value(forHTTPHeaderField: "Set-Cookie") {
            let cookies = HTTPCookie.cookies(
                withResponseHeaderFields: ["Set-Cookie": setCookie],
                for: url
            )
            HTTPCookieStorage.shared.setCookies(cookies, for: url, mainDocumentURL: nil)
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}