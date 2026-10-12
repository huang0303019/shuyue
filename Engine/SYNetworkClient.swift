import Foundation

// MARK: - 网络层

/// 网络请求结果。
struct SYHTTPResult: Sendable {
    let data: Data
    let response: URLResponse?
    let statusCode: Int?
}

/// 轻量网络客户端。支持 GET/POST、超时、自定义请求头。
struct SYNetworkClient: Sendable {
    var timeout: TimeInterval
    var defaultHeaders: [String: String]
    /// 用于测试注入的 URLSessionProtocol 替换；nil 时使用 URLSession。
    var session: URLSession?
    /// 是否启用 cookie jar（默认关闭，与书源 enabledCookieJar 联动）。
    var useCookieJar: Bool = false

    init(
        timeout: TimeInterval = 15,
        defaultHeaders: [String: String] = [:],
        session: URLSession? = nil
    ) {
        self.timeout = timeout
        self.defaultHeaders = defaultHeaders
        self.session = session
    }

    /// 发起请求。method 支持 GET/POST/PUT/DELETE/HEAD。
    func request(
        url: String,
        method: String = "GET",
        headers: [String: String] = [:],
        body: Data? = nil,
        debug: SYDebugSink? = nil
    ) async throws -> SYHTTPResult {
        guard let requestURL = URL(string: url) else {
            throw SYEngineError.badURL(url)
        }
        var req = URLRequest(url: requestURL)
        req.httpMethod = method
        req.timeoutInterval = timeout
        var merged = defaultHeaders
        for (k, v) in headers { merged[k.lowercased()] = v }
        for (k, v) in merged { req.setValue(v, forHTTPHeaderField: k) }
        if let body {
            req.httpBody = body
        }

        debug?(.requestSent(url: url, method: method, headers: merged))

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        if useCookieJar {
            config.httpCookieStorage = HTTPCookieStorage.shared
        } else {
            config.httpCookieStorage = nil
            config.httpShouldSetCookies = false
        }
        let activeSession = session ?? URLSession(configuration: config)
        defer {
            if session == nil { activeSession.finishTasksAndInvalidate() }
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await activeSession.data(for: req)
        } catch {
            debug?(.error(step: "请求失败", message: "\(method.uppercased()) \(url)：\(error.localizedDescription)"))
            throw SYEngineError.network(error.localizedDescription)
        }
        let code = (response as? HTTPURLResponse)?.statusCode
        let previewData = data.prefix(8192)
        let preview = String(data: previewData, encoding: .utf8) ?? ""
        debug?(.responseReceived(
            url: url,
            statusCode: code,
            bytes: data.count,
            preview: preview,
            truncated: data.count > 8192
        ))
        return SYHTTPResult(data: data, response: response, statusCode: code)
    }

    /// GET 便捷方法（自动读取响应为 UTF-8 文本）。
    func getText(url: String, headers: [String: String] = [:]) async throws -> String {
        let result = try await request(url: url, method: "GET", headers: headers)
        return SYTextDecoding.text(from: result.data)
    }

    /// 解析请求头字符串（书源 header 为 JSON 文本）。
    static func parseHeaderJSON(_ jsonText: String?) -> [String: String] {
        guard let jsonText, let data = jsonText.data(using: .utf8) else { return [:] }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        var out: [String: String] = [:]
        for (k, v) in obj {
            if let s = v as? String { out[k] = s }
            else if let n = v as? NSNumber { out[k] = n.stringValue }
        }
        return out
    }
}

// MARK: - 文本解码

enum SYTextDecoding {
    /// 优先按 UTF-8，失败时按响应头 charset 或 GBK 等常见中文编码回退。
    static func text(from data: Data, response: URLResponse? = nil) -> String {
        if let s = String(data: data, encoding: .utf8) { return s }
        if let s = String(data: data, encoding: .isoLatin1) { return s }
        // GBK / GB18030 常见于中文书源 HTML。
        let encodings: [String.Encoding] = [
            String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))),
            String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.big5.rawValue))),
        ]
        for enc in encodings {
            if let s = String(data: data, encoding: enc) { return s }
        }
        return String(decoding: data, as: UTF8.self)
    }
}

// MARK: - 错误

enum SYEngineError: Error, LocalizedError, Equatable {
    case badURL(String)
    case network(String)
    case ruleNotMatched(String)
    case emptyResult(String)
    case jsError(String)
    case jsonPathNotFound(String)
    case unsupportedRule(String)

    var errorDescription: String? {
        switch self {
        case .badURL(let u): return "无效 URL：\(u)"
        case .network(let m): return "网络错误：\(m)"
        case .ruleNotMatched(let r): return "规则未命中：\(r)"
        case .emptyResult(let r): return "结果为空：\(r)"
        case .jsError(let m): return "JS 错误：\(m)"
        case .jsonPathNotFound(let p): return "JSONPath 未命中：\(p)"
        case .unsupportedRule(let r): return "不支持的规则：\(r)"
        }
    }
}
