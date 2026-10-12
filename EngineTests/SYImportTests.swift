import XCTest
@testable import ShuYue

// MARK: - 导入审查流程离线校验（不依赖网络 / UI）

final class SYImportTests: XCTestCase {

    private func makeSource(
        _ name: String,
        url: String,
        group: String? = nil,
        clock: Int64? = nil,
        customOrder: Int = 0
    ) -> SYBookSource {
        SYBookSource(
            bookSourceName: name,
            bookSourceUrl: url,
            bookSourceGroup: group,
            customOrder: customOrder,
            lastUpdateTime: clock
        )
    }

    // MARK: 状态判定与默认勾选

    @MainActor
    func testPlanStatesAndDefaultSelection() {
        let incoming = [
            makeSource("新源", url: "https://new.example.com"),
            makeSource("更新源", url: "https://update.example.com", clock: 200),
            makeSource("已有源", url: "https://old.example.com", clock: 50),
        ]
        let localClocks: [String: Int64] = [
            "https://update.example.com": 100,
            "https://old.example.com": 100,
        ]
        let plan = SYImportPlan(incoming: incoming) { localClocks[$0] }

        XCTAssertEqual(plan.totalCount, 3)
        XCTAssertEqual(plan.entries[0].state, .new)
        XCTAssertEqual(plan.entries[1].state, .update)
        XCTAssertEqual(plan.entries[2].state, .existing)
        // 新增 + 更新默认勾选，已有默认不勾选。
        XCTAssertEqual(plan.selectedIDs, Set([0, 1]))
        XCTAssertEqual(plan.newCount, 1)
        XCTAssertEqual(plan.updateCount, 1)
        XCTAssertEqual(plan.existingCount, 1)
    }

    @MainActor
    func testSameClockIsExistingNotUpdate() {
        let incoming = [makeSource("同时间", url: "https://same.example.com", clock: 100)]
        let plan = SYImportPlan(incoming: incoming) { _ in 100 }
        XCTAssertEqual(plan.entries[0].state, .existing)
        XCTAssertTrue(plan.selectedIDs.isEmpty)
    }

    @MainActor
    func testMissingClockIsExistingWhenLocalExists() {
        // 导入条目没有 lastUpdateTime（视为 0），无法证明比本地新 → 已有。
        let incoming = [makeSource("无时钟", url: "https://noclock.example.com", clock: nil)]
        let plan = SYImportPlan(incoming: incoming) { _ in 100 }
        XCTAssertEqual(plan.entries[0].state, .existing)
    }

    // MARK: 勾选

    @MainActor
    func testToggleAndSelectAll() {
        let incoming = [
            makeSource("A", url: "https://a.example.com"),
            makeSource("B", url: "https://b.example.com"),
            makeSource("C", url: "https://c.example.com"),
        ]
        let plan = SYImportPlan(incoming: incoming) { _ in nil }
        XCTAssertEqual(plan.selectedCount, 3)
        XCTAssertTrue(plan.isSelectingAll)

        plan.toggleSelectAll()
        XCTAssertEqual(plan.selectedCount, 0)

        plan.toggle(1)
        XCTAssertEqual(plan.selectedIDs, Set([1]))
        XCTAssertEqual(plan.selectedSources.map(\.bookSourceUrl), ["https://b.example.com"])

        plan.toggleSelectAll()
        XCTAssertEqual(plan.selectedCount, 3)
    }

    @MainActor
    func testSelectAllNewAndUpdateOnly() {
        let incoming = [
            makeSource("A", url: "https://a.example.com"),
            makeSource("B", url: "https://b.example.com", clock: 200),
            makeSource("C", url: "https://c.example.com", clock: 50),
        ]
        let localClocks: [String: Int64] = [
            "https://b.example.com": 100,
            "https://c.example.com": 100,
        ]
        let plan = SYImportPlan(incoming: incoming) { localClocks[$0] }
        // 默认：A(新增) + B(更新) 勾选，C(已有) 不勾。
        XCTAssertEqual(plan.selectedIDs, Set([0, 1]))

        plan.toggleSelectAllNew()
        XCTAssertEqual(plan.selectedIDs, Set([1]))  // 取消全选「新增」
        plan.toggleSelectAllUpdate()
        XCTAssertEqual(plan.selectedIDs, Set())     // 再取消全选「更新」

        plan.toggleSelectAllNew()
        plan.toggleSelectAllUpdate()
        XCTAssertEqual(plan.selectedIDs, Set([0, 1]))
    }

    // MARK: 选项合并

    func testMergeKeepsLocalOrderOnUpdate() {
        let incoming = makeSource("新名", url: "https://same.example.com", customOrder: 99)
        let local = makeSource("旧名", url: "https://same.example.com", customOrder: 5)
        let options = SYImportOptions(keepCustomOrder: true)
        let merged = options.merged(incoming: incoming, local: local)
        XCTAssertEqual(merged.customOrder, 5)
        XCTAssertEqual(merged.bookSourceName, "新名")
    }

    func testMergeKeepsEverythingWhenRequested() {
        let incoming = makeSource(
            "新名", url: "https://same.example.com", group: "导入组", customOrder: 8
        )
        var local = makeSource("旧名", url: "https://same.example.com", group: "本地组", customOrder: 3)
        local.enabled = false
        local.enabledExplore = true
        let options = SYImportOptions(
            keepName: true, keepGroup: true, keepEnable: true, keepCustomOrder: true
        )
        let merged = options.merged(incoming: incoming, local: local)
        XCTAssertEqual(merged.bookSourceName, "旧名")
        XCTAssertEqual(merged.bookSourceGroup, "本地组")
        XCTAssertFalse(merged.enabled)
        XCTAssertTrue(merged.enabledExplore)
        XCTAssertEqual(merged.customOrder, 3)
    }

    func testMergeGroupReplace() {
        let incoming = makeSource("A", url: "https://a.example.com", group: "原组")
        let options = SYImportOptions(groupName: "新分组")
        let merged = options.merged(incoming: incoming, local: nil)
        XCTAssertEqual(merged.bookSourceGroup, "新分组")
    }

    func testMergeGroupAppendDedupe() {
        let incoming = makeSource("A", url: "https://a.example.com", group: "原组,其他")
        let options = SYImportOptions(groupName: "其他", addsToExistingGroups: true)
        let merged = options.merged(incoming: incoming, local: nil)
        XCTAssertEqual(merged.bookSourceGroup, "原组,其他")
    }

    func testMergeKeepsGroupWhenAppendOnLocal() {
        let incoming = makeSource("A", url: "https://a.example.com", group: "导入组")
        let local = makeSource("A", url: "https://a.example.com", group: "本地组")
        let options = SYImportOptions(keepGroup: true, groupName: "新增组", addsToExistingGroups: true)
        let merged = options.merged(incoming: incoming, local: local)
        XCTAssertEqual(merged.bookSourceGroup, "本地组,新增组")
    }

    // MARK: 分组串拆分

    func testSplitGroups() {
        XCTAssertEqual(SYImportOptions.splitGroups("A,B,C"), ["A", "B", "C"])
        XCTAssertEqual(SYImportOptions.splitGroups("A，B；C"), ["A", "B", "C"])
        XCTAssertEqual(SYImportOptions.splitGroups(" A ,  B "), ["A", "B"])
        XCTAssertEqual(SYImportOptions.splitGroups(nil), [])
        XCTAssertEqual(SYImportOptions.splitGroups(""), [])
    }

    func testGroupsByAddingDedupe() {
        XCTAssertEqual(SYImportOptions.groupsByAdding("B", to: "A,B"), "A,B")
        XCTAssertEqual(SYImportOptions.groupsByAdding("C", to: " A , B "), "A,B,C")
        XCTAssertEqual(SYImportOptions.groupsByAdding("A", to: nil), "A")
    }
}