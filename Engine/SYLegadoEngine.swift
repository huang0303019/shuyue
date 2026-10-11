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
        self.js = SYJavaScriptContext(jsLib: source.jsLib)
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
        if let commaRange = t.lastRange(of: ",{") {
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
}