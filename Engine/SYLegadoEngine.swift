import Foundation

// MARK: - Legado 书源执行引擎

/// 单个书源的执行器：搜索 / 发现 / 详情 / 目录 / 正文五条链路。
actor SYLegadoEngine {
    let source: SYBookSource
    private var client: SYNetworkClient
    private var js: SYJavaScriptContext?

    init(source: SYBookSource, session: URLSession? = nil) {
        self.source = source
        let timeout = source.respondTime > 0 ? Double(source.respondTime) / 1000.0 : 15.0
        var network = SYNetworkClient(
            timeout: timeout,
            defaultHeaders: SYNetworkClient.parseHeaderJSON(source.header),
            session: session
        )
        network.useCookieJar = source.enabledCookieJar
        self.client = network
        self.js = SYJavaScriptContext(jsLib: source.jsLib, sourceVariables: source.variable)
    }

    /// 按模板发起请求（支持 URL 模板变量与 `url,{json}` 请求体配置）。
    private func requestTemplate(_ template: String, vars: [String: String]) async throws -> (SYHTTPResult, String) {
        let (urlText, method, body) = resolveTemplate(template, vars: vars)
        let result = try await client.request(
            url: urlText,
            method: method,
            headers: headerVars(vars),
            body: body?.data(using: .utf8)
        )
        return (result, urlText)
    }

    // MARK: - 搜索

    func search(keyword: String, page: Int = 1) async throws -> [SYBook] {
        guard let template = source.searchUrl, !template.isEmpty else {
            throw SYEngineError.emptyResult("书源未配置 searchUrl")
        }
        guard source.enabledSearch else {
            throw SYEngineError.emptyResult("书源已禁用搜索")
        }
        let vars = searchVariables(keyword: keyword, page: page)
        let (result, urlText) = try await requestTemplate(template, vars: vars)
        let text = SYTextDecoding.text(from: result.data, response: result.response)
        let context = makeContext(rawText: text, pageURL: urlText)
        return try parseBookList(rule: source.ruleSearch, context: context, baseUrl: source.bookSourceUrl)
    }

    // MARK: - 发现

    func explore(url: String? = nil) async throws -> [SYBook] {
        guard source.enabledExplore else {
            throw SYEngineError.emptyResult("书源未启用发现")
        }
        let template = url ?? source.exploreUrl ?? ""
        guard !template.isEmpty else {
            throw SYEngineError.emptyResult("书源未配置 exploreUrl")
        }
        let vars = baseVars()
        let (result, urlText) = try await requestTemplate(template, vars: vars)
        let text = SYTextDecoding.text(from: result.data, response: result.response)
        let context = makeContext(rawText: text, pageURL: urlText)
        return try parseExploreList(rule: source.ruleExplore, context: context, baseUrl: source.bookSourceUrl)
    }

    // MARK: - 详情

    func bookInfo(_ book: SYBook) async throws -> SYBook {
        let requestURL = absolutize(book.detailRequestUrl ?? book.bookUrl, base: source.bookSourceUrl)
        let (result, urlText) = try await requestTemplate(requestURL, vars: baseVars(bookUrl: book.bookUrl))
        let text = SYTextDecoding.text(from: result.data, response: result.response)
        let context = makeContext(rawText: text, pageURL: urlText)

        // init 规则：产物作为后续字段规则的 JSON 根（如番茄书源 `<js>result={...}</js>`）。
        var fieldContext = context
        if let initRule = source.ruleBookInfo.initRule, !initRule.isEmpty {
            if let initValue = SYRuleEvaluator.raw(initRule, context: context) {
                fieldContext = SYRuleContext(
                    jsonRoot: initValue,
                    htmlRoot: nil,
                    baseUrl: urlText,
                    js: js,
                    fallbackText: text
                )
            }
        }

        var updated = book
        let rule = source.ruleBookInfo
        updated.name = SYRuleEvaluator.string(rule.name, context: fieldContext) ?? book.name
        updated.author = SYRuleEvaluator.string(rule.author, context: fieldContext) ?? book.author
        updated.intro = SYRuleEvaluator.string(rule.intro, context: fieldContext) ?? book.intro
        updated.coverUrl = SYRuleEvaluator.string(rule.coverUrl, context: fieldContext) ?? book.coverUrl
        updated.kind = SYRuleEvaluator.string(rule.kind, context: fieldContext) ?? book.kind
        updated.wordCount = SYRuleEvaluator.string(rule.wordCount, context: fieldContext) ?? book.wordCount
        return updated
    }

    // MARK: - 目录

    func toc(_ book: SYBook) async throws -> [SYChapter] {
        var requestURL = book.detailRequestUrl ?? book.bookUrl
        if let tocTemplate = source.ruleToc.url, !tocTemplate.isEmpty {
            requestURL = fillTemplate(tocTemplate, vars: baseVars(bookUrl: book.bookUrl))
        }
        let urlText = absolutize(requestURL, base: source.bookSourceUrl)
        let (result, _) = try await requestTemplate(urlText, vars: baseVars(bookUrl: book.bookUrl))
        let text = SYTextDecoding.text(from: result.data, response: result.response)
        let context = makeContext(rawText: text, pageURL: urlText)

        let rule = source.ruleToc
        let items = SYRuleEvaluator.list(rule.chapterList, context: context)
        var chapters: [SYChapter] = []
        var index = 0
        for item in items {
            let itemContext = SYRuleContext(
                jsonRoot: itemJSON(item),
                htmlRoot: itemHTML(item),
                baseUrl: urlText,
                js: js,
                fallbackText: nil
            )
            guard let title = SYRuleEvaluator.string(rule.chapterName, context: itemContext), !title.isEmpty else { continue }
            guard let chapterURL = SYRuleEvaluator.string(rule.chapterUrl, context: itemContext), !chapterURL.isEmpty else { continue }
            let isVip = isVipTrue(SYRuleEvaluator.string(rule.isVip, context: itemContext))
            chapters.append(SYChapter(
                title: title,
                url: absolutize(chapterURL, base: urlText),
                sourceUrl: source.bookSourceUrl,
                index: index,
                isVip: isVip
            ))
            index += 1
        }
        return chapters
    }

    // MARK: - 正文

    func content(_ chapter: SYChapter) async throws -> SYContentResult {
        var requestURL = chapter.url
        if let t = source.ruleContent.url, !t.isEmpty, t.contains("{{chapterUrl}}") {
            requestURL = fillTemplate(t, vars: [
                "baseUrl": source.bookSourceUrl,
                "bookUrl": chapter.url,
                "chapterUrl": chapter.url
            ])
        }
        let urlText = absolutize(requestURL, base: source.bookSourceUrl)
        let (result, _) = try await requestTemplate(urlText, vars: baseVars())
        let text = SYTextDecoding.text(from: result.data, response: result.response)
        let context = makeContext(rawText: text, pageURL: urlText)

        guard let content = SYRuleEvaluator.string(source.ruleContent.content, context: context), !content.isEmpty else {
            throw SYEngineError.emptyResult("正文规则未命中：\(source.ruleContent.content ?? "")")
        }
        var nextURL: String?
        if let next = source.ruleContent.nextContentUrl, !next.isEmpty {
            let nextTemplate = fillTemplate(next, vars: ["baseUrl": source.bookSourceUrl, "chapterUrl": chapter.url])
            nextURL = absolutize(nextTemplate, base: urlText)
        }
        return SYContentResult(content: content, nextUrl: nextURL)
    }

    // MARK: - 列表字段解析

    private func parseBookList(rule: SYRuleSearch, context: SYRuleContext, baseUrl: String) throws -> [SYBook] {
        let items = SYRuleEvaluator.list(rule.bookList, context: context)
        var books: [SYBook] = []
        for item in items {
            let itemContext = SYRuleContext(
                jsonRoot: itemJSON(item),
                htmlRoot: itemHTML(item),
                baseUrl: baseUrl,
                js: js,
                fallbackText: nil
            )
            guard let name = SYRuleEvaluator.string(rule.name, context: itemContext), !name.isEmpty else { continue }
            guard let bookURL = SYRuleEvaluator.string(rule.bookUrl, context: itemContext), !bookURL.isEmpty else { continue }
            books.append(SYBook(
                name: name,
                author: SYRuleEvaluator.string(rule.author, context: itemContext),
                intro: SYRuleEvaluator.string(rule.intro, context: itemContext),
                coverUrl: SYRuleEvaluator.string(rule.coverUrl, context: itemContext),
                wordCount: SYRuleEvaluator.string(rule.wordCount, context: itemContext),
                kind: SYRuleEvaluator.string(rule.kind, context: itemContext),
                lastChapter: SYRuleEvaluator.string(rule.lastChapter, context: itemContext),
                sourceUrl: source.bookSourceUrl,
                bookUrl: absolutize(bookURL, base: baseUrl),
                detailRequestUrl: bookURL,
                sourceName: source.bookSourceName
            ))
        }
        return books
    }

    private func parseExploreList(rule: SYRuleExplore, context: SYRuleContext, baseUrl: String) throws -> [SYBook] {
        let items = SYRuleEvaluator.list(rule.bookList, context: context)
        var books: [SYBook] = []
        for item in items {
            let itemContext = SYRuleContext(
                jsonRoot: itemJSON(item),
                htmlRoot: itemHTML(item),
                baseUrl: baseUrl,
                js: js,
                fallbackText: nil
            )
            guard let name = SYRuleEvaluator.string(rule.name, context: itemContext), !name.isEmpty else { continue }
            guard let bookURL = SYRuleEvaluator.string(rule.bookUrl, context: itemContext), !bookURL.isEmpty else { continue }
            books.append(SYBook(
                name: name,
                author: SYRuleEvaluator.string(rule.author, context: itemContext),
                intro: SYRuleEvaluator.string(rule.intro, context: itemContext),
                coverUrl: SYRuleEvaluator.string(rule.coverUrl, context: itemContext),
                wordCount: SYRuleEvaluator.string(rule.wordCount, context: itemContext),
                kind: SYRuleEvaluator.string(rule.kind, context: itemContext),
                lastChapter: SYRuleEvaluator.string(rule.lastChapter, context: itemContext),
                sourceUrl: source.bookSourceUrl,
                bookUrl: absolutize(bookURL, base: baseUrl),
                detailRequestUrl: bookURL,
                sourceName: source.bookSourceName
            ))
        }
        return books
    }

    // MARK: - 工具

    private func makeContext(rawText: String, pageURL: String) -> SYRuleContext {
        var jsonRoot: Any?
        if let data = rawText.data(using: .utf8) {
            jsonRoot = try? JSONSerialization.jsonObject(with: data)
        }
        var htmlRoot: SYHTMLNode?
        if jsonRoot == nil {
            htmlRoot = SYHTMLParser.parse(rawText)
        }
        return SYRuleContext(
            jsonRoot: jsonRoot,
            htmlRoot: htmlRoot,
            baseUrl: pageURL,
            js: js,
            fallbackText: rawText
        )
    }

    private func baseVars(bookUrl: String? = nil) -> [String: String] {
        var vars: [String: String] = ["baseUrl": source.bookSourceUrl]
        if let bookUrl { vars["bookUrl"] = bookUrl }
        return vars
    }

    private func searchVariables(keyword: String, page: Int) -> [String: String] {
        var vars = baseVars()
        vars["key"] = keyword
        vars["searchKey"] = keyword
        vars["sword"] = keyword
        vars["page"] = String(page)
        vars["page-1"] = String(max(0, page - 1))
        return vars
    }

    private func resolveTemplate(_ template: String, vars: [String: String]) -> (url: String, method: String, body: String?) {
        var t = template
        var method = "GET"
        if t.hasPrefix("@post:") {
            method = "POST"
            t = String(t.dropFirst("@post:".count))
        } else if t.hasPrefix("@get:") {
            t = String(t.dropFirst("@get:".count))
        }
        // Legado 语法：`url,{"method":"POST","headers":{...},"body":"{{key}}"}` 请求体配置
        var body: String?
        if let commaRange = t.range(of: ",{", options: .backwards) {
            let candidate = String(t[t.index(after: commaRange.lowerBound)...])
            if let data = candidate.data(using: .utf8),
               let cfg = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                t = String(t[..<commaRange.lowerBound])
                if let m = cfg["method"] as? String, !m.isEmpty {
                    method = m.uppercased()
                }
                if let b = cfg["body"] as? String, !b.isEmpty {
                    body = fillTemplate(b, vars: vars)
                }
            }
        }
        return (fillTemplate(t, vars: vars), method, body)
    }

    private func fillTemplate(_ template: String, vars: [String: String]) -> String {
        var out = template
        for (key, value) in vars {
            let encoded = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
            out = out.replacingOccurrences(of: "{{\(key)}}", with: encoded)
        }
        return out
    }

    private func headerVars(_ vars: [String: String]) -> [String: String] {
        var out: [String: String] = [:]
        for (k, v) in client.defaultHeaders {
            out[k] = fillTemplate(v, vars: vars)
        }
        return out
    }

    private func absolutize(_ url: String, base: String) -> String {
        if url.hasPrefix("http://") || url.hasPrefix("https://") { return url }
        guard let baseURL = URL(string: base), let u = URL(string: url, relativeTo: baseURL) else {
            return url
        }
        return u.absoluteString
    }

    private func itemJSON(_ item: SYRuleValue) -> Any? {
        if case .json(let v) = item { return v }
        return nil
    }

    private func itemHTML(_ item: SYRuleValue) -> SYHTMLNode? {
        if case .nodes(let nodes) = item, let first = nodes.first { return first }
        return nil
    }

    private func isVipTrue(_ value: String?) -> Bool {
        guard let value else { return false }
        let t = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty || t == "0" || t == "false" || t == "否" || t == "无" { return false }
        return true
    }

    // MARK: - 登录

    /// 解析登录界面：兼容数组 / `{title,params,urls}` 对象两种形态；
    /// `loginUi` 为 `<js>` / `@js:` 动态脚本（不依赖 java 桥）时先求值再解析。
    func loadLoginUi() -> SYLoginUi? {
        guard let raw = source.loginUi, !raw.isEmpty else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let script = extractLoginScript(trimmed) {
            guard let js else { return nil }
            guard let out = try? js.evaluate(script, result: nil, baseUrl: source.bookSourceUrl) else { return nil }
            if let jsonText = jsonText(from: out) {
                return SYLoginUiParser.parse(jsonText)
            }
            return nil
        }
        return SYLoginUiParser.parse(trimmed)
    }

    /// 执行登录并校验结果。
    /// - Parameters:
    ///   - formValues: 登录表单值（用户名/密码等），用于填充 `{{key}}` 模板或 POST 表单体。
    ///   - urlAction: 对象形态 loginUi 中选中的提交目标；为空时使用书源 loginUrl。
    func login(formValues: [String: String] = [:], urlAction: SYLoginUrlAction? = nil) async throws -> SYLoginResult {
        let rawTarget = (urlAction?.url ?? source.loginUrl ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawTarget.isEmpty else {
            return SYLoginResult(success: false, message: "书源未配置登录地址（loginUrl）", checked: false)
        }

        // JS 形态登录：注入登录信息后执行。ShuYue 无 java 桥，依赖 java 的书源会明确失败。
        if let script = extractLoginScript(rawTarget) {
            return try executeLoginJS(script, formValues: formValues)
        }

        // URL 形态登录：模板填充 + 表单提交（Cookie 经 HTTPCookieStorage.shared 自动持久化）。
        let responseText = try await executeURLLogin(target: rawTarget, formValues: formValues, actionMethod: urlAction?.method)

        // loginCheckJs 校验：以登录响应文本为 result 执行，非空返回值视为已登录。
        return evaluateLoginCheck(responseText: responseText)
    }

    // MARK: 登录实现

    private func executeURLLogin(target: String, formValues: [String: String], actionMethod: String?) async throws -> String {
        let resolved = resolveTemplate(target, vars: formValues)
        var method = resolved.method
        var body = resolved.body

        // 无占位符且无 body 配置但有表单字段时，转 POST 表单提交（application/x-www-form-urlencoded）。
        if method == "GET", body == nil, !target.contains("{{"), !formValues.isEmpty {
            method = actionMethod?.uppercased() ?? "POST"
            if method == "POST" {
                let encoded = formValues.map { key, value in
                    let ek = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
                    let ev = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
                    return "\(ek)=\(ev)"
                }.joined(separator: "&")
                body = encoded
            }
        }

        // 登录请求一律走 Cookie jar：Set-Cookie 由 HTTPCookieStorage.shared 自动保存，
        // 后续书源请求在「启用 Cookie」开启时自动携带。
        var loginClient = client
        loginClient.useCookieJar = true

        var requestHeaders = loginHeaders(formValues: formValues)
        if method == "POST", body != nil {
            requestHeaders["Content-Type"] = "application/x-www-form-urlencoded"
        }
        let result = try await loginClient.request(
            url: resolved.url,
            method: method,
            headers: requestHeaders,
            body: body?.data(using: .utf8)
        )
        return SYTextDecoding.text(from: result.data, response: result.response)
    }

    private func executeLoginJS(_ script: String, formValues: [String: String]) throws -> SYLoginResult {
        guard let js else {
            return SYLoginResult(success: false, message: "JS 引擎不可用", checked: false)
        }
        // 注入登录信息到全局 loginInfo（Legado 源常用 source.getLoginInfo() 读取）。
        let infoExpr = SYJavaScriptContext.jsValueLiteral(formValues) ?? "{}"
        _ = try? js.evaluate("var loginInfo = \(infoExpr);", result: nil, baseUrl: source.bookSourceUrl)
        let wrapped = """
        \(script)
        if (typeof login === 'function') {
            login.apply(this);
        } else {
            throw 'Function login not implements!!!';
        }
        """
        do {
            _ = try js.evaluate(wrapped, result: nil, baseUrl: source.bookSourceUrl)
            return SYLoginResult(success: true, message: "登录脚本已执行；请确认书源已启用「启用 Cookie」以持久化会话", checked: false)
        } catch {
            let msg = error.localizedDescription
            let lower = msg.lowercased()
            if lower.contains("java") || lower.contains("can't find variable") || lower.contains("login") {
                return SYLoginResult(
                    success: false,
                    message: "此书源采用 JS 登录脚本且依赖 java 桥，当前版本仅支持 URL 型登录",
                    checked: false
                )
            }
            return SYLoginResult(success: false, message: "登录脚本执行失败：\(msg)", checked: false)
        }
    }

    private func evaluateLoginCheck(responseText: String) -> SYLoginResult {
        let raw = (source.loginCheckJs ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, let js else {
            return SYLoginResult(success: true, message: "登录成功", checked: false)
        }
        let script = extractCheckScript(raw)
        do {
            let output = try js.evaluate(script, result: responseText as NSString, baseUrl: source.bookSourceUrl)
            if let boolean = output as? Bool {
                return boolean
                    ? SYLoginResult(success: true, message: "登录成功，校验已通过", checked: true)
                    : SYLoginResult(success: false, message: "登录校验未通过（loginCheckJs 返回 false）", checked: true)
            }
            if let text = output as? String {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                let lower = trimmed.lowercased()
                if trimmed.isEmpty || lower == "false" || lower == "0" || lower == "null" || lower == "undefined" {
                    return SYLoginResult(success: false, message: "登录校验未通过（loginCheckJs 返回空）", checked: true)
                }
                return SYLoginResult(success: true, message: "登录成功，校验已通过", checked: true)
            }
            return SYLoginResult(success: false, message: "登录校验未通过（loginCheckJs 未返回有效结果）", checked: true)
        } catch {
            let msg = error.localizedDescription
            let lower = msg.lowercased()
            if lower.contains("java") || lower.contains("can't find variable") {
                return SYLoginResult(
                    success: false,
                    message: "登录校验脚本依赖 java 桥，无法执行 loginCheckJs",
                    checked: true
                )
            }
            return SYLoginResult(success: false, message: "登录校验脚本执行出错：\(msg)", checked: true)
        }
    }

    /// 登录请求头：书源 header 模板代入表单值。
    private func loginHeaders(formValues: [String: String]) -> [String: String] {
        var out: [String: String] = [:]
        for (k, v) in client.defaultHeaders {
            out[k] = fillTemplate(v, vars: formValues)
        }
        return out
    }

    /// 提取脚本形态的登录地址 / 动态 loginUi：`@js:` 前缀、`<js>…</js>` 包裹，
    /// 以及非 URL 且带函数定义/多行的纯脚本启发式。
    private func extractLoginScript(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("@js:") { return String(trimmed.dropFirst(4)) }
        if trimmed.hasPrefix("<js>") {
            if let end = trimmed.range(of: "</js>", options: .backwards) {
                return String(trimmed[trimmed.index(trimmed.startIndex, offsetBy: 4)..<end.lowerBound])
            }
            return String(trimmed.dropFirst(4))
        }
        if !trimmed.hasPrefix("http://"), !trimmed.hasPrefix("https://"), !trimmed.hasPrefix("/") {
            if trimmed.contains("function ") || trimmed.contains("\n") { return trimmed }
        }
        return nil
    }

    /// loginCheckJs 为纯脚本：剥掉 `@js:` / `js:` 前缀与 `<js>` 包裹后直接执行。
    private func extractCheckScript(_ raw: String) -> String {
        var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("@js:") { t = String(t.dropFirst(4)) }
        else if t.hasPrefix("js:") { t = String(t.dropFirst(3)) }
        if t.hasPrefix("<js>"), let end = t.range(of: "</js>", options: .backwards) {
            t = String(t[t.index(t.startIndex, offsetBy: 4)..<end.lowerBound])
        }
        return t
    }

    /// 动态 loginUi JS 的求值结果转 JSON 文本（对象/数组/字符串均可）。
    private func jsonText(from value: Any?) -> String? {
        switch value {
        case let text as String:
            return text
        case let dict as [String: Any]:
            if let data = try? JSONSerialization.data(withJSONObject: dict) {
                return String(data: data, encoding: .utf8)
            }
            return nil
        case let array as [Any]:
            if let data = try? JSONSerialization.data(withJSONObject: array) {
                return String(data: data, encoding: .utf8)
            }
            return nil
        default:
            return nil
        }
    }
}
