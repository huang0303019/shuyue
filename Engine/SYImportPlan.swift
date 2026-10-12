import Foundation
import Combine

// MARK: - 导入条目状态

/// 一条待导入书源与本库已有内容的对比状态（对应 Legado 导入对话框的 新增 / 更新 / 已有）。
enum SYImportItemState: Equatable {
    /// 库中没有同 url 的书源。
    case new
    /// 库中有同 url 书源，且导入条目声明的 lastUpdateTime 比本地新。
    case update
    /// 库中有同 url 书源，且不比本地新。默认不勾选。
    case existing
}

// MARK: - 导入选项

/// 导入覆盖时的保留策略与目标分组，对应 Legado 导入对话框的
/// 保留原名 / 保留分组 / 保留启用状态 / 分组 一组选项。
struct SYImportOptions: Equatable {
    /// 更新已有书源时，保留本地的 bookSourceName。
    var keepName: Bool = false
    /// 更新已有书源时，保留本地的 bookSourceGroup（在 groupName 之前应用，支持「附加分组」叠加）。
    var keepGroup: Bool = false
    /// 更新已有书源时，保留本地的 enabled / enabledExplore。
    var keepEnable: Bool = false
    /// 更新已有书源时，保留本地的 customOrder（与 Legado 行为一致，手动导入默认开启）。
    var keepCustomOrder: Bool = false
    /// 目标分组；nil / 空白表示不改动分组。
    var groupName: String?
    /// true 表示把 groupName 追加到已有分组串；false 表示整体替换。
    var addsToExistingGroups: Bool = false

    /// 全量覆盖，什么都不保留 —— 整包恢复直接导入时使用。
    static let direct = SYImportOptions()

    /// 手动导入经过确认清单时的默认值：更新时保留本地排序，与 Legado 一致。
    static let manualDefaults = SYImportOptions(keepCustomOrder: true)

    var needsLocalCopy: Bool { keepName || keepGroup || keepEnable || keepCustomOrder }

    var trimmedGroupName: String? {
        guard let groupName else { return nil }
        let trimmed = groupName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// 把本地用户字段折叠进导入条目，再按 groupName 归档。
    /// 无论 keep 开关如何，未更新的新书源直接取 JSON 声明的字段。
    func merged(incoming: SYBookSource, local: SYBookSource?) -> SYBookSource {
        var source = incoming
        if let local {
            if keepName {
                source.bookSourceName = local.bookSourceName
            }
            if keepGroup {
                source.bookSourceGroup = local.bookSourceGroup
            }
            if keepEnable {
                source.enabled = local.enabled
                source.enabledExplore = local.enabledExplore
            }
            if keepCustomOrder {
                source.customOrder = local.customOrder
            }
        }
        if let group = trimmedGroupName {
            if addsToExistingGroups {
                source.bookSourceGroup = Self.groupsByAdding(group, to: source.bookSourceGroup)
            } else {
                source.bookSourceGroup = group
            }
        }
        return source
    }

    /// 把一个分组名追加到已有分组串：去重并保持原有顺序，最后用逗号重排。
    static func groupsByAdding(_ group: String, to existing: String?) -> String {
        var names: [String] = []
        var seen = Set<String>()
        for name in splitGroups(existing) where !seen.contains(name) {
            seen.insert(name)
            names.append(name)
        }
        if !seen.contains(group) {
            names.append(group)
        }
        return names.joined(separator: ",")
    }

    /// 拆分组名：兼容 Legado 的 `, ; ， ；` 与空白分隔。
    static func splitGroups(_ raw: String?) -> [String] {
        guard let raw, !raw.isEmpty else { return [] }
        return raw.split(whereSeparator: { separator in
            separator == "," || separator == ";" || separator == "，" || separator == "；"
                || separator.isWhitespace
        })
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    }
}

// MARK: - 导入计划

/// 导入确认清单背后的状态：拆包后每一条与本地库的对比、勾选集合与统计。
///
/// 勾选以条目在包内的位置为 id —— 同一份包允许合法地出现同名同 url 的两条，
/// 行位置才是包内稳定身份。统计在 init 一次算好，避免大书源包（数千条）逐次全表扫描。
@MainActor
final class SYImportPlan: ObservableObject, Identifiable {
    let id = UUID()

    /// 一行：入站书源 + 与本库对比状态。
    struct Entry: Identifiable {
        let id: Int
        var source: SYBookSource
        var state: SYImportItemState
    }

    @Published private(set) var entries: [Entry]
    /// 被勾选的行 id（一次 Set 写入，点击只发布一次）。
    @Published private(set) var selectedIDs: Set<Int>
    /// 新增 / 更新行 id，用于「全选新增」「全选更新」，避免体每次重算。
    private(set) var newIDs: Set<Int>
    private(set) var updateIDs: Set<Int>

    /// - Parameters:
    ///   - incoming: 已解析的书源，保持包内顺序。
    ///   - existingClock: 库中同 url 书源的 lastUpdateTime；没有则为 nil。
    init(incoming: [SYBookSource], existingClock: (String) -> Int64?) {
        var entries: [Entry] = []
        entries.reserveCapacity(incoming.count)
        var selected: Set<Int> = []
        var newIDs: Set<Int> = []
        var updateIDs: Set<Int> = []

        for (index, source) in incoming.enumerated() {
            let state: SYImportItemState
            if let clock = existingClock(source.bookSourceUrl) {
                let incomingClock = source.lastUpdateTime ?? 0
                state = clock < incomingClock ? .update : .existing
            } else {
                state = .new
            }
            entries.append(Entry(id: index, source: source, state: state))
            switch state {
            case .new:
                newIDs.insert(index)
                selected.insert(index)
            case .update:
                updateIDs.insert(index)
                selected.insert(index)
            case .existing:
                // 与 Legado 一致：作者未标记为更新的重导入默认不勾选，
                // 避免覆盖本地修改；用户仍可手动勾选。
                break
            }
        }

        self.entries = entries
        self.selectedIDs = selected
        self.newIDs = newIDs
        self.updateIDs = updateIDs
    }

    // MARK: 汇总

    var totalCount: Int { entries.count }
    var selectedCount: Int { selectedIDs.count }
    var newCount: Int { newIDs.count }
    var updateCount: Int { updateIDs.count }
    var existingCount: Int { entries.count - newIDs.count - updateIDs.count }
    var isEmpty: Bool { entries.isEmpty }

    var isSelectingAll: Bool {
        !entries.isEmpty && selectedIDs.count == entries.count
    }

    var isSelectingAllNew: Bool {
        !newIDs.isEmpty && newIDs.isSubset(of: selectedIDs)
    }

    var isSelectingAllUpdate: Bool {
        !updateIDs.isEmpty && updateIDs.isSubset(of: selectedIDs)
    }

    func isSelected(_ id: Int) -> Bool {
        selectedIDs.contains(id)
    }

    /// 已勾选条目，按包内顺序 —— 确认导入时实际写入的内容。
    var selectedSources: [SYBookSource] {
        entries.filter { selectedIDs.contains($0.id) }.map(\.source)
    }

    // MARK: 勾选

    func toggle(_ id: Int) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    /// 全选 / 取消全选（底部按钮，全部勾选时点击变取消）。
    func toggleSelectAll() {
        if isSelectingAll {
            selectedIDs = []
        } else {
            selectedIDs = Set(entries.map(\.id))
        }
    }

    /// 只勾选所有「新增」行；已全选新增时点击则取消。
    func toggleSelectAllNew() {
        if isSelectingAllNew {
            selectedIDs.subtract(newIDs)
        } else {
            selectedIDs.formUnion(newIDs)
        }
    }

    /// 只勾选所有「更新」行；已全选更新时点击则取消。
    func toggleSelectAllUpdate() {
        if isSelectingAllUpdate {
            selectedIDs.subtract(updateIDs)
        } else {
            selectedIDs.formUnion(updateIDs)
        }
    }
}

// MARK: - 导入解析错误

/// 携带可直接展示中文信息的导入错误（`Result` 的 Failure 类型必须遵守 `Error`）。
struct SYImportMessage: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
