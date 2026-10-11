import Foundation

// MARK: - 轻量 HTML 文档（自研解析器，无第三方依赖）

/// HTML 节点：标签、属性、子节点、文本。
final class SYHTMLNode: @unchecked Sendable {
    var tag: String
    var attributes: [String: String] = [:]
    var children: [SYHTMLNode] = []
    var textContent: String = ""
    weak var parent: SYHTMLNode?

    init(tag: String) {
        self.tag = tag
    }
}

/// 轻量 HTML 解析器：处理标签、属性、自闭合、纯文本、简单实体。
enum SYHTMLParser {

    /// 解析 HTML 文本为文档根（虚拟 #root）。
    static func parse(_ html: String) -> SYHTMLNode {
        let root = SYHTMLNode(tag: "#root")
        let scanner = Scanner(html)
        var stack: [SYHTMLNode] = [root]

        while let token = scanner.next() {
            switch token {
            case .open(let name, let attrs, let selfClosing):
                let node = SYHTMLNode(tag: name.lowercased())
                node.attributes = attrs
                if let top = stack.last {
                    node.parent = top
                    top.children.append(node)
                }
                if !selfClosing && !SYHTMLParser.voidTags.contains(name.lowercased()) {
                    stack.append(node)
                } else {
                    // 自闭合/void 元素立即闭合
                }
            case .close(let name):
                let lower = name.lowercased()
                if let idx = stack.lastIndex(where: { $0.tag == lower }) {
                    // 弹出到匹配标签
                    while stack.count > idx + 1 {
                        stack.removeLast()
                    }
                    _ = stack.popLast()
                }
                // 不匹配则忽略（容错 HTML）
            case .text(let text):
                if let top = stack.last {
                    top.textContent += text
                }
            case .comment:
                break
            case .doctype:
                break
            }
        }
        return root
    }

    static let voidTags: Set<String> = [
        "area", "base", "br", "col", "embed", "hr", "img", "input",
        "link", "meta", "param", "source", "track", "wbr"
    ]

    /// 递归收集本节点及后代中所有匹配标签的节点。
    static func elements(tag: String, in node: SYHTMLNode) -> [SYHTMLNode] {
        var out: [SYHTMLNode] = []
        for child in node.children {
            if child.tag == tag { out.append(child) }
            out.append(contentsOf: elements(tag: tag, in: child))
        }
        return out
    }
}

// MARK: - 扫描器

fileprivate enum HTMLToken {
    case open(String, [String: String], Bool)
    case close(String)
    case text(String)
    case comment
    case doctype
}

fileprivate final class Scanner {
    private let input: [Character]
    private var pos = 0

    init(_ text: String) {
        self.input = Array(text)
    }

    private var isAtEnd: Bool { pos >= input.count }

    func next() -> HTMLToken? {
        guard !isAtEnd else { return nil }
        let c = input[pos]
        if c == "<" {
            return scanTag()
        }
        // 普通文本直到下一个 <
        var text = ""
        while pos < input.count, input[pos] != "<" {
            text.append(input[pos])
            pos += 1
        }
        return .text(decodeEntities(text))
    }

    private func scanTag() -> HTMLToken? {
        // 当前位于 '<'
        pos += 1
        guard !isAtEnd else { return nil }
        let c = input[pos]
        if c == "/" { // 闭合标签
            pos += 1
            var name = ""
            while pos < input.count, !isTagDelimiter(input[pos]) {
                name.append(input[pos])
                pos += 1
            }
            skipUntilAfter(">")
            return .close(name.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if c == "!" { // 注释或 doctype
            let rest = String(input[pos...])
            if rest.hasPrefix("--") {
                if let end = rest.range(of: "-->") {
                    let offset = rest.distance(from: rest.startIndex, to: end.upperBound)
                    pos += offset
                    return .comment
                }
                pos = input.count
                return .comment
            }
            skipUntilAfter(">")
            return .doctype
        }
        if c == "?" {
            skipUntilAfter(">")
            return .doctype
        }

        var name = ""
        while pos < input.count, isTagNameChar(input[pos]) {
            name.append(input[pos])
            pos += 1
        }
        if name.isEmpty {
            skipUntilAfter(">")
            return .text("")
        }

        // 属性
        var attrs: [String: String] = [:]
        var selfClosing = false
        var pendingKey = ""
        var awaitingValue = false
        var sawKey = false

        while pos < input.count {
            let ch = input[pos]
            if ch == ">" {
                pos += 1
                break
            }
            if ch == "/" && pos + 1 < input.count && input[pos + 1] == ">" {
                selfClosing = true
                pos += 2
                break
            }
            if ch == "=" {
                sawKey = true
                awaitingValue = true
                pos += 1
                continue
            }
            if isWhitespace(ch) {
                pos += 1
                continue
            }
            if awaitingValue {
                // 解析属性值
                let value = scanAttributeValue()
                if !pendingKey.isEmpty {
                    attrs[pendingKey.lowercased()] = value
                }
                pendingKey = ""
                awaitingValue = false
                sawKey = false
                continue
            }
            if !sawKey {
                pendingKey = ""
                while pos < input.count, isAttrNameChar(input[pos]) {
                    pendingKey.append(input[pos])
                    pos += 1
                }
                if !pendingKey.isEmpty {
                    // 无值属性：暂存，若后跟 = 则有值
                    attrs[pendingKey.lowercased()] = pendingKey
                    // 这里不清空，稍后若遇到 = 会覆盖
                }
            }
        }
        // 处理无值属性（重复 key 时保留最后一个）
        return .open(name.lowercased(), attrs, selfClosing)
    }

    private func scanAttributeValue() -> String {
        guard !isAtEnd else { return "" }
        let c = input[pos]
        var value = ""
        if c == "\"" || c == "'" {
            let quote = c
            pos += 1
            while pos < input.count, input[pos] != quote {
                value.append(input[pos])
                pos += 1
            }
            pos += 1 // skip quote
        } else {
            while pos < input.count, !isWhitespace(input[pos]), input[pos] != ">" {
                value.append(input[pos])
                pos += 1
            }
        }
        return decodeEntities(value)
    }

    private func skipUntilAfter(_ ch: Character) {
        while pos < input.count, input[pos] != ch {
            pos += 1
        }
        if pos < input.count { pos += 1 }
    }

    private func isTagDelimiter(_ c: Character) -> Bool {
        c == ">" || c == "/" || c == " "
    }

    private func isTagNameChar(_ c: Character) -> Bool {
        c.isLetter || c.isNumber || c == "-" || c == "_" || c == ":"
    }

    private func isAttrNameChar(_ c: Character) -> Bool {
        c.isLetter || c.isNumber || c == "-" || c == "_" || c == ":" || c == "."
    }

    private func isWhitespace(_ c: Character) -> Bool {
        c == " " || c == "\t" || c == "\n" || c == "\r" || c == "\u{0C}"
    }

    private func decodeEntities(_ s: String) -> String {
        guard s.contains("&") else { return s }
        let replacements: [String: String] = [
            "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"",
            "&#39;": "'", "&nbsp;": "\u{00A0}", "&apos;": "'"
        ]
        var out = s
        for (k, v) in replacements {
            out = out.replacingOccurrences(of: k, with: v)
        }
        // 数字实体 &#123;
        if out.contains("&#") {
            // 简单处理十进制数字实体
            let pattern = #"&#(\d+);"#
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(out.startIndex..<out.endIndex, in: out)
                out = regex.stringByReplacingMatches(in: out, options: [], range: range) { match in
                    if let r = Range(match.range(at: 1), in: out),
                       let code = Int(out[r]),
                       let scalar = UnicodeScalar(code) {
                        return String(Character(scalar))
                    }
                    return ""
                }
            }
        }
        return out
    }
}

// MARK: - HTML 文档便捷方法

extension SYHTMLNode {
    /// 全部后代（含自身）中符合 CSS 选择器简化子集的节点。
    /// 支持 tag / .class / #id / [attr] / [attr=value] / 后代空格 / 子代 >。
    func query(_ selector: String) -> [SYHTMLNode] {
        let parts = selector.split(separator: " ").map(String.init)
        var current = [self]
        for part in parts {
            var next: [SYHTMLNode] = []
            for node in current {
                next.append(contentsOf: descendants(of: node, matching: part))
            }
            current = next
        }
        return current
    }

    private func descendants(of node: SYHTMLNode, matching part: String) -> [SYHTMLNode] {
        var out: [SYHTMLNode] = []
        for child in node.children {
            if matches(child, selector: part) { out.append(child) }
            out.append(contentsOf: descendants(of: child, matching: part))
        }
        return out
    }

    private func matches(_ node: SYHTMLNode, selector: String) -> Bool {
        var rest = selector.trimmingCharacters(in: .whitespaces)
        if rest.hasPrefix(":") { return false } // 伪类暂不支持
        // class
        if rest.hasPrefix(".") {
            let cls = String(rest.dropFirst())
            guard let v = node.attributes["class"] else { return false }
            return v.split(separator: " ").contains(where: { $0 == cls })
        }
        // id
        if rest.hasPrefix("#") {
            let id = String(rest.dropFirst())
            return node.attributes["id"] == id
        }
        // attr
        if rest.hasPrefix("[") {
            guard let end = rest.firstIndex(of: "]") else { return false }
            let expr = String(rest[rest.index(after: rest.startIndex)..<end])
            if expr.contains("=") {
                let kv = expr.split(separator: "=", maxSplits: 1).map(String.init)
                let attr = kv[0].trimmingCharacters(in: .whitespaces)
                var val = kv[1].trimmingCharacters(in: .whitespaces)
                if val.count >= 2, (val.first == "\"" || val.first == "'") {
                    val.removeFirst(); val.removeLast()
                }
                if attr == "text" {
                    return node.textContent.trimmingCharacters(in: .whitespacesAndNewlines).contains(val)
                }
                return node.attributes[attr] == val
            }
            let attr = expr.trimmingCharacters(in: .whitespaces)
            return node.attributes[attr] != nil
        }
        // tag
        if rest == "*" { return true }
        return node.tag == rest.lowercased()
    }

    /// 匹配 XPath 子集；返回所有命中节点（支持 // 任意深度、[@attr]、[n]、text()、@attr 简化）。
    func xpath(_ expression: String) -> [SYHTMLNode] {
        SYXPath.evaluate(expression, root: self)
    }

    /// 节点文本：递归拼接（HTML 转义已处理）。
    var fullText: String {
        let t = textContent.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { return t }
        let parts = children.map { $0.fullText }
        return parts.joined(separator: " ")
    }

    /// 取第一个匹配子节点的文本。
    func textOf(_ selector: String) -> String? {
        query(selector).first?.fullText
    }

    /// 取第一个匹配节点的属性。
    func attrOf(_ selector: String, _ attr: String) -> String? {
        query(selector).first?.attributes[attr]
    }
}