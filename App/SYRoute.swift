import Foundation

// MARK: - 导航路由

/// 书悦用 `NavigationStack` 承载详情与阅读器；不使用系统底部标签栏。
enum SYRoute: Hashable {
    /// 书籍详情页。
    case bookDetail(SYBook)
    /// 阅读器；可指定起始章节下标。
    case reader(SYBook, Int?)
}