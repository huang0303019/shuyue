import SwiftUI

/// 书悦的导航分区。取消「閱讀」/墨悦式底部标签栏，全部收进左侧抽屉。
enum SYSection: String, CaseIterable, Identifiable {
    case bookshelf
    case discover
    case search
    case sources
    case history
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bookshelf: return "书房"
        case .discover: return "发现"
        case .search: return "搜索"
        case .sources: return "书源"
        case .history: return "阅读历史"
        case .settings: return "设置"
        }
    }

    var caption: String {
        switch self {
        case .bookshelf: return "我的书架与进度"
        case .discover: return "按书源逛逛"
        case .search: return "跨书源搜书"
        case .sources: return "导入与调试书源"
        case .history: return "最近读过的书"
        case .settings: return "外观与阅读偏好"
        }
    }

    var systemImage: String {
        switch self {
        case .bookshelf: return "books.vertical"
        case .discover: return "sparkles"
        case .search: return "magnifyingglass"
        case .sources: return "square.stack.3d.up"
        case .history: return "clock.arrow.circlepath"
        case .settings: return "gearshape"
        }
    }
}