import Foundation

// MARK: - 深链导入解析

/// `shuyue://` 深链解析结果。
enum SYDeepLinkAction: Equatable {
    /// 导入一段书源 JSON 文本（URLComponents 已做一层百分号解码）。
    case importText(String)
    /// 导入远程订阅链接（http/https，由主 App 自行抓取）。
    case importRemote(String)
    /// 仅打开书源页。
    case openSources
}

/// 书悦自定义 URL scheme 解析器。
///
/// 约定（与分享扩展书悦导入共用）：
/// - `shuyue://import?url=<percent-encoded http(s) 链接>`：网络导入订阅
/// - `shuyue://import?text=<percent-encoded 书源 JSON 文本>`：文本导入
/// - `shuyue://sources`：打开书源页
enum SYDeepLinkParser {
    static func parse(_ url: URL) -> SYDeepLinkAction? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "shuyue" else {
            return nil
        }
        let host = (components.host ?? "").lowercased()
        let path = components.path

        if host == "sources" || host.isEmpty && path.hasPrefix("/sources") {
            return .openSources
        }
        let isImport = host == "import" || path.hasPrefix("/import")
        guard isImport else { return nil }

        let query = components.queryItems ?? []
        if let text = query.first(where: { $0.name == "text" })?.value, !text.isEmpty {
            return .importText(text)
        }
        if let remote = query.first(where: { $0.name == "url" })?.value, !remote.isEmpty {
            return .importRemote(remote)
        }
        return nil
    }
}
