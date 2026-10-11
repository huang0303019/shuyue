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
    var concurrentRate: Int = 0
    var respondTime: Int = 15_000

    // ---- 网络 ----
    var header: String?
    var loginUrl: String?
    var loginUi: String?

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
        case searchUrl, exploreUrl
        case ruleSearch, ruleExplore, ruleBookInfo, ruleToc, ruleContent
        case jsLib, lastUpdateTime, bookUrlPattern, bookUrlRegex, checkKeyUrl
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
        concurrentRate: Int = 0,
        respondTime: Int = 15_000,
        header: String? = nil,
        loginUrl: String? = nil,
        loginUi: String? = nil,
        searchUrl: String? = nil,
        exploreUrl: String? = nil,
        ruleSearch: SYRuleSearch = SYRuleSearch(),
        ruleExplore: SYRuleExplore = SYRuleExplore(),
        ruleBookInfo: SYRuleBookInfo = SYRuleBookInfo(),
        ruleToc: SYRuleToc = SYRuleToc(),
        ruleContent: SYRuleContent = SYRuleContent(),
        jsLib: String? = nil,
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
        self.searchUrl = searchUrl
        self.exploreUrl = exploreUrl
        self.ruleSearch = ruleSearch
        self.ruleExplore = ruleExplore
        self.ruleBookInfo = ruleBookInfo
        self.ruleToc = ruleToc
        self.ruleContent = ruleContent
        self.jsLib = jsLib
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