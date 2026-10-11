import Foundation

// MARK: - XPath 子集求值（自研，配合 SYHTMLNode）

/// 轻量 XPath 支持：
/// - 路径：`/html/body/div`、`//div`、`//div[@class='x']/a[1]`
/// - 步骤谓词：`[@attr]`、`[@attr='val']`、`[@attr="val"]`、`[n]`（1 起）、`[contains(@attr,'val')]`
/// - 文本/属性结尾：`//div/text()`、`//a/@href`
enum SYXPath {

    /// 返回命中节点（不含结尾 `text()` / `@attr` 的字符串化）。
    static func evaluate(_ expression: String, root: SYHTMLNode) -> [SYHTMLNode] {
        let steps = parse(expression)
        guard !steps.isEmpty else { return [root] }
        var current: [SYHTMLNode] = [root]
        for step in steps {
            var next: [SYHTMLNode] = []
            for node in current {
                next.append(contentsOf: match(step: step, from: node))
            }
            current = next
            if current.isEmpty { return [] }
        }
        return current
    }

    /// 求值为字符串：结尾 `text()` 或 `@attr` 时取文本/属性，否则取首个命中节点文本。
    static func evaluateString(_ expression: String, root: SYHTMLNode) -> String? {
        let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix("/text()") {
            let path = String(trimmed.dropLast("/text()".count))
            return evaluate(path, root: root).first?.fullText
        }
        if let range = trimmed.range(of: "/@", options: .backwards) {
            let path = String(trimmed[..<range.lowerBound])
            let attr = String(trimmed[range.upperBound...])
            return evaluate(path, root: root).first?.attributes[attr]
        }
        return evaluate(trimmed, root: root).first?.fullText
    }

    // MARK: - 解析

    private struct Step {
        var key: String = "*"
        var allDescendants: Bool = false
        var predicates: [Predicate] = []
    }

    private enum Predicate {
        case attr(String)
        case attrValue(String, String)
        case index(Int)
        case contains(String, String)
    }

    private static func parse(_ expression: String) -> [Step] {
        let s = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        var steps: [Step] = []
        var i = s.startIndex
        var first = true
        while i < s.endIndex {
            var all = false
            if s[i] == "/" {
                i = s.index(after: i)
                if i < s.endIndex, s[i] == "/" {
                    all = true
                    i = s.index(after: i)
                }
            }
            var seg = ""
            while i < s.endIndex, s[i] != "/" {
                seg.append(s[i])
                i = s.index(after: i)
            }
            if seg.isEmpty { continue }
            steps.append(parseSegment(seg, allDescendants: all && !first))
            first = false
        }
        return steps
    }

    private static func parseSegment(_ seg: String, allDescendants: Bool) -> Step {
        var key = ""
        var predicates: [Predicate] = []
        var i = seg.startIndex
        while i < seg.endIndex, seg[i] != "[" {
            key.append(seg[i])
            i = seg.index(after: i)
        }
        if key.isEmpty { key = "*" }
        while i < seg.endIndex {
            guard seg[i] == "[" else { break }
            i = seg.index(after: i)
            var inner = ""
            while i < seg.endIndex, seg[i] != "]" {
                inner.append(seg[i])
                i = seg.index(after: i)
            }
            if i < seg.endIndex { i = seg.index(after: i) }
            if let p = parsePredicate(inner) {
                predicates.append(p)
            }
        }
        return Step(key: key, allDescendants: allDescendants, predicates: predicates)
    }

    private static func parsePredicate(_ inner: String) -> Predicate? {
        let t = inner.trimmingCharacters(in: .whitespaces)
        if let n = Int(t) { return .index(n) }
        if t.hasPrefix("contains("), t.hasSuffix(")") {
            let body = String(t.dropFirst("contains(".count).dropLast())
            if let comma = body.firstIndex(of: ",") {
                let lhs = body[..<comma].trimmingCharacters(in: .whitespaces)
                var rhs = body[comma...].dropFirst().trimmingCharacters(in: .whitespaces)
                if rhs.count >= 2, (rhs.first == "'" || rhs.first == "\"") {
                    rhs.removeFirst(); rhs.removeLast()
                }
                if lhs.hasPrefix("@") {
                    return .contains(String(lhs.dropFirst()), String(rhs))
                }
            }
            return nil
        }
        if t.hasPrefix("@") {
            var body = String(t.dropFirst())
            if let eq = body.firstIndex(of: "=") {
                let name = String(body[..<eq]).trimmingCharacters(in: .whitespaces)
                var val = String(body[body.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
                if val.count >= 2, (val.first == "'" || val.first == "\"") {
                    val.removeFirst(); val.removeLast()
                }
                return .attrValue(name, val)
            }
            return .attr(body.trimmingCharacters(in: .whitespaces))
        }
        return nil
    }

    // MARK: - 匹配

    private static func match(step: Step, from node: SYHTMLNode) -> [SYHTMLNode] {
        var candidates = step.allDescendants ? allDescendants(of: node) : node.children
        guard !candidates.isEmpty else { return [] }
        if step.key != "*" {
            candidates = candidates.filter { $0.tag == step.key }
        }
        for pred in step.predicates {
            switch pred {
            case .index(let n):
                if candidates.indices.contains(n - 1) {
                    candidates = [candidates[n - 1]]
                } else {
                    return []
                }
            case .attr(let name):
                candidates = candidates.filter { $0.attributes[name] != nil }
            case .attrValue(let name, let value):
                candidates = candidates.filter { $0.attributes[name] == value }
            case .contains(let name, let value):
                candidates = candidates.filter { ($0.attributes[name] ?? "").contains(value) }
            }
        }
        return candidates
    }

    private static func allDescendants(of node: SYHTMLNode) -> [SYHTMLNode] {
        var out: [SYHTMLNode] = []
        for child in node.children {
            out.append(child)
            out.append(contentsOf: allDescendants(of: child))
        }
        return out
    }
}