import Foundation

// MARK: - 书籍与章节模型

/// 书悦全局书籍模型：由任意书源解析出的统一结果。
struct SYBook: Identifiable, Equatable, Sendable {
    /// 稳定 ID：书源 URL + 书籍页 URL。
    var id: String { "\(sourceUrl)|\(bookUrl)" }

    var name: String
    var author: String?
    var intro: String?
    var coverUrl: String?
    var wordCount: String?
    var kind: String?
    var lastChapter: String?
    /// 归属书源 URL（bookSourceUrl）。
    var sourceUrl: String
    /// 书籍详情页 URL（如搜索结果给出的 bookUrl）。
    var bookUrl: String
    /// 详情页原始请求 URL（ruleToc.url 等可能不同）。
    var detailRequestUrl: String?

    var sourceName: String?

    init(
        name: String,
        author: String? = nil,
        intro: String? = nil,
        coverUrl: String? = nil,
        wordCount: String? = nil,
        kind: String? = nil,
        lastChapter: String? = nil,
        sourceUrl: String,
        bookUrl: String,
        detailRequestUrl: String? = nil,
        sourceName: String? = nil
    ) {
        self.name = name
        self.author = author
        self.intro = intro
        self.coverUrl = coverUrl
        self.wordCount = wordCount
        self.kind = kind
        self.lastChapter = lastChapter
        self.sourceUrl = sourceUrl
        self.bookUrl = bookUrl
        self.detailRequestUrl = detailRequestUrl
        self.sourceName = sourceName
    }
}

/// 章节模型。
struct SYChapter: Identifiable, Equatable, Sendable {
    var id: String { "\(sourceUrl)|\(url)" }

    var title: String
    var url: String
    var sourceUrl: String
    var index: Int = 0
    var isVip: Bool = false

    init(title: String, url: String, sourceUrl: String, index: Int = 0, isVip: Bool = false) {
        self.title = title
        self.url = url
        self.sourceUrl = sourceUrl
        self.index = index
        self.isVip = isVip
    }
}

/// 章节正文结果（可能含分页）。
struct SYContentResult: Equatable, Sendable {
    var content: String
    var nextUrl: String?
}