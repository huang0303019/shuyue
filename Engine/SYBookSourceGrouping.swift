import Foundation

// MARK: - 书源分组（兼容 Legado bookSourceGroup 的多分组语义）

/// 置顶 / 置底位置标记。一个书源最多处于一种 pin 状态。
enum SYSourcePinPosition: String, Codable {
    case top
    case bottom
}

/// pin 记录：记录书源被置顶 / 置底的时间，取消置顶后可按需恢复原始排序。
struct SYSourcePinRecord: Codable, Equatable {
    var position: SYSourcePinPosition
    var pinnedAt: Date
}

/// 列表展示用的一个分组小节。
struct SYSourceGroupSection: Identifiable, Equatable {
    var id: String          // 内部唯一 id
    var name: String        // 展示名
    var sourceIDs: [String] // 组内书源 bookSourceUrl 列表（保持源数组顺序）
    var kind: Kind

    enum Kind: Equatable {
        case pinnedTop      // 置顶组
        case pinnedBottom   // 置底组
        case normal         // 普通分组（来源 bookSourceGroup）
        case `default`      // 默认分组（未填 bookSourceGroup 的书源）
    }
}

/// 分组计算工具：拆分分组、构造有序分组小节、解析默认分组等。
enum SYBookSourceGrouping {
    static let defaultGroupName = "默认分组"
    static let pinnedTopGroupID = "pinned-top"
    static let pinnedBottomGroupID = "pinned-bottom"
    static let defaultGroupID = "default-group"

    /// 拆分 Legado 分组字符串：英文/中文逗号、分号、空白、换行均视为分隔符。
    static func splitGroups(_ raw: String?) -> [String] {
        guard let raw, !raw.isEmpty else { return [] }
        let separators = CharacterSet(charactersIn: ",，;；\n\t ")
        return raw
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// 书源所属分组名：未填写 bookSourceGroup 时归入默认分组。
    static func groupNames(for source: SYBookSource) -> [String] {
        let groups = splitGroups(source.bookSourceGroup)
        return groups.isEmpty ? [defaultGroupName] : groups
    }

    /// 每个非空 `bookSourceGroup` 的源数量，按首次出现顺序 —— 「移动分组」「按域名分组」等菜单的可选目标。
    /// 整表一次遍历，避免逐行重复计算。
    static func groupCounts(sources: [SYBookSource], excluding excluded: String = "") -> [(name: String, count: Int)] {
        var order: [String] = []
        var counts: [String: Int] = [:]
        for source in sources {
            for name in splitGroups(source.bookSourceGroup) {
                guard !name.isEmpty, name != excluded else { continue }
                if counts[name] == nil { order.append(name) }
                counts[name, default: 0] += 1
            }
        }
        return order.map { (name: $0, count: counts[$0] ?? 0) }
    }

    /// 按域名分组：取 `bookSourceUrl` 的主机名；无主机时回退 无域名。
    static func domain(of url: String) -> String {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if let host = URLComponents(string: trimmed)?.host, !host.isEmpty {
            return host
        }
        if let schemeRange = trimmed.range(of: "://") {
            let afterScheme = trimmed[schemeRange.upperBound...]
            if let slash = afterScheme.firstIndex(of: "/") {
                return String(afterScheme[..<slash])
            }
            return String(afterScheme)
        }
        return ""
    }

    /// 将书源数组 + pin 记录构造成有序分组小节。
    /// 顺序：置顶 -> 普通分组（名称升序）-> 默认分组 -> 置底。
    static func sections(
        sources: [SYBookSource],
        pinRecords: [String: SYSourcePinRecord]
    ) -> [SYSourceGroupSection] {
        var byNormalGroup: [String: [String]] = [:]
        var defaultGroup: [String] = []
        var pinnedTop: [String] = []
        var pinnedBottom: [String] = []

        for source in sources {
            switch pinRecords[source.bookSourceUrl]?.position {
            case .top:
                pinnedTop.append(source.bookSourceUrl)
                continue
            case .bottom:
                pinnedBottom.append(source.bookSourceUrl)
                continue
            default:
                break
            }

            let names = groupNames(for: source)
            for name in names where name != defaultGroupName {
                byNormalGroup[name, default: []].append(source.bookSourceUrl)
            }
            if names.contains(defaultGroupName) {
                defaultGroup.append(source.bookSourceUrl)
            }
        }

        var result: [SYSourceGroupSection] = []
        if !pinnedTop.isEmpty {
            result.append(SYSourceGroupSection(
                id: pinnedTopGroupID,
                name: "置顶",
                sourceIDs: pinnedTop,
                kind: .pinnedTop
            ))
        }
        for name in byNormalGroup.keys.sorted() {
            let urls = byNormalGroup[name]!
            result.append(SYSourceGroupSection(
                id: "group:\(name)",
                name: name,
                sourceIDs: urls,
                kind: .normal
            ))
        }
        if !defaultGroup.isEmpty {
            result.append(SYSourceGroupSection(
                id: defaultGroupID,
                name: defaultGroupName,
                sourceIDs: defaultGroup,
                kind: .default
            ))
        }
        if !pinnedBottom.isEmpty {
            result.append(SYSourceGroupSection(
                id: pinnedBottomGroupID,
                name: "置底",
                sourceIDs: pinnedBottom,
                kind: .pinnedBottom
            ))
        }
        return result
    }
}