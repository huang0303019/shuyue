import XCTest
@testable import ShuYue

// MARK: - 深链解析离线校验（不依赖网络 / UI）

final class SYDeepLinkTests: XCTestCase {

    func testOpenSources() {
        XCTAssertEqual(SYDeepLinkParser.parse(URL(string: "shuyue://sources")!), .openSources)
        XCTAssertEqual(SYDeepLinkParser.parse(URL(string: "shuyue://sources?x=1")!), .openSources)
        XCTAssertEqual(SYDeepLinkParser.parse(URL(string: "shuyue:///sources")!), .openSources)
    }

    func testImportRemote() {
        let url = URL(string: "shuyue://import?url=https%3A%2F%2Fexample.com%2Ffeeds.json")!
        XCTAssertEqual(SYDeepLinkParser.parse(url), .importRemote("https://example.com/feeds.json"))
    }

    func testImportText() {
        let raw = "{\"bookSourceName\":\"测试\"}"
        let encoded = raw.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        let url = URL(string: "shuyue://import?text=\(encoded)")!
        XCTAssertEqual(SYDeepLinkParser.parse(url), .importText(raw))
    }

    func testImportPreferTextOverUrl() {
        let raw = "{\"bookSourceName\":\"a\"}"
        let encoded = raw.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        let url = URL(string: "shuyue://import?text=\(encoded)&url=https%3A%2F%2Fexample.com")!
        XCTAssertEqual(SYDeepLinkParser.parse(url), .importText(raw))
    }

    func testImportWithoutParamsReturnsNil() {
        XCTAssertNil(SYDeepLinkParser.parse(URL(string: "shuyue://import")!))
        XCTAssertNil(SYDeepLinkParser.parse(URL(string: "shuyue://import?text=")!))
        XCTAssertNil(SYDeepLinkParser.parse(URL(string: "shuyue://import?url=")!))
    }

    func testUnknownSchemeOrHostReturnsNil() {
        XCTAssertNil(SYDeepLinkParser.parse(URL(string: "https://sources")!))
        XCTAssertNil(SYDeepLinkParser.parse(URL(string: "shuyue://other")!))
        if let bare = URL(string: "shuyue://") {
            XCTAssertNil(SYDeepLinkParser.parse(bare))
        }
    }
}
