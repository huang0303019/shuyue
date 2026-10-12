import Foundation
import JavaScriptCore

// MARK: - 登录界面模型（兼容 Legado loginUi）

/// loginUi 字段类型：Legado RowUi 的 type 全集（input 与 text 等价）。
enum SYLoginFieldType: String, Equatable {
    case text, input, password, select, checkbox
    case captcha, button, toggle, label, group

    /// 是否以密文输入框渲染。
    var isSecure: Bool { self == .password }
}

/// 登录表单中的单个字段。
struct SYLoginField: Identifiable, Equatable {
    let name: String
    let type: SYLoginFieldType
    /// 展示标签：优先 label / viewName（剥引号），缺省回退 name。
    let label: String
    /// select / toggle 的候选项（chars）。
    let options: [String]
    let defaultValue: String?
    /// button 字段的动作 JS（action）。
    let action: String?

    var id: String { name }
}

/// 对象形态 loginUi 的提交目标：`{"name","url","method","params"}`。
struct SYLoginUrlAction: Identifiable, Equatable {
    let name: String
    let url: String
    let method: String
    var id: String { "\(url)|\(name)" }
}

/// 解析后的登录界面：数组形态 title 为空、urls 为空（走书源 loginUrl）。
struct SYLoginUi: Equatable {
    let title: String?
    let fields: [SYLoginField]
    /// 对象形态的提交目标；空数组时登录请求使用书源 loginUrl。
    let urls: [SYLoginUrlAction]

    var hasFields: Bool { !fields.isEmpty }
}

/// 登录执行结果。
struct SYLoginResult: Sendable, Equatable {
    /// 是否登录成功（含 loginCheckJs 校验通过）。
    let success: Bool
    /// 面向用户的简体中文提示。
    let message: String
    /// 是否执行了 loginCheckJs 校验。
    let checked: Bool
}

// MARK: - 解析器

/// loginUi 解析器：兼容两种 Legado 形态——
/// a) 纯数组 `[{"name","type","label","viewName","chars","default","action"}, ...]`
/// b) 对象 `{"title","params":[...],"urls":[{"name","url","method","params"}]}`
/// 并容忍 JS 对象字面量（单引号、尾逗号）——先严格 JSON，失败后经 JavaScriptCore 归一化。
enum SYLoginUiParser {

    static func parse(_ raw: String?) -> SYLoginUi? {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // 对象形态（以 { 开头）。
        if trimmed.hasPrefix("{") {
            if let obj = jsonObject(trimmed) as? [String: Any] {
                return parseObject(obj)
            }
            return nil
        }

        // 数组形态。
        if trimmed.hasPrefix("[") {
            guard let array = jsonArray(trimmed) else { return nil }
            return SYLoginUi(title: nil, fields: array.compactMap { parseField($0) }, urls: [])
        }
        return nil
    }

    // MARK: 形态解析

    private static func parseObject(_ obj: [String: Any]) -> SYLoginUi? {
        let title = stringValue(obj["title"])
        var fields: [SYLoginField] = []
        if let params = obj["params"] as? [Any] {
            fields = params.compactMap { parseField($0) }
        }
        var urls: [SYLoginUrlAction] = []
        if let actions = obj["urls"] as? [Any] {
            for item in actions {
                guard let dict = item as? [String: Any] else { continue }
                guard let name = stringValue(dict["name"]), !name.isEmpty else { continue }
                guard let url = stringValue(dict["url"]), !url.isEmpty else { continue }
                let method = (stringValue(dict["method"]) ?? "POST").uppercased()
                urls.append(SYLoginUrlAction(name: name, url: url, method: method))
            }
        }
        return SYLoginUi(title: title, fields: fields, urls: urls)
    }

    private static func parseField(_ value: Any) -> SYLoginField? {
        guard let dict = value as? [String: Any] else { return nil }
        guard let name = stringValue(dict["name"]), !name.isEmpty else { return nil }
        let type = SYLoginFieldType(rawValue: stringValue(dict["type"]) ?? "") ?? .text
        return SYLoginField(
            name: name,
            type: type,
            label: displayLabel(dict),
            options: stringArray(dict["chars"]),
            defaultValue: stringValue(dict["default"]),
            action: stringValue(dict["action"])
        )
    }

    /// 展示标签：`label` 优先；其次 `viewName`（形如 `'文本'` 的单引号字面量剥引号）；
    /// 再退化为字段名。
    private static func displayLabel(_ dict: [String: Any]) -> String {
        if let label = stringValue(dict["label"]), !label.isEmpty { return label }
        if let viewName = stringValue(dict["viewName"]), !viewName.isEmpty {
            let t = viewName.trimmingCharacters(in: .whitespaces)
            if t.count >= 2, t.hasPrefix("'"), t.hasSuffix("'") {
                return String(t.dropFirst().dropLast())
            }
            return viewName
        }
        return stringValue(dict["name"]) ?? ""
    }

    // MARK: 容错 JSON

    private static func jsonArray(_ text: String) -> [[String: Any]]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = trimmed.data(using: .utf8),
           let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            return array
        }
        guard let normalized = normalizeJSLiteral(trimmed),
              let data = normalized.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return nil
        }
        return array
    }

    private static func jsonObject(_ text: String) -> [String: Any]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = trimmed.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return obj
        }
        guard let normalized = normalizeJSLiteral(trimmed),
              let data = normalized.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return obj
    }

    /// 把 JS 对象/数组字面量（单引号、尾逗号等）归一化为严格 JSON。
    private static func normalizeJSLiteral(_ literal: String) -> String? {
        guard let context = JSContext() else { return nil }
        context.exceptionHandler = { _, _ in }
        context.setObject(literal, forKeyedSubscript: "__legadoLiteral" as NSString)
        let script = "(function(){try{return JSON.stringify(eval('('+__legadoLiteral+')'));}catch(e){return '';}})()"
        guard let value = context.evaluateScript(script),
              value.isString,
              let result = value.toString(),
              !result.isEmpty, result != "undefined", result != "null" else {
            return nil
        }
        return result
    }

    // MARK: 值工具

    private static func stringArray(_ value: Any?) -> [String] {
        guard let array = value as? [Any] else { return [] }
        return array.compactMap { stringValue($0) }
    }

    private static func stringValue(_ value: Any?) -> String? {
        switch value {
        case let string as String: return string
        case let number as NSNumber: return number.stringValue
        case let boolean as Bool: return boolean ? "true" : "false"
        case let value?:
            return String(describing: value)
        case nil:
            return nil
        }
    }
}
