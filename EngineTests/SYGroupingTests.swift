import XCTest
@testable import ShuYue

// MARK: - 分组工具离线校验（不依赖网络 / UI）

final class SYGroupingTests: XCTestCase {

    private func makeSource(_ name: String, url: String, group: String? = nil) -> SYBookSource {
        SYBookSource(bookSourceName: name, bookSourceUrl: url, bookSourceGroup: group)
    }

    // MARK: 拆分分组

    func testSplitGroupsSeparators() {
        XCTAssertEqual(SYBookSourceGrouping.splitGroups("A,B,C"), ["A", "B", "C"])
        XCTAssertEqual(SYBookSourceGrouping.splitGroups("A，B；C"), ["A", "B", "C"])
        XCTAssertEqual(SYBookSourceGrouping.splitGroups(" A ,  B "), ["A", "B"])
        XCTAssertEqual(SYBookSourceGrouping.splitGroups("A\nB\tC"), ["A", "B", "C"])
        XCTAssertEqual(SYBookSourceGrouping.splitGroups(nil), [])
        XCTAssertEqual(SYBookSourceGrouping.splitGroups(""), [])
        XCTAssertEqual(SYBookSourceGrouping.splitGroups("  "), [])
    }

    // MARK: 默认分组归属

    func testGroupNamesDefaultWhenEmpty() {
        let source = makeSource("无分组源", url: "https://a.com")
        XCTAssertEqual(SYBookSourceGrouping.groupNames(for: source), ["默认分组"])
    }

    func testGroupNamesMulti() {
        let source = makeSource("多组源", url: "https://b.com", group: "小说,轻小说")
        XCTAssertEqual(SYBookSourceGrouping.groupNames(for: source), ["小说", "轻小说"])
    }

    // MARK: 分组小节构造

    func testSectionsOrder() {
        let a = makeSource("A", url: "https://a.com", group: "小说")
        let b = makeSource("B", url: "https://b.com")            // 默认分组
        let c = makeSource("C", url: "https://c.com", group: "漫画")
        let d = makeSource("D", url: "https://d.com")

        let sections = SYBookSourceGrouping.sections(
            sources: [a, b, c, d],
            pinRecords: [:]
        )
        XCTAssertEqual(sections.map(\.name), ["漫画", "小说", "默认分组"], "普通分组按名称升序，随后默认分组")
        XCTAssertEqual(sections.first { $0.kind == .normal }?.sourceIDs, ["https://c.com"])
        XCTAssertEqual(sections.last?.name, "默认分组")
        XCTAssertEqual(sections.last?.sourceIDs, ["https://b.com", "https://d.com"])
    }

    func testSectionsWithPins() {
        let a = makeSource("A", url: "https://a.com", group: "小说")
        let b = makeSource("B", url: "https://b.com", group: "小说")
        let c = makeSource("C", url: "https://c.com", group: "漫画")

        let pins: [String: SYSourcePinRecord] = [
            "https://b.com": SYSourcePinRecord(position: .top, pinnedAt: Date()),
            "https://c.com": SYSourcePinRecord(position: .bottom, pinnedAt: Date()),
        ]
        let sections = SYBookSourceGrouping.sections(sources: [a, b, c], pinRecords: pins)

        XCTAssertEqual(sections.map(\.kind), [.pinnedTop, .normal, .pinnedBottom], "置顶 -> 普通 -> 置底")
        XCTAssertEqual(sections[0].sourceIDs, ["https://b.com"])
        XCTAssertEqual(sections[1].name, "小说")
        XCTAssertEqual(sections[1].sourceIDs, ["https://a.com"], "被置顶的 b 不应再出现在普通分组")
        XCTAssertEqual(sections[2].sourceIDs, ["https://c.com"])
    }

    func testSectionsMultiGroupSourceAppearsInEach() {
        let a = makeSource("A", url: "https://a.com", group: "小说,轻小说")
        let sections = SYBookSourceGrouping.sections(sources: [a], pinRecords: [:])
        XCTAssertEqual(sections.count, 2)
        XCTAssertEqual(sections.map(\.name), ["轻小说", "小说"], "分组按 zh_CN 拼音升序：轻(q) < 小(x)")
        XCTAssertTrue(sections.allSatisfy { $0.sourceIDs == ["https://a.com"] })
    }

    // MARK: 分组统计与域名

    func testGroupCounts() {
        let a = makeSource("A", url: "https://a.com", group: "小说")
        let b = makeSource("B", url: "https://b.com", group: "小说,漫画")
        let c = makeSource("C", url: "https://c.com", group: nil)
        let counts = SYBookSourceGrouping.groupCounts(sources: [a, b, c])
        XCTAssertEqual(counts.count, 2)
        XCTAssertEqual(counts[0].name, "小说")
        XCTAssertEqual(counts[0].count, 2)
        XCTAssertEqual(counts[1].name, "漫画")
        XCTAssertEqual(counts[1].count, 1)

        let excluded = SYBookSourceGrouping.groupCounts(sources: [a, b, c], excluding: "漫画")
        XCTAssertEqual(excluded.map(\.name), ["小说"])
    }

    func testDomain() {
        XCTAssertEqual(SYBookSourceGrouping.domain(of: "https://fanqienovel.com/page/1"), "fanqienovel.com")
        XCTAssertEqual(SYBookSourceGrouping.domain(of: "https://www.example.com"), "www.example.com")
        XCTAssertEqual(SYBookSourceGrouping.domain(of: "http://a.cn/x"), "a.cn")
        XCTAssertEqual(SYBookSourceGrouping.domain(of: ""), "")
        XCTAssertEqual(SYBookSourceGrouping.domain(of: " @js:xxx "), "")
    }

    // MARK: Legado 分组字段往返（导入自动落组）

    func testBookSourceGroupDecode() throws {
        let json = """
        {"bookSourceName":"示例","bookSourceUrl":"https://example.com","bookSourceGroup":"小说，轻小说"}
        """
        let sources = SYBookSourceStore.parse(json)
        XCTAssertEqual(sources.count, 1)
        XCTAssertEqual(sources.first?.bookSourceGroup, "小说，轻小说", "导入应保留 JSON 中的分组")
    }
}