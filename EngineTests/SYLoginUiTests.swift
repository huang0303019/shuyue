import XCTest
@testable import ShuYue

// MARK: - 登录表单（P1-⑥）：loginUi 解析、URL/JS 登录、loginCheckJs 校验、Cookie 保存

final class SYLoginUiTests: XCTestCase {

    override func setUp() {
        super.setUp()
        MockURLProtocol.handler = nil
        // 清理共享 Cookie 存储，避免跨测试污染。
        HTTPCookieStorage.shared.removeCookies(since: .distantPast)
    }

    override func tearDown() {
        MockURLProtocol.handler = nil
        HTTPCookieStorage.shared.removeCookies(since: .distantPast)
        super.tearDown()
    }

    /// 构造带 Mock 网络与共享 Cookie 存储的登录测试会话。
    private func makeLoginSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.httpShouldSetCookies = true
        return URLSession(configuration: config)
    }

    private func makeEngine(_ source: SYBookSource) -> SYLegadoEngine {
        SYLegadoEngine(source: source, session: makeLoginSession())
    }

    private func mockTextResponse(_ text: String, headers: [String: String] = ["Content-Type": "text/plain"]) {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: headers
            )!
            return (response, Data(text.utf8))
        }
    }

    // MARK: - loginUi 解析：数组形态

    func testLoginUiArrayForm() throws {
        let raw = #"""
        [
          {"name":"user","type":"text","label":"账号"},
          {"name":"pass","type":"password","label":"密码"},
          {"name":"remember","type":"select","chars":["7天","30天"],"default":"7天"},
          {"name":"agree","type":"checkbox","label":"同意条款"}
        ]
        """#
        let ui = try XCTUnwrap(SYLoginUiParser.parse(raw))
        XCTAssertNil(ui.title)
        XCTAssertTrue(ui.urls.isEmpty)
        XCTAssertEqual(ui.fields.count, 4)
        XCTAssertEqual(ui.fields[0].type, .text)
        XCTAssertEqual(ui.fields[0].label, "账号")
        XCTAssertEqual(ui.fields[1].type, .password)
        XCTAssertTrue(ui.fields[1].type.isSecure)
        XCTAssertEqual(ui.fields[2].type, .select)
        XCTAssertEqual(ui.fields[2].options, ["7天", "30天"])
        XCTAssertEqual(ui.fields[2].defaultValue, "7天")
        XCTAssertEqual(ui.fields[3].type, .checkbox)
        XCTAssertTrue(ui.hasFields)
    }

    // MARK: - loginUi 解析：对象形态（含 urls）

    func testLoginUiObjectForm() throws {
        let raw = #"""
        {
          "title": "用户登录",
          "params": [
            {"name":"username","type":"input","label":"用户名"},
            {"name":"captcha","type":"captcha","label":"验证码"}
          ],
          "urls": [
            {"name":"提交","url":"https://example.com/login","method":"POST"},
            {"name":"短信登录","url":"https://example.com/sms/login","method":"GET"}
          ]
        }
        """#
        let ui = try XCTUnwrap(SYLoginUiParser.parse(raw))
        XCTAssertEqual(ui.title, "用户登录")
        XCTAssertEqual(ui.fields.count, 2)
        XCTAssertEqual(ui.fields[0].type, .input)
        XCTAssertEqual(ui.fields[1].type, .captcha)
        XCTAssertEqual(ui.urls.count, 2)
        XCTAssertEqual(ui.urls[0].name, "提交")
        XCTAssertEqual(ui.urls[0].url, "https://example.com/login")
        XCTAssertEqual(ui.urls[0].method, "POST")
        XCTAssertEqual(ui.urls[1].method, "GET")
    }

    // MARK: - loginUi 解析：JS 字面量容错（单引号 / 尾逗号）

    func testLoginUiJSLiteralTolerance() throws {
        let raw = #"""
        [
          {'name':'user','type':'text','label':'账号',},
          {'name':'pass','type':'password','label':'密码'},
        ]
        """#
        let ui = try XCTUnwrap(SYLoginUiParser.parse(raw))
        XCTAssertEqual(ui.fields.count, 2)
        XCTAssertEqual(ui.fields[0].name, "user")
        XCTAssertEqual(ui.fields[0].label, "账号")
        XCTAssertEqual(ui.fields[1].type, .password)
    }

    // MARK: - loginUi 解析：label 退化与非法输入

    func testLoginUiLabelFallback() throws {
        // 缺 label / viewName 时退化到 name。
        let raw = #"[{"name":"username","type":"text"}]"#
        let ui = try XCTUnwrap(SYLoginUiParser.parse(raw))
        XCTAssertEqual(ui.fields[0].label, "username")

        // viewName 带单引号字面量：剥引号。
        let raw2 = #"[{"name":"username","type":"text","viewName":"'用户名'"}]"#
        let ui2 = try XCTUnwrap(SYLoginUiParser.parse(raw2))
        XCTAssertEqual(ui2.fields[0].label, "用户名")
    }

    func testLoginUiInvalidReturnsNil() {
        XCTAssertNil(SYLoginUiParser.parse(nil))
        XCTAssertNil(SYLoginUiParser.parse(""))
        XCTAssertNil(SYLoginUiParser.parse("   "))
        XCTAssertNil(SYLoginUiParser.parse("not-json"))
        XCTAssertNil(SYLoginUiParser.parse("{broken"))
    }

    // MARK: - 动态 loginUi（<js> 求值）

    func testLoadLoginUiFromDynamicJS() async throws {
        var source = SYBookSource(bookSourceName: "动态源", bookSourceUrl: "https://example.com")
        source.loginUi = """
        <js>
        JSON.stringify([{'name':'user','type':'text','label':'账号'}])
        </js>
        """
        let engine = makeEngine(source)
        let ui = await engine.loadLoginUi()
        XCTAssertEqual(ui?.fields.count, 1)
        XCTAssertEqual(ui?.fields[0].name, "user")
    }

    // MARK: - URL 表单登录：POST body / Content-Type / Cookie 保存

    func testURLLoginPostsFormAndSavesCookie() async throws {
        var source = SYBookSource(bookSourceName: "表单源", bookSourceUrl: "https://example.com")
        source.loginUrl = "https://example.com/login"
        source.loginCheckJs = "JSON.parse(result).code == 200"

        var capturedMethod: String?
        var capturedBody: String?
        var capturedContentType: String?
        MockURLProtocol.handler = { request in
            capturedMethod = request.httpMethod
            if let body = request.httpBody, let text = String(data: body, encoding: .utf8) {
                capturedBody = text
            }
            capturedContentType = request.value(forHTTPHeaderField: "Content-Type")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: [
                    "Content-Type": "application/json",
                    "Set-Cookie": "sid=abc123; Path=/; Domain=example.com"
                ]
            )!
            return (response, Data(#"{"code":200}"#.utf8))
        }

        let engine = makeEngine(source)
        let result = try await engine.login(formValues: ["username": "zhang", "password": "secret"])

        XCTAssertEqual(capturedMethod, "POST", "无占位符且有表单值时应转 POST 表单提交")
        XCTAssertEqual(capturedContentType, "application/x-www-form-urlencoded")
        if let capturedBody {
            XCTAssertTrue(capturedBody.contains("username=zhang"))
            XCTAssertTrue(capturedBody.contains("password=secret"))
        } else {
            XCTFail("POST body 不应为空")
        }
        XCTAssertTrue(result.success)
        XCTAssertTrue(result.checked, "配置 loginCheckJs 后应执行校验")

        // Login 请求强制 useCookieJar：Set-Cookie 进入 HTTPCookieStorage.shared。
        let saved = HTTPCookieStorage.shared.cookies?.first { $0.name == "sid" }
        XCTAssertEqual(saved?.value, "abc123", "登录响应 Set-Cookie 应保存到共享 Cookie 存储")
    }

    // MARK: - loginCheckJs 校验分支

    func testLoginCheckJsBoolTrue() async throws {
        var source = SYBookSource(bookSourceName: "校验源", bookSourceUrl: "https://example.com")
        source.loginUrl = "https://example.com/login"
        source.loginCheckJs = "JSON.parse(result).code == 200"
        mockTextResponse(#"{"code":200}"#, headers: ["Content-Type": "application/json"])

        let result = try await makeEngine(source).login(formValues: [])
        XCTAssertTrue(result.success)
        XCTAssertTrue(result.checked)
    }

    func testLoginCheckJsBoolFalse() async throws {
        var source = SYBookSource(bookSourceName: "校验源", bookSourceUrl: "https://example.com")
        source.loginUrl = "https://example.com/login"
        source.loginCheckJs = "JSON.parse(result).code == 200"
        mockTextResponse(#"{"code":403}"#, headers: ["Content-Type": "application/json"])

        let result = try await makeEngine(source).login(formValues: [])
        XCTAssertFalse(result.success)
        XCTAssertTrue(result.checked)
    }

    func testLoginCheckJsTextNonEmptyPasses() async throws {
        var source = SYBookSource(bookSourceName: "校验源", bookSourceUrl: "https://example.com")
        source.loginUrl = "https://example.com/login"
        source.loginCheckJs = "'登录成功'"
        mockTextResponse("ok")

        let result = try await makeEngine(source).login(formValues: [])
        XCTAssertTrue(result.success, "非空文本返回值应视为登录成功")
        XCTAssertTrue(result.checked)
    }

    func testLoginCheckJsEmptyTextFails() async throws {
        var source = SYBookSource(bookSourceName: "校验源", bookSourceUrl: "https://example.com")
        source.loginUrl = "https://example.com/login"
        source.loginCheckJs = "''"
        mockTextResponse("")

        let result = try await makeEngine(source).login(formValues: [])
        XCTAssertFalse(result.success, "空字符串应判定登录失败")
        XCTAssertTrue(result.checked)
    }

    func testLoginCheckJsMissingScriptsPassUnchecked() async throws {
        var source = SYBookSource(bookSourceName: "无校验源", bookSourceUrl: "https://example.com")
        source.loginUrl = "https://example.com/login"
        mockTextResponse("any")

        let result = try await makeEngine(source).login(formValues: [])
        XCTAssertTrue(result.success)
        XCTAssertFalse(result.checked, "未配置 loginCheckJs 时不做校验")
    }

    func testLoginCheckJsJavaBridgeHint() async throws {
        var source = SYBookSource(bookSourceName: "java源", bookSourceUrl: "https://example.com")
        source.loginUrl = "https://example.com/login"
        source.loginCheckJs = "java.lang.System.currentTimeMillis() > 0"
        mockTextResponse("ok")

        let result = try await makeEngine(source).login(formValues: [])
        XCTAssertFalse(result.success)
        XCTAssertTrue(result.message.contains("java"), "依赖 java 桥的校验应给出中文提示，实际：\(result.message)")
    }

    // MARK: - URL 占位符填充（GET 模板）

    func testURLLoginFillsPlaceholders() async throws {
        var source = SYBookSource(bookSourceName: "模板源", bookSourceUrl: "https://example.com")
        source.loginUrl = "https://example.com/login?user={{username}}"
        var capturedURL: String?
        mockTextResponse("ok") // 占位
        MockURLProtocol.handler = { request in
            capturedURL = request.url?.absoluteString
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("ok".utf8))
        }

        let result = try await makeEngine(source).login(formValues: ["username": "zhang"])
        XCTAssertEqual(capturedURL, "https://example.com/login?user=zhang", "表单值应填充 URL 模板")
        XCTAssertTrue(result.success)
    }

    // MARK: - JS 形态登录

    func testJSLoginInvokesFunction() async throws {
        var source = SYBookSource(bookSourceName: "jss源", bookSourceUrl: "https://example.com")
        source.loginUrl = "function login(){ var a = 1 + 2; }"

        let result = try await makeEngine(source).login(formValues: ["username": "zhang"])
        XCTAssertTrue(result.success, "无 java 依赖的 login() 应正常执行")
    }

    func testJSLoginJavaBridgeFailsGracefully() async throws {
        var source = SYBookSource(bookSourceName: "jss源", bookSourceUrl: "https://example.com")
        source.loginUrl = "function login(){ java.connect('https://example.com'); }"

        let result = try await makeEngine(source).login(formValues: [])
        XCTAssertFalse(result.success)
        XCTAssertTrue(result.message.contains("java"), "JS 登录依赖 java 桥时应明确失败并提示，实际：\(result.message)")
    }

    // MARK: - 模型编解码

    func testBookSourceLoginCheckJsDecoding() throws {
        let json = #"""
        {"bookSourceName":"登录源","bookSourceUrl":"https://example.com",
         "loginUrl":"https://example.com/login","loginCheckJs":"result.code == 200"}
        """#
        let source = try XCTUnwrap(SYBookSource(jsonData: Data(json.utf8)))
        XCTAssertEqual(source.loginCheckJs, "result.code == 200")
        let roundTrip = try XCTUnwrap(SYBookSource(jsonData: source.jsonData()!))
        XCTAssertEqual(roundTrip.loginCheckJs, source.loginCheckJs)
    }
}
