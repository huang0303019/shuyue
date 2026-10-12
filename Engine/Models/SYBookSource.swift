import Foundation

// MARK: - 书源模型（兼容 Legado/阅读 3.0 书源 JSON 规范）

/// 顶层书源定义。字段与 Legado 公开 JSON 结构对齐，全部使用可选/带默认值以容错导入。
struct SYBookSource: Codable, Identifiable, Equatable {
    var id: String { bookSourceUrl }

    // ---- 标识与分组 ----
    var bookSourceName: String
    var bookSourceUrl: String
    var bookSourceGroup: String?
    var bookSourceType: Int = 0            // 0 文本 / 1 有声 / 2 图片
    var bookSourceComment: String?

    // ---- 开关与权重 ----
    var enabled: Bool = true
    var enabledExplore: Bool = false
    var enabledSearch: Bool = true
    var enabledCookieJar: Bool = false
    var eventListener: Bool = false
    var customOrder: Int = 0
    var customButton: Bool = false
    var weight: Int = 0
    var concurrentRate: String?
    var respondTime: Int = 15_000

    // ---- 网络 ----
    var header: String?
    var loginUrl: String?
    var loginUi: String?
    /// 登录后校验脚本：以登录响应文本为 `result` 执行，非空返回值视为已登录。
    var loginCheckJs: String?

    // ---- 入口 URL ----
    var searchUrl: String?
    var exploreUrl: String?

    // ---- 规则 ----
    var ruleSearch: SYRuleSearch = SYRuleSearch()
    var ruleExplore: SYRuleExplore = SYRuleExplore()
    var ruleBookInfo: SYRuleBookInfo = SYRuleBookInfo()
    var ruleToc: SYRuleToc = SYRuleToc()
    var ruleContent: SYRuleContent = SYRuleContent()

    // ---- 脚本 ----
    var jsLib: String?

    // ---- 源变量 ----
    /// JSON 文本变量：书源 JS 通过 `source.getVariable()` 读取。
    var variable: String?
    /// 源变量说明：展示给用户作为填写指引。
    var variableComment: String?

    // ---- 维护信息 ----
    var lastUpdateTime: Int64?
    var bookUrlPattern: String?
    var bookUrlRegex: String?
    var checkKeyUrl: String?

    enum CodingKeys: String, CodingKey {
        case bookSourceName, bookSourceUrl, bookSourceGroup, bookSourceType
        case bookSourceComment, enabled, enabledExplore, enabledSearch
        case enabledCookieJar, eventListener, customOrder, customButton
        case weight, concurrentRate, respondTime, header, loginUrl, loginUi
        case loginCheckJs, searchUrl, exploreUrl
        case ruleSearch, ruleExplore, ruleBookInfo, ruleToc, ruleContent
        case jsLib, lastUpdateTime, bookUrlPattern, bookUrlRegex, checkKeyUrl
        case variable, variableComment
    }

    /// 容错解码：Legado 书源在字段缺失、以及数字/字符串混用（如 concurrentRate）上差异很大，
    /// 这里统一用 decodeIfPresent + 类型兜底，避免因单个字段导致整份书源导入失败。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        func str(_ key: CodingKeys) -> String? {
            if let v = try? c.decodeIfPresent(String.self, forKey: key) { return v }
            if let v = try? c.decodeIfPresent(Int.self, forKey: key) { return String(v) }
            if let v = try? c.decodeIfPresent(Double.self, forKey: key) { return String(v) }
            if let v = try? c.decodeIfPresent(Bool.self, forKey: key) { return String(v) }
            return nil
        }
        func int(_ key: CodingKeys, _ def: Int) -> Int {
            if let v = try? c.decodeIfPresent(Int.self, forKey: key) { return v }
            if let v = try? c.decodeIfPresent(String.self, forKey: key), let i = Int(v) { return i }
            if let v = try? c.decodeIfPresent(Double.self, forKey: key) { return Int(v) }
            return def
        }
        func bool(_ key: CodingKeys, _ def: Bool) -> Bool {
            if let v = try? c.decodeIfPresent(Bool.self, forKey: key) { return v }
            if let v = try? c.decodeIfPresent(Int.self, forKey: key) { return v != 0 }
            if let v = try? c.decodeIfPresent(String.self, forKey: key) {
                let t = v.trimmingCharacters(in: .whitespaces).lowercased()
                if t == "true" || t == "1" { return true }
                if t == "false" || t == "0" || t.isEmpty { return false }
            }
            return def
        }
        func rules<T: Decodable>(_ key: CodingKeys, _ type: T.Type) -> T? {
            try? c.decodeIfPresent(T.self, forKey: key)
        }

        bookSourceName = str(.bookSourceName) ?? ""
        bookSourceUrl = str(.bookSourceUrl) ?? ""
        bookSourceGroup = str(.bookSourceGroup)
        bookSourceType = int(.bookSourceType, 0)
        bookSourceComment = str(.bookSourceComment)
        enabled = bool(.enabled, true)
        enabledExplore = bool(.enabledExplore, false)
        enabledSearch = bool(.enabledSearch, true)
        enabledCookieJar = bool(.enabledCookieJar, false)
        eventListener = bool(.eventListener, false)
        customOrder = int(.customOrder, 0)
        customButton = bool(.customButton, false)
        weight = int(.weight, 0)
        concurrentRate = str(.concurrentRate)
        respondTime = int(.respondTime, 15_000)
        header = str(.header)
        loginUrl = str(.loginUrl)
        loginUi = str(.loginUi)
        loginCheckJs = str(.loginCheckJs)
        searchUrl = str(.searchUrl)
        exploreUrl = str(.exploreUrl)
        ruleSearch = rules(.ruleSearch, SYRuleSearch.self) ?? SYRuleSearch()
        ruleExplore = rules(.ruleExplore, SYRuleExplore.self) ?? SYRuleExplore()
        ruleBookInfo = rules(.ruleBookInfo, SYRuleBookInfo.self) ?? SYRuleBookInfo()
        ruleToc = rules(.ruleToc, SYRuleToc.self) ?? SYRuleToc()
        ruleContent = rules(.ruleContent, SYRuleContent.self) ?? SYRuleContent()
        jsLib = str(.jsLib)
        variable = str(.variable)
        variableComment = str(.variableComment)
        if let v = try? c.decodeIfPresent(Int64.self, forKey: .lastUpdateTime) {
            lastUpdateTime = v
        } else if let s = str(.lastUpdateTime), let v = Int64(s) {
            lastUpdateTime = v
        } else {
            lastUpdateTime = nil
        }
        bookUrlPattern = str(.bookUrlPattern)
        bookUrlRegex = str(.bookUrlRegex)
        checkKeyUrl = str(.checkKeyUrl)
    }

    init(
        bookSourceName: String,
        bookSourceUrl: String,
        bookSourceGroup: String? = nil,
        bookSourceType: Int = 0,
        bookSourceComment: String? = nil,
        enabled: Bool = true,
        enabledExplore: Bool = false,
        enabledSearch: Bool = true,
        enabledCookieJar: Bool = false,
        eventListener: Bool = false,
        customOrder: Int = 0,
        customButton: Bool = false,
        weight: Int = 0,
        concurrentRate: String? = nil,
        respondTime: Int = 15_000,
        header: String? = nil,
        loginUrl: String? = nil,
        loginUi: String? = nil,
        loginCheckJs: String? = nil,
        searchUrl: String? = nil,
        exploreUrl: String? = nil,
        ruleSearch: SYRuleSearch = SYRuleSearch(),
        ruleExplore: SYRuleExplore = SYRuleExplore(),
        ruleBookInfo: SYRuleBookInfo = SYRuleBookInfo(),
        ruleToc: SYRuleToc = SYRuleToc(),
        ruleContent: SYRuleContent = SYRuleContent(),
        jsLib: String? = nil,
        variable: String? = nil,
        variableComment: String? = nil,
        lastUpdateTime: Int64? = nil,
        bookUrlPattern: String? = nil,
        bookUrlRegex: String? = nil,
        checkKeyUrl: String? = nil
    ) {
        self.bookSourceName = bookSourceName
        self.bookSourceUrl = bookSourceUrl
        self.bookSourceGroup = bookSourceGroup
        self.bookSourceType = bookSourceType
        self.bookSourceComment = bookSourceComment
        self.enabled = enabled
        self.enabledExplore = enabledExplore
        self.enabledSearch = enabledSearch
        self.enabledCookieJar = enabledCookieJar
        self.eventListener = eventListener
        self.customOrder = customOrder
        self.customButton = customButton
        self.weight = weight
        self.concurrentRate = concurrentRate
        self.respondTime = respondTime
        self.header = header
        self.loginUrl = loginUrl
        self.loginUi = loginUi
        self.loginCheckJs = loginCheckJs
        self.searchUrl = searchUrl
        self.exploreUrl = exploreUrl
        self.ruleSearch = ruleSearch
        self.ruleExplore = ruleExplore
        self.ruleBookInfo = ruleBookInfo
        self.ruleToc = ruleToc
        self.ruleContent = ruleContent
        self.jsLib = jsLib
        self.variable = variable
        self.variableComment = variableComment
        self.lastUpdateTime = lastUpdateTime
        self.bookUrlPattern = bookUrlPattern
        self.bookUrlRegex = bookUrlRegex
        self.checkKeyUrl = checkKeyUrl
    }

    /// JSON 解码（容忍未知字段）。
    init?(jsonData: Data) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        guard let value = try? decoder.decode(SYBookSource.self, from: jsonData) else {
            return nil
        }
        self = value
    }

    /// JSON 编码。
    func jsonData() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(self)
    }
}

// MARK: - 并发率

extension SYBookSource {
    /// 并发率数值：Legado 书源 `concurrentRate` 为字符串，`0` / 空 / 非数字表示不限制；
    /// 大于 0 时作为同一书源同时进行的网络请求数上限。
    var concurrentRateLimit: Int? {
        guard let raw = concurrentRate, let value = Int(raw), value > 0 else { return nil }
        return value
    }
}
