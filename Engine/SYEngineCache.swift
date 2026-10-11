import Foundation

// MARK: - 书源执行器缓存

/// 按书源地址缓存 `SYLegadoEngine`，避免每次搜索/阅读重复构造网络层与 JS 上下文。
actor SYEngineCache {
    private var engines: [String: SYLegadoEngine] = [:]

    func engine(for source: SYBookSource) -> SYLegadoEngine {
        if let existing = engines[source.bookSourceUrl] {
            return existing
        }
        let created = SYLegadoEngine(source: source)
        engines[source.bookSourceUrl] = created
        return created
    }

    func dropEngine(for url: String) {
        engines[url] = nil
    }

    func dropAll() {
        engines.removeAll()
    }
}