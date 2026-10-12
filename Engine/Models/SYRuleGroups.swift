import Foundation

// MARK: - 规则组模型（与 Legado ruleSearch / ruleExplore / ruleBookInfo / ruleToc / ruleContent 对齐）

struct SYRuleSearch: Codable, Equatable {
    var bookList: String?
    var bookListUrl: String?
    var name: String?
    var author: String?
    var intro: String?
    var coverUrl: String?
    var bookUrl: String?
    var wordCount: String?
    var kind: String?
    var lastChapter: String?
    var tag: String?
    var searchType: String?
    /// Legado CheckSource.keyword —— 校验搜索阶段使用的测试关键词；为空时使用默认词。
    var checkKeyWord: String?
    /// Legado 搜索预处理 JS（字段名 init）：获取搜索页 HTML 后执行再解析。
    var initScript: String?

    enum CodingKeys: String, CodingKey {
        case bookList, bookListUrl, name, author, intro, coverUrl, bookUrl
        case wordCount, kind, lastChapter, tag, searchType, checkKeyWord
        case initScript = "init"
    }

    init() {}

    init(
        bookList: String? = nil, bookListUrl: String? = nil,
        name: String? = nil, author: String? = nil, intro: String? = nil,
        coverUrl: String? = nil, bookUrl: String? = nil, wordCount: String? = nil,
        kind: String? = nil, lastChapter: String? = nil, tag: String? = nil,
        searchType: String? = nil, checkKeyWord: String? = nil,
        initScript: String? = nil
    ) {
        self.bookList = bookList
        self.bookListUrl = bookListUrl
        self.name = name
        self.author = author
        self.intro = intro
        self.coverUrl = coverUrl
        self.bookUrl = bookUrl
        self.wordCount = wordCount
        self.kind = kind
        self.lastChapter = lastChapter
        self.tag = tag
        self.searchType = searchType
        self.checkKeyWord = checkKeyWord
        self.initScript = initScript
    }
}

struct SYRuleExplore: Codable, Equatable {
    var bookList: String?
    var name: String?
    var author: String?
    var intro: String?
    var coverUrl: String?
    var bookUrl: String?
    var wordCount: String?
    var kind: String?
    var lastChapter: String?
    /// Legado 发现预处理 JS（字段名 init）：获取发现页 HTML 后执行再解析。
    var initScript: String?

    enum CodingKeys: String, CodingKey {
        case bookList, name, author, intro, coverUrl, bookUrl
        case wordCount, kind, lastChapter
        case initScript = "init"
    }

    init() {}

    init(
        bookList: String? = nil, name: String? = nil, author: String? = nil,
        intro: String? = nil, coverUrl: String? = nil, bookUrl: String? = nil,
        wordCount: String? = nil, kind: String? = nil, lastChapter: String? = nil,
        initScript: String? = nil
    ) {
        self.bookList = bookList
        self.name = name
        self.author = author
        self.intro = intro
        self.coverUrl = coverUrl
        self.bookUrl = bookUrl
        self.wordCount = wordCount
        self.kind = kind
        self.lastChapter = lastChapter
        self.initScript = initScript
    }
}

struct SYRuleBookInfo: Codable, Equatable {
    var initRule: String?        // Legado 字段名 init（保留 init 会与 Swift 冲突）
    var name: String?
    var author: String?
    var intro: String?
    var coverUrl: String?
    var kind: String?
    var wordCount: String?
    var bookUrlPattern: String?
    var touxiangUrl: String?

    enum CodingKeys: String, CodingKey {
        case initRule = "init"
        case name, author, intro, coverUrl, kind, wordCount, bookUrlPattern, touxiangUrl
    }

    init() {}

    init(
        initRule: String? = nil, name: String? = nil, author: String? = nil,
        intro: String? = nil, coverUrl: String? = nil, kind: String? = nil,
        wordCount: String? = nil, bookUrlPattern: String? = nil, touxiangUrl: String? = nil
    ) {
        self.initRule = initRule
        self.name = name
        self.author = author
        self.intro = intro
        self.coverUrl = coverUrl
        self.kind = kind
        self.wordCount = wordCount
        self.bookUrlPattern = bookUrlPattern
        self.touxiangUrl = touxiangUrl
    }
}

struct SYRuleToc: Codable, Equatable {
    var url: String?
    var chapterList: String?
    var chapterName: String?
    var chapterUrl: String?
    var nextTocUrl: String?
    var isVip: String?
    var payType: String?
    /// Legado preUpdateJs：加载目录页后先执行此 JS 再解析。
    var preUpdateJs: String?
    /// Legado formatJs：章节名格式化规则。
    var formatJs: String?
    /// Legado isVolume：是否表示分卷条目。
    var isVolume: String?
    /// Legado isPay：是否表示付费章节。
    var isPay: String?

    init() {}

    init(
        url: String? = nil, chapterList: String? = nil, chapterName: String? = nil,
        chapterUrl: String? = nil, nextTocUrl: String? = nil,
        isVip: String? = nil, payType: String? = nil,
        preUpdateJs: String? = nil, formatJs: String? = nil,
        isVolume: String? = nil, isPay: String? = nil
    ) {
        self.url = url
        self.chapterList = chapterList
        self.chapterName = chapterName
        self.chapterUrl = chapterUrl
        self.nextTocUrl = nextTocUrl
        self.isVip = isVip
        self.payType = payType
        self.preUpdateJs = preUpdateJs
        self.formatJs = formatJs
        self.isVolume = isVolume
        self.isPay = isPay
    }
}

struct SYRuleContent: Codable, Equatable {
    var url: String?
    var nextContentUrl: String?
    var content: String?
    /// Legado title：正文内章节标题规则。
    var title: String?
    /// Legado webJs：通过 WebView 加载正文的规则。
    var webJs: String?
    /// Legado replaceRegex：正文替换规则，每行 regex@@@replacement。
    var replaceRegex: String?
    /// Legado imageStyle：图片样式规则。
    var imageStyle: String?

    init() {}

    init(
        url: String? = nil, nextContentUrl: String? = nil, content: String? = nil,
        title: String? = nil, webJs: String? = nil,
        replaceRegex: String? = nil, imageStyle: String? = nil
    ) {
        self.url = url
        self.nextContentUrl = nextContentUrl
        self.content = content
        self.title = title
        self.webJs = webJs
        self.replaceRegex = replaceRegex
        self.imageStyle = imageStyle
    }
}