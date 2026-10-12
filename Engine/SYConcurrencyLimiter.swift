import Foundation

// MARK: - 书源并发率限制器

/// 异步信号量：限制同一书源同时进行的网络请求数（对应 Legado 书源 `concurrentRate` 字段）。
///
/// 书源引擎为 actor 且存在可重入：搜索、详情、目录等多条链路同时
/// 命中同一书源时，多个网络请求可能并发发出。`concurrentRate` 不为空且
/// 大于 0 的书源，用本限制器把「同时进行中的请求」压到该数值。
actor SYConcurrencyLimiter {
    private var available: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    /// - Parameter count: 允许同时进行的请求数；至少为 1。
    init(count: Int) {
        available = max(1, count)
    }

    /// 占用一个并发名额；名额耗尽时挂起等待，直到有人 release。
    func acquire() async {
        if available > 0 {
            available -= 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    /// 释放一个并发名额，并把名额让给最早等待者。
    func release() {
        if waiters.isEmpty {
            available += 1
        } else {
            let waiter = waiters.removeFirst()
            waiter.resume()
        }
    }
}
