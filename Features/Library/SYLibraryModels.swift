import SwiftUI
import Foundation

// MARK: - 书架 / 历史 / 搜索 / 设置 数据模型

/// 书架条目：书籍元数据 + 阅读进度 + 分组。
struct SYBookshelfItem: Identifiable, Codable, Equatable {
    var id: String { book.id }
    var book: SYBook
    var group: String
    var progress: Double
    var chapterIndex: Int
    var chapterTitle: String?
    var addedAt: Date
    var updatedAt: Date

    init(
        book: SYBook,
        group: String = "想读",
        progress: Double = 0,
        chapterIndex: Int = 0,
        chapterTitle: String? = nil,
        addedAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.book = book
        self.group = group
        self.progress = progress
        self.chapterIndex = chapterIndex
        self.chapterTitle = chapterTitle
        self.addedAt = addedAt
        self.updatedAt = updatedAt
    }
}

/// 阅读历史条目：每本书只保留最新一条。
struct SYHistoryEntry: Identifiable, Codable, Equatable {
    var id: String { bookId }
    var bookId: String
    var book: SYBook
    var chapterTitle: String?
    var date: Date

    init(bookId: String, book: SYBook, chapterTitle: String?, date: Date = Date()) {
        self.bookId = bookId
        self.book = book
        self.chapterTitle = chapterTitle
        self.date = date
    }
}

/// 单个书源的搜索结果（含失败原因）。
struct SYSearchGroup: Identifiable, Sendable {
    var id: String { sourceUrl }
    var sourceUrl: String
    var sourceName: String
    var books: [SYBook]
    var error: String?
}

/// 发现页分类项（由 exploreUrl 的 JSON 分类解析而来）。
struct SYExploreCategory: Identifiable, Hashable {
    var id: String { title + "|" + url }
    var title: String
    var url: String
}

/// 书源导入结果。
struct SYImportSummary: Equatable {
    var added: Int = 0
    var updated: Int = 0
    var issues: [String] = []
    var failureMessage: String?

    var isFailure: Bool { failureMessage != nil }

    /// 面向用户的一句话结果。
    var text: String {
        if let failureMessage { return failureMessage }
        var parts: [String] = []
        if added > 0 { parts.append("新增 \(added) 个书源") }
        if updated > 0 { parts.append("更新 \(updated) 个书源") }
        if parts.isEmpty { parts.append("没有可导入的书源") }
        if !issues.isEmpty { parts.append(issues.joined(separator: "；")) }
        return parts.joined(separator: "，")
    }

    static func failure(_ message: String) -> SYImportSummary {
        SYImportSummary(failureMessage: message)
    }
}

// MARK: - 阅读外观

enum ReaderTheme: String, Codable, CaseIterable, Identifiable {
    case paper
    case sepia
    case night

    var id: String { rawValue }

    var title: String {
        switch self {
        case .paper: return "宣纸"
        case .sepia: return "牛皮"
        case .night: return "夜墨"
        }
    }

    var background: Color {
        switch self {
        case .paper: return Color(red: 0.96, green: 0.94, blue: 0.90)
        case .sepia: return Color(red: 0.93, green: 0.88, blue: 0.78)
        case .night: return Color(red: 0.08, green: 0.07, blue: 0.06)
        }
    }

    var textColor: Color {
        switch self {
        case .paper, .sepia: return Color(red: 0.11, green: 0.10, blue: 0.09)
        case .night: return Color(red: 0.80, green: 0.77, blue: 0.71)
        }
    }

    var controlsBackground: Color {
        switch self {
        case .paper, .sepia: return Color.white.opacity(0.95)
        case .night: return Color(red: 0.15, green: 0.14, blue: 0.12).opacity(0.96)
        }
    }

    var controlsText: Color {
        switch self {
        case .paper, .sepia: return Color(red: 0.11, green: 0.10, blue: 0.09)
        case .night: return Color(red: 0.85, green: 0.82, blue: 0.76)
        }
    }
}

struct SYReaderSettings: Codable, Equatable {
    var theme: ReaderTheme = .paper
    var fontSize: Double = 19
    var lineSpacing: Double = 8
    var useSerif: Bool = true
}