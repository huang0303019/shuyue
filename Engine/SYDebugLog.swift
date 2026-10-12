import Foundation

// MARK: - 规则调试日志模型

/// 调试事件级别：与面板配色一一对应。
enum SYDebugLevel: String, Sendable {
    case info
    case success
    case warning
    case error
    case pipeline   // 细粒度规则步骤
}

/// 单条调试日志（面板展示用）。
struct SYDebugLogEntry: Identifiable, Sendable {
    let id = UUID()
    let timestamp: Date
    let level: SYDebugLevel
    let step: String
    let summary: String
    var detail: String?

    init(level: SYDebugLevel, step: String, summary: String, detail: String? = nil) {
        self.timestamp = Date()
        self.level = level
        self.step = step
        self.summary = summary
        self.detail = detail
    }
}

/// 引擎链路上产生的结构化调试事件。
///
/// 事件流（单次规则求值）：contentSet → requestSent/responseReceived → rulesParsed
/// → [每个子规则: beforeExtract → (jsExecuted / regexApplied) → afterExtractValue/List]
/// → finalResult / finalResultList。
enum SYDebugEvent: Sendable {

    // MARK: 原始数据

    /// 响应文本进入引擎上下文。
    case contentSet(
        contentType: String,   // "HTML" / "JSON" / "文本"
        length: Int,
        preview: String,
        url: String
    )

    // MARK: 网络

    case requestSent(url: String, method: String, headers: [String: String])
    case responseReceived(url: String, statusCode: Int?, bytes: Int, preview: String, truncated: Bool)

    // MARK: 规则解析

    /// 规则串被拆分为子规则链。
    case rulesParsed(rule: String, segments: [String])

    /// 开始执行第 index 个子规则。
    case beforeExtract(index: Int, mode: String, rule: String)

    /// 子规则执行后的值结果。
    case afterExtractValue(index: Int, result: String)

    /// 子规则执行后的列表结果。
    case afterExtractList(index: Int, count: Int, items: [String])

    /// 正则提取/替换已应用。
    case regexApplied(index: Int, pattern: String, replacement: String, before: String, after: String)

    /// JS 子规则已执行。
    case jsExecuted(index: Int, script: String, result: String)

    // MARK: 最终结果

    /// 整条规则链求值完成（字符串/节点值）。
    case finalResult(value: String, elapsedMs: Double)

    /// 整条规则链求值完成（列表值）。
    case finalResultList(values: [String], elapsedMs: Double)

    // MARK: 错误

    case error(step: String, message: String)
}

/// 调试事件接收器。由调试引擎注入引擎链路；关闭时为 nil，不产生任何开销。
typealias SYDebugSink = @Sendable (SYDebugEvent) -> Void

// MARK: - 事件 → 日志条目

extension SYDebugLogEntry {

    /// 将结构化事件转换为面板日志条目。`stage` 用于标注当前阶段（搜索/详情/目录/正文/流程）。
    static func make(event: SYDebugEvent, stage: String) -> SYDebugLogEntry {
        switch event {
        case let .contentSet(type, length, preview, url):
            return SYDebugLogEntry(
                level: .info,
                step: "[\(stage)] 原始数据",
                summary: "类型: \(type) · \(length) 字符",
                detail: preview.isEmpty ? url : "\(preview)\n\n来源: \(url)"
            )

        case let .requestSent(url, method, _):
            return SYDebugLogEntry(
                level: .info,
                step: "[\(stage)] 请求",
                summary: "\(method.uppercased()) \(url)",
                detail: url
            )

        case let .responseReceived(url, statusCode, bytes, preview, truncated):
            let statusText = statusCode.map { String($0) } ?? "无状态码"
            let truncatedText = truncated ? "（已截断）" : ""
            return SYDebugLogEntry(
                level: (statusCode ?? 0) >= 400 ? .warning : .info,
                step: "[\(stage)] 响应",
                summary: "HTTP \(statusText) · \(bytes) 字节\(truncatedText)",
                detail: preview.isEmpty ? url : "\(preview)\n\n来源: \(url)"
            )

        case let .rulesParsed(rule, segments):
            let segs = segments.enumerated().map { "[\($0.offset)] \($0.element)" }
                .joined(separator: "\n")
            return SYDebugLogEntry(
                level: .pipeline,
                step: "[\(stage)] 规则解析",
                summary: "规则: \(rule.prefix(80))",
                detail: segs.isEmpty ? nil : segs
            )

        case let .beforeExtract(index, mode, rule):
            return SYDebugLogEntry(
                level: .pipeline,
                step: "[\(stage)] 提取 #\(index)",
                summary: "[\(mode)] \(rule.prefix(100))",
                detail: nil
            )

        case let .afterExtractValue(index, result):
            let empty = result.isEmpty
            return SYDebugLogEntry(
                level: empty ? .warning : .pipeline,
                step: "[\(stage)] 提取结果 #\(index)",
                summary: empty ? "（空）" : result.prefix(140).description,
                detail: result.count > 140 ? result : nil
            )

        case let .afterExtractList(index, count, items):
            let detail = items.enumerated().map { "  [\($0.offset)] \($0.element)" }
                .joined(separator: "\n")
            return SYDebugLogEntry(
                level: count == 0 ? .warning : .pipeline,
                step: "[\(stage)] 提取列表 #\(index)",
                summary: "共 \(count) 项",
                detail: detail.isEmpty ? nil : detail
            )

        case let .regexApplied(index, pattern, replacement, before, after):
            return SYDebugLogEntry(
                level: .pipeline,
                step: "[\(stage)] 正则 #\(index)",
                summary: "\(pattern.prefix(40)) → \(replacement.prefix(20))",
                detail: "前: \(before.prefix(200))\n后: \(after.prefix(200))"
            )

        case let .jsExecuted(index, script, result):
            return SYDebugLogEntry(
                level: .pipeline,
                step: "[\(stage)] JS #\(index)",
                summary: result.isEmpty ? "（空结果）" : result.prefix(140).description,
                detail: "脚本: \(script.prefix(300))\n结果: \(result.prefix(500))"
            )

        case let .finalResult(value, elapsedMs):
            let empty = value.isEmpty
            return SYDebugLogEntry(
                level: empty ? .warning : .success,
                step: "[\(stage)] 最终值",
                summary: (empty ? "（空）" : value.prefix(140).description)
                    + String(format: "  (%.1f ms)", elapsedMs),
                detail: value.count > 140 ? value : nil
            )

        case let .finalResultList(values, elapsedMs):
            let detail = values.prefix(20).enumerated().map { "  [\($0.offset)] \($0.element)" }
                .joined(separator: "\n")
            return SYDebugLogEntry(
                level: values.isEmpty ? .warning : .success,
                step: "[\(stage)] 最终列表",
                summary: "共 \(values.count) 项" + String(format: "  (%.1f ms)", elapsedMs),
                detail: detail.isEmpty ? nil : detail
            )

        case let .error(stepText, message):
            return SYDebugLogEntry(
                level: .error,
                step: "[\(stage)] \(stepText)",
                summary: message,
                detail: message
            )
        }
    }
}
