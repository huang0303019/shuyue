import Foundation

// MARK: - JSONPath 求值（Legado @json / $. 规则）

/// 支持 `$.a.b[0].c`、`$['a']['b']`、`$[0]` 等常用子集的 JSONPath 求值器。
enum SYJSONPath {

    /// 在任意 JSON 值上执行路径。
    /// - Parameters:
    ///   - path: 形如 `$.store.book[0].title` / `store.book[0].title` / `[0]` / `$`
    ///   - root: JSONSerialization 解出的 Any
    /// - Returns: 命中值；未命中返回 nil。
    static func evaluate(path: String, root: Any?) -> Any? {
        guard let root else { return nil }
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        var p = trimmed
        if p.hasPrefix("$") {
            p.removeFirst()
        }
        if p.isEmpty { return root }

        // 逐个 token：`.name` 或 `['name']` / `[0]` / `[0:2]` / `[*]`
        var current: Any? = root
        var tokens = tokenize(p)
        guard !tokens.isEmpty else { return root }

        for tok in tokens {
            guard let cur = current else { return nil }
            switch tok {
            case .key(let name):
                if let dict = cur as? [String: Any] {
                    current = dict[name]
                } else if let dict = cur as? [AnyHashable: Any], let n = name as AnyHashable? {
                    current = dict[n]
                } else {
                    return nil
                }
            case .index(let idx):
                if let arr = cur as? [Any], arr.indices.contains(idx) {
                    current = arr[idx]
                } else {
                    return nil
                }
            case .star:
                if let arr = cur as? [Any] {
                    current = arr
                } else {
                    return nil
                }
            case .slice(let from, let to):
                guard let arr = cur as? [Any] else { return nil }
                let lo = from ?? 0
                let hi = to ?? arr.count
                current = Array(arr[max(0, lo)..<min(arr.count, hi)])
            }
        }
        return current
    }

    private enum Token {
        case key(String)
        case index(Int)
        case star
        case slice(Int?, Int?)
    }

    private static func tokenize(_ path: String) -> [Token] {
        var tokens: [Token] = []
        var i = path.startIndex
        while i < path.endIndex {
            let c = path[i]
            if c == "." {
                i = path.index(after: i)
                // 读取 key 直到 . 或 [
                var key = ""
                while i < path.endIndex {
                    let ch = path[i]
                    if ch == "." || ch == "[" || ch == "]" { break }
                    key.append(ch)
                    i = path.index(after: i)
                }
                if !key.isEmpty { tokens.append(.key(key)) }
                // 注意：`.*` 已是 star；`[` 会留在下一次循环处理
                if i < path.endIndex, path[i] == "." {
                    // 循环继续
                }
            } else if c == "[" {
                i = path.index(after: i)
                var inner = ""
                while i < path.endIndex, path[i] != "]" {
                    inner.append(path[i])
                    i = path.index(after: i)
                }
                if i < path.endIndex { i = path.index(after: i) } // skip ]
                inner = inner.trimmingCharacters(in: .whitespacesAndNewlines)
                if inner == "*" {
                    tokens.append(.star)
                } else if inner.hasPrefix("'") || inner.hasPrefix("\"") {
                    let quote = inner.first!
                    var key = inner
                    key.removeFirst()
                    if key.last == quote { key.removeLast() }
                    tokens.append(.key(key))
                } else if inner.contains(":") {
                    let parts = inner.split(separator: ":").map { Int($0.trimmingCharacters(in: .whitespaces)) }
                    tokens.append(.slice(parts.count > 0 ? parts[0] : nil,
                                         parts.count > 1 ? parts[1] : nil))
                } else if let idx = Int(inner) {
                    tokens.append(.index(idx))
                } else {
                    tokens.append(.key(inner))
                }
            } else if c == "*" {
                tokens.append(.star)
                i = path.index(after: i)
            } else if c == " " || c == "\t" || c == "\n" {
                i = path.index(after: i)
            } else {
                // 无点开始，直接读 key 直到 . 或 [
                var key = ""
                while i < path.endIndex, path[i] != ".", path[i] != "[" {
                    key.append(path[i])
                    i = path.index(after: i)
                }
                tokens.append(.key(key))
            }
        }
        return tokens
    }

    /// 将任意值转为便于展示的字符串。
    static func displayString(_ value: Any?) -> String? {
        guard let value else { return nil }
        if let s = value as? String { return s }
        if let n = value as? NSNumber { return n.stringValue }
        if let b = value as? Bool { return b ? "true" : "false" }
        if let arr = value as? [Any] {
            let items = arr.prefix(20).compactMap { displayString($0) }
            return items.joined(separator: "\n")
        }
        if let dict = value as? [String: Any] {
            // 取 text 字段优先（网页 JSON 常见）
            if let t = dict["text"] as? String { return t }
            if let t = dict["textContent"] as? String { return t }
            return nil
        }
        return String(describing: value)
    }

    /// 判断路径是否合法（无显式校验，仅做快速提示用）。
    static func looksLikePath(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return t == "$" || t.hasPrefix("$.") || t.hasPrefix("$[") || t.hasPrefix("[")
    }
}