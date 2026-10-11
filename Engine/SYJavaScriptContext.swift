import Foundation
import JavaScriptCore

// MARK: - JavaScript 执行上下文（JavaScriptCore，无第三方依赖）

/// 封装 JSContext：加载书源 jsLib 并提供 Legado 常见内建函数兜底。
/// 同一引擎实例内串行访问（由 SYLegadoEngine actor 保证）。
final class SYJavaScriptContext: @unchecked Sendable {
    private let context: JSContext
    private let lock = NSLock()
    private var lastException: String?

    init?(jsLib: String?) {
        guard let ctx = JSContext() else { return nil }
        self.context = ctx

        ctx.exceptionHandler = { [weak self] _, exception in
            self?.lastException = exception?.toString() ?? "unknown exception"
        }
        // 部分 jsLib 依赖 window / console 全局对象。
        ctx.evaluateScript("""
            var window = this;
            var console = { log: function(){}, info: function(){}, warn: function(){}, error: function(){} };
        """)
        SYJavaScriptContext.injectBuiltins(into: ctx)

        if let jsLib, !jsLib.isEmpty {
            _ = ctx.evaluateScript(jsLib)
        }
    }

    /// 求值脚本/表达式。`result` 与 `baseUrl` 会注入全局变量。
    func evaluate(_ script: String, result: Any?, baseUrl: String?) throws -> Any? {
        lock.lock()
        defer { lock.unlock() }

        context.setObject(toJSValue(result), forKeyedSubscript: "result" as NSString)
        if let baseUrl {
            context.setObject(baseUrl as NSString, forKeyedSubscript: "baseUrl" as NSString)
        }
        lastException = nil
        let value = context.evaluateScript(script)
        if let exc = lastException {
            throw SYEngineError.jsError(exc)
        }
        return fromJS(value)
    }

    // MARK: - 内建函数兜底

    private static func injectBuiltins(into ctx: JSContext) {
        let absUrl: @convention(block) (String, String) -> String = { url, base in
            if url.hasPrefix("http://") || url.hasPrefix("https://") { return url }
            guard let baseURL = URL(string: base), let u = URL(string: url, relativeTo: baseURL) else {
                return url
            }
            return u.absoluteString
        }
        ctx.setObject(absUrl, forKeyedSubscript: "__sy_absUrl" as NSString)

        let decodePua: @convention(block) (String) -> String = { text in
            SYJavaScriptContext.decodePUA(text)
        }
        ctx.setObject(decodePua, forKeyedSubscript: "__sy_decodePua" as NSString)

        ctx.evaluateScript("""
            function absUrl(url, base) { return __sy_absUrl(url || '', base || ''); }
            function decodePua(s) { return __sy_decodePua(String(s || '')); }
            function wan(text) { return String(text || ''); }
            function htmlToText(html) {
                if (!html) return '';
                return String(html)
                    .replace(/<br\\s*\\/?>/gi, '\\n')
                    .replace(/<\\/(p|div|li|h[1-6])>/gi, '\\n')
                    .replace(/<[^>]+>/g, '')
                    .replace(/&nbsp;/g, ' ')
                    .replace(/&amp;/g, '&')
                    .replace(/&lt;/g, '<')
                    .replace(/&gt;/g, '>')
                    .replace(/&quot;/g, '"')
                    .replace(/&#39;/g, "'")
                    .replace(/\\n{3,}/g, '\\n\\n')
                    .trim();
            }
            function cleanForRead(text) { return String(text || '').trim(); }
            function formatComments(c) { return String(c || ''); }
            function fqMode(v) { return v; }
        """)
    }

    /// PUA 字符兜底：真实映射一般由书源 jsLib 提供；无映射时原样返回，避免破坏文本。
    static func decodePUA(_ text: String) -> String {
        text
    }

    // MARK: - 值桥接

    private func toJSValue(_ value: Any?) -> Any {
        guard let value else { return NSNull() }
        if let s = value as? String { return s as NSString }
        if let b = value as? Bool { return b as NSNumber }
        if let n = value as? NSNumber { return n }
        if let arr = value as? [Any] {
            return jsonObject(from: arr) ?? NSNull()
        }
        if let dict = value as? [String: Any] {
            return jsonObject(from: dict) ?? NSNull()
        }
        return String(describing: value) as NSString
    }

    private func jsonObject(from value: Any) -> Any? {
        guard let data = try? JSONSerialization.data(withJSONObject: value),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }
        return context.evaluateScript("(" + json + ")") ?? NSNull()
    }

    private func fromJS(_ value: JSValue?) -> Any? {
        guard let value else { return nil }
        if value.isUndefined || value.isNull { return nil }
        if value.isBoolean { return value.toBool() }
        if value.isNumber { return value.toDouble() }
        if value.isString { return value.toString() }
        if value.isObject || value.isArray {
            context.setObject(value, forKeyedSubscript: "__sy_tmp" as NSString)
            guard let json = context.evaluateScript("JSON.stringify(__sy_tmp)")?.toString(),
                  let data = json.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) else {
                return nil
            }
            return obj
        }
        return nil
    }
}