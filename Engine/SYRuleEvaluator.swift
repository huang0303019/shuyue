import Foundation

// MARK: - 规则求值（Legado 规则链子集）

/// 规则求值上下文：JSON 根 或 HTML 根。
struct SYRuleContext {
    var jsonRoot: Any?
    var htmlRoot: SYHTMLNode?
    var baseUrl: String?
    var js: SYJavaScriptContext?
    var fallbackText: String?
    /// 调试事件接收器；nil 时规则求值不产生任何调试开销。
    var debug: SYDebugSink?

    init(
        jsonRoot: Any? = nil,
        htmlRoot: SYHTMLNode? = nil,
        baseUrl: String? = nil,
        js: SYJavaScriptContext? = nil,
        fallbackText: String? = nil,
        debug: SYDebugSink? = nil
    ) {
        self.jsonRoot = jsonRoot
        self.htmlRoot = htmlRoot
        self.baseUrl = baseUrl
        self.js = js
        self.fallbackText = fallbackText
        self.debug = debug
    }
}

/// 规则链中间值。
enum SYRuleValue {
    case json(Any?)
    case string(String)
    case nodes([SYHTMLNode])
}

/// 规则求值器：支持 `<js>` / `@js:` / `$.` / `@json:` / `@css:` / `@xpath:` / `//` / `@regex:` / `@replace:` / `@text` / `@all` 等子集。
enum SYRuleEvaluator {

    /// 求值为字符串（字段规则入口，如书名/章节名/正文）。
    static func string(_ rule: String?, context: SYRuleContext) -> String? {
        guard let rule, !rule.isEmpty else { return nil }
        let value = chain(rule, context: context, current: nil)
        return finalize(value)
    }

    /// 求值为原始值（JSON 值/字符串/节点），不字符串化。用于 init 等需要保留对象结构的规则。
    static func raw(_ rule: String?, context: SYRuleContext) -> Any? {
        guard let rule, !rule.isEmpty else { return nil }
        let value = chain(rule, context: context, current: nil)
        switch value {
        case .json(let any): return any
        case .string(let s): return s
        case .nodes(let nodes): return nodes
        default: return nil
        }
    }

    /// 求值为列表（bookList / chapterList 入口）：返回节点或 JSON 值数组。
    static func list(_ rule: String?, context: SYRuleContext) -> [SYRuleValue] {
        guard let rule, !rule.isEmpty else { return [] }
        let value = chain(rule, context: context, current: nil)
        switch value {
        case .nodes(let nodes):
            return nodes.map { .nodes([$0]) }
        case .json(let any):
            if let arr = any as? [Any] {
                return arr.map { .json($0) }
            }
            if let wrapped = any, !(wrapped is NSNull) {
                return [.json(wrapped)]
            }
            return []
        case .string:
            return []
        case .none:
            return []
        }
    }

    // MARK: - 链式执行

    /// 拆分为子规则：`@` 为分隔符，`@@` 为字面 @；方括号（XPath 谓词）深度 > 0 或引号内的 `@` 不视为分隔符。
    private static func splitRule(_ rule: String) -> [String] {
        var parts: [String] = []
        var buf = ""
        var depth = 0
        var quote: Character?
        var i = rule.startIndex
        while i < rule.endIndex {
            let c = rule[i]
            let next = rule.index(after: i)
            if c == "@", depth == 0, quote == nil {
                if next < rule.endIndex, rule[next] == "@" {
                    buf.append("@")
                    i = rule.index(after: next)
                    continue
                }
                parts.append(buf)
                buf = ""
            } else {
                buf.append(c)
                if quote != nil {
                    if c == quote { quote = nil }
                } else if c == "'" || c == "\"" {
                    quote = c
                } else if c == "[" {
                    depth += 1
                } else if c == "]", depth > 0 {
                    depth -= 1
                }
            }
            i = next
        }
        parts.append(buf)
        return parts
    }

    /// 逐级执行 `@` 分隔的子规则。
    /// 开启调试时逐个上报规则拆解、子规则执行前后与最终结果事件。
    private static func chain(_ rule: String, context: SYRuleContext, current: SYRuleValue?) -> SYRuleValue? {
        let parts = splitRule(rule)
        guard let debug = context.debug else {
            var currentValue = current
            for part in parts {
                currentValue = apply(part, context: context, current: currentValue)
            }
            return currentValue
        }

        debug(.rulesParsed(rule: rule, segments: parts))
        let t0 = Date()
        var currentValue = current
        for (index, part) in parts.enumerated() {
            debug(.beforeExtract(index: index, mode: mode(for: part), rule: part))
            let after = apply(part, context: context, current: currentValue, index: index)
            emitResult(after, index: index, debug: debug)
            currentValue = after
        }
        emitFinal(currentValue, elapsedMs: Date().timeIntervalSince(t0) * 1000, debug: debug)
        return currentValue
    }

    private static func apply(_ part: String, context: SYRuleContext, current: SYRuleValue?, index: Int? = nil) -> SYRuleValue? {
        let sub = part.trimmingCharacters(in: .whitespaces)
        guard !sub.isEmpty else { return current }

        // `<js>...</js>` 整段脚本
        if sub.hasPrefix("<js>"), sub.hasSuffix("</js>") {
            let script = String(sub.dropFirst("<js>".count).dropLast("</js>".count))
            return applyJS(script, context: context, current: current, index: index)
        }
        // 显式前缀
        if sub.hasPrefix("js:") {
            return applyJS(String(sub.dropFirst("js:".count)), context: context, current: current, index: index)
        }
        if sub.hasPrefix("json:") {
            return applyJSONPath(String(sub.dropFirst("json:".count)), context: context, current: current)
        }
        if sub.hasPrefix("css:") {
            return applyCSS(String(sub.dropFirst("css:".count)), context: context, current: current)
        }
        if sub.hasPrefix("xpath:") {
            return applyXPath(String(sub.dropFirst("xpath:".count)), context: context, current: current)
        }
        if sub.hasPrefix("regex:") {
            return applyRegex(String(sub.dropFirst("regex:".count)), context: context, current: current, index: index)
        }
        if sub.hasPrefix("replace:") {
            return applyReplace(String(sub.dropFirst("replace:".count)), context: context, current: current, index: index)
        }
        // 子集外能力：返回原值，不阻断链
        if sub.hasPrefix("put:") || sub.hasPrefix("get:") || sub.hasPrefix("cookie:") || sub.hasPrefix("header:") {
            return current
        }
        // 容错：`@css:` 等整体带 @ 前缀
        if sub.hasPrefix("@") {
            return apply(String(sub.dropFirst()), context: context, current: current, index: index)
        }
        // JSONPath
        if sub == "$" || sub.hasPrefix("$.") || sub.hasPrefix("$[") || sub.hasPrefix("[") {
            return applyJSONPath(sub, context: context, current: current)
        }
        // XPath 快捷
        if sub.hasPrefix("//") || sub.hasPrefix("/") {
            return applyXPath(sub, context: context, current: current)
        }
        // 动词
        switch sub {
        case "text":
            return applyTextVerb(current: current)
        case "all":
            return applyAllVerb(current: current)
        case "html", "textNodes", "ownText":
            return applyTextVerb(current: current)
        case "trim", "strip":
            if case .string(let s) = current {
                return .string(s.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            return current
        default:
            break
        }
        // 属性获取：节点后跟属性名（如 `css:a@href`）。
        if case .nodes(let nodes) = current, let first = nodes.first, let attr = first.attributes[sub] {
            return .string(attr)
        }
        // 无前缀：形如 CSS 选择器则查询，否则视为固定文本。
        if looksLikeCSSSelector(sub), let root = htmlRoot(from: current) ?? context.htmlRoot {
            return .nodes(root.query(sub))
        }
        return .string(sub)
    }

    // MARK: - 各类型求值

    private static func applyTextVerb(current: SYRuleValue?) -> SYRuleValue? {
        switch current {
        case .nodes(let nodes):
            return .string(nodes.first?.fullText ?? "")
        case .json(let any):
            return .string(SYJSONPath.displayString(any) ?? "")
        default:
            return current
        }
    }

    private static func applyAllVerb(current: SYRuleValue?) -> SYRuleValue? {
        switch current {
        case .nodes(let nodes):
            return .string(nodes.compactMap { $0.fullText }.joined(separator: "\n"))
        case .json(let any):
            if let arr = any as? [Any] {
                return .string(arr.compactMap { SYJSONPath.displayString($0) }.joined(separator: "\n"))
            }
            return .string(SYJSONPath.displayString(any) ?? "")
        default:
            return current
        }
    }

    private static func applyJSONPath(_ path: String, context: SYRuleContext, current: SYRuleValue?) -> SYRuleValue? {
        var target: Any?
        switch current {
        case .json(let v):
            target = v
        case .string(let s):
            if let data = s.data(using: .utf8) {
                target = try? JSONSerialization.jsonObject(with: data)
            }
        default:
            target = context.jsonRoot
        }
        guard let root = target else { return .json(nil) }
        return .json(SYJSONPath.evaluate(path: path, root: root))
    }

    private static func applyJS(_ script: String, context: SYRuleContext, current: SYRuleValue?, index: Int? = nil) -> SYRuleValue? {
        guard let js = context.js else { return current }
        let resultValue: Any?
        switch current {
        case .json(let v): resultValue = v
        case .string(let s): resultValue = s
        case .nodes(let nodes): resultValue = nodes.first?.fullText
        default: resultValue = context.fallbackText
        }
        do {
            let out = try js.evaluate(script, result: resultValue, baseUrl: context.baseUrl)
            let display = SYJSONPath.displayString(out) ?? ""
            if let index, let debug = context.debug {
                debug(.jsExecuted(index: index, script: script, result: display))
            }
            return .json(out)
        } catch {
            if let index, let debug = context.debug {
                debug(.error(step: "JS 执行", message: "子规则 #\(index) 执行失败：\(error.localizedDescription)"))
            }
            return .json(nil)
        }
    }

    private static func applyCSS(_ selector: String, context: SYRuleContext, current: SYRuleValue?) -> SYRuleValue? {
        let root = htmlRoot(from: current) ?? context.htmlRoot
        guard let root else { return .nodes([]) }
        return .nodes(root.query(selector))
    }

    private static func applyXPath(_ expr: String, context: SYRuleContext, current: SYRuleValue?) -> SYRuleValue? {
        let root = htmlRoot(from: current) ?? context.htmlRoot
        guard let root else { return .nodes([]) }
        if expr.hasSuffix("/text()") || expr.range(of: "/@", options: .backwards) != nil {
            if let s = SYXPath.evaluateString(expr, root: root) {
                return .string(s)
            }
            return .nodes([])
        }
        return .nodes(SYXPath.evaluate(expr, root: root))
    }

    private static func applyRegex(_ spec: String, context: SYRuleContext, current: SYRuleValue?, index: Int? = nil) -> SYRuleValue? {
        guard let s = stringValue(current), !spec.isEmpty else { return current }
        var pattern = spec
        var group = 1
        let parts = spec.components(separatedBy: "###")
        if parts.count >= 2 {
            pattern = parts[0]
            group = Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? 1
        }
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return current }
        let ns = NSRange(s.startIndex..<s.endIndex, in: s)
        guard let match = regex.firstMatch(in: s, options: [], range: ns) else { return current }
        var result = current
        if group == 0 {
            if let r = Range(match.range, in: s) { result = .string(String(s[r])) }
        } else if match.numberOfRanges > group, let r = Range(match.range(at: group), in: s) {
            result = .string(String(s[r]))
        } else if let r = Range(match.range(at: 0), in: s) {
            result = .string(String(s[r]))
        }
        if let index, let debug = context.debug {
            let before = s.prefix(200)
            let after = stringValue(result)?.prefix(200) ?? ""
            debug(.regexApplied(index: index, pattern: pattern, replacement: "组\(group)", before: String(before), after: String(after)))
        }
        return result
    }

    private static func applyReplace(_ spec: String, context: SYRuleContext, current: SYRuleValue?, index: Int? = nil) -> SYRuleValue? {
        guard let s = stringValue(current), !spec.isEmpty else { return current }
        let parts = spec.components(separatedBy: "||")
        guard parts.count >= 2 else { return current }
        let old = parts[0]
        let newValue = parts.dropFirst().joined(separator: "||")
        let result: SYRuleValue
        if let regex = try? NSRegularExpression(pattern: old) {
            let ns = NSRange(s.startIndex..<s.endIndex, in: s)
            let out = regex.stringByReplacingMatches(in: s, options: [], range: ns, withTemplate: newValue)
            result = .string(out)
        } else {
            result = .string(s.replacingOccurrences(of: old, with: newValue))
        }
        if let index, let debug = context.debug {
            let before = s.prefix(200)
            let after = stringValue(result)?.prefix(200) ?? ""
            debug(.regexApplied(index: index, pattern: old, replacement: newValue, before: String(before), after: String(after)))
        }
        return result
    }

    // MARK: - 辅助

    /// 子规则类型标签（调试日志展示用）。
    private static func mode(for part: String) -> String {
        let sub = part.trimmingCharacters(in: .whitespaces)
        if sub.hasPrefix("<js>") || sub.hasPrefix("js:") { return "js" }
        if sub.hasPrefix("json:") { return "json" }
        if sub.hasPrefix("css:") { return "css" }
        if sub.hasPrefix("xpath:") { return "xpath" }
        if sub.hasPrefix("regex:") { return "regex" }
        if sub.hasPrefix("replace:") { return "replace" }
        if sub.hasPrefix("@") { return "verb" }
        if sub == "$" || sub.hasPrefix("$.") || sub.hasPrefix("$[") || sub.hasPrefix("[") { return "json" }
        if sub.hasPrefix("//") || sub.hasPrefix("/") { return "xpath" }
        switch sub {
        case "text", "all", "html", "textNodes", "ownText", "trim", "strip": return "verb"
        default: break
        }
        return "default"
    }

    /// 子规则执行后的值/列表结果事件。
    private static func emitResult(_ value: SYRuleValue?, index: Int, debug: SYDebugSink) {
        switch value {
        case .nodes(let nodes) where nodes.count > 1:
            debug(.afterExtractList(index: index, count: nodes.count, items: nodes.prefix(10).map { $0.fullText }))
        case .nodes(let nodes):
            debug(.afterExtractValue(index: index, result: nodes.first?.fullText ?? ""))
        case .json(let any):
            debug(.afterExtractValue(index: index, result: any == nil ? "" : (SYJSONPath.displayString(any) ?? "")))
        case .string(let s):
            debug(.afterExtractValue(index: index, result: s))
        case .none:
            debug(.afterExtractValue(index: index, result: ""))
        }
    }

    /// 整条规则链求值完成事件。
    private static func emitFinal(_ value: SYRuleValue?, elapsedMs: Double, debug: SYDebugSink) {
        switch value {
        case .nodes(let nodes) where nodes.count > 1:
            debug(.finalResultList(values: nodes.prefix(20).map { $0.fullText }, elapsedMs: elapsedMs))
        case .nodes(let nodes):
            debug(.finalResult(value: nodes.first?.fullText ?? "", elapsedMs: elapsedMs))
        case .json(let any):
            if let arr = any as? [Any] {
                debug(.finalResultList(values: arr.prefix(20).map { SYJSONPath.displayString($0) ?? "" }, elapsedMs: elapsedMs))
            } else {
                debug(.finalResult(value: any == nil ? "" : (SYJSONPath.displayString(any) ?? ""), elapsedMs: elapsedMs))
            }
        case .string(let s):
            debug(.finalResult(value: s, elapsedMs: elapsedMs))
        case .none:
            debug(.finalResult(value: "", elapsedMs: elapsedMs))
        }
    }

    private static let knownTags: Set<String> = [
        "a", "abbr", "article", "aside", "b", "body", "br", "button", "div", "em",
        "figcaption", "figure", "footer", "form", "h1", "h2", "h3", "h4", "h5", "h6",
        "head", "header", "html", "i", "img", "input", "label", "li", "main", "nav",
        "ol", "p", "pre", "script", "section", "select", "small", "span", "strong",
        "style", "table", "tbody", "td", "textarea", "th", "thead", "title", "tr", "ul"
    ]

    private static func looksLikeCSSSelector(_ s: String) -> Bool {
        guard let first = s.first else { return false }
        if first == "." || first == "#" || first == "[" || first == "*" { return true }
        if s.contains(" ") || s.contains(">") { return true }
        var head = ""
        for ch in s {
            if ch == "." || ch == "#" || ch == "[" { break }
            head.append(ch)
        }
        let tag = head.lowercased()
        return s.count <= 40 && knownTags.contains(tag)
    }

    private static func htmlRoot(from current: SYRuleValue?) -> SYHTMLNode? {
        guard case .nodes(let nodes) = current, let first = nodes.first else { return nil }
        return first
    }

private static func stringValue(_ value: SYRuleValue?) -> String? {
        switch value {
        case .string(let s): return s
        case .json(let any): return SYJSONPath.displayString(any)
        case .nodes(let nodes): return nodes.first?.fullText
        case .none: return nil
        }
    }

    /// 规则最终输出：字符串。
    static func finalize(_ value: SYRuleValue?) -> String? {
        guard let value else { return nil }
        switch value {
        case .string(let s):
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        case .json(let any):
            guard let any else { return nil }
            let s = SYJSONPath.displayString(any) ?? ""
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        case .nodes(let nodes):
            guard let first = nodes.first else { return nil }
            let s = first.fullText
            return s.isEmpty ? nil : s
        }
    }
}
