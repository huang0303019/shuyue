import Foundation

// MARK: - 本地持久化

/// 书悦的轻量本地存储：书源 / 书架 / 历史 / 阅读设置统一以 JSON 存入 UserDefaults。
enum SYLibraryPersistence {
    private static let prefix = "shuyue.store."

    private static func storageKey(_ key: String) -> String { prefix + key }

    static func save<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: storageKey(key))
    }

    static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: storageKey(key)) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    static func remove(key: String) {
        UserDefaults.standard.removeObject(forKey: storageKey(key))
    }
}