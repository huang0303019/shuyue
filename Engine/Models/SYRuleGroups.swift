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

    init() {}

    init(
        bookList: String? = nil, bookListUrl: String? = nil,
        name: String? = nil, author: String? = nil, intro: String? = nil,
        coverUrl: String? = nil, bookUrl: String? = nil, wordCount: String? = nil,
        kind: String? = nil, lastChapter: String? = nil, tag: String? = nil,
        searchType: String? = nil
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

    init() {}

    init(
        bookList: String? = nil, name: String? = nil, author: String? = nil,
        intro: String? = nil, coverUrl: String? = nil, bookUrl: String? = nil,
        wordCount: String? = nil, kind: String? = nil, lastChapter: String? = nil
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

    init() {}

    init(
        url: String? = nil, chapterList: String? = nil, chapterName: String? = nil,
        chapterUrl: String? = nil, nextTocUrl: String? = nil,
        isVip: String? = nil, payType: String? = nil
    ) {
        self.url = url
        self.chapterList = chapterList
        self.chapterName = chapterName
        self.chapterUrl = chapterUrl
        self.nextTocUrl = nextTocUrl
        self.isVip = isVip
        self.payType = payType
    }
}

struct SYRuleContent: Codable, Equatable {
    var url: String?
    var nextContentUrl: String?
    var content: String?

    init() {}

    init(url: String? = nil, nextContentUrl: String? = nil, content: String? = nil) {
        self.url = url
        self.nextContentUrl = nextContentUrl
        self.content = content
    }
}