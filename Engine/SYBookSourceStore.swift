import Foundation

// MARK: - 书源存储（导入 / 导出 / 校验）

enum SYBookSourceStore {

    /// 解析书源文本：支持单个对象或对象数组。
    static func parse(_ text: String) -> [SYBookSource] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8) else { return [] }
        guard let obj = try? JSONSerialization.jsonObject(with: data) else { return [] }
        var out: [SYBookSource] = []
        if let arr = obj as? [Any] {
            for item in arr {
                if let d = try? JSONSerialization.data(withJSONObject: item),
                   let source = SYBookSource(jsonData: d) {
                    out.append(source)
                }
            }
        } else if let source = SYBookSource(jsonData: data) {
            out.append(source)
        }
        return out
    }

    /// 导出书源数组为 JSON 文本。
    static func serialize(_ sources: [SYBookSource]) -> String {
        let list = sources.compactMap { source -> Any? in
            guard let data = source.jsonData() else { return nil }
            return try? JSONSerialization.jsonObject(with: data)
        }
        guard let data = try? JSONSerialization.data(withJSONObject: list, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return text
    }

    /// 基本规则校验：返回问题列表（空表示通过）。
    static func validate(_ source: SYBookSource) -> [String] {
        var issues: [String] = []
        if source.bookSourceName.isEmpty {
            issues.append("缺少书源名称 bookSourceName")
        }
        if source.bookSourceUrl.isEmpty {
            issues.append("缺少书源地址 bookSourceUrl")
        }
        let hasSearch = !(source.searchUrl?.isEmpty ?? true) || !(source.ruleSearch.bookList?.isEmpty ?? true)
        if !hasSearch {
            issues.append("缺少搜索入口 searchUrl 或 ruleSearch.bookList")
        }
        if source.ruleToc.chapterList?.isEmpty ?? true {
            issues.append("缺少目录规则 ruleToc.chapterList")
        }
        if source.ruleContent.content?.isEmpty ?? true {
            issues.append("缺少正文规则 ruleContent.content")
        }
        return issues
    }
}