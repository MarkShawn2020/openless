import Foundation

/// App Group 容器内的 JSON 持久化（偏好、风格包等），主 App 与键盘扩展共读。
/// 凭据不走这里——敏感数据存 Keychain（Phase 1 的 KeychainStore）。
///
/// 线程安全：所有读写在内部串行队列上序列化；`encoder`/`decoder` 不跨线程共享。
public final class SharedStore: @unchecked Sendable {
    public static let shared = SharedStore()

    private let dir: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let queue = DispatchQueue(label: "top.openless.ios.sharedstore")

    private init(subdirectory: String = "OpenLess") {
        dir = AppGroup.containerURL.appendingPathComponent(subdirectory, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder = JSONDecoder()
    }

    private func url(_ name: String) -> URL { dir.appendingPathComponent(name) }

    public func load<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        queue.sync {
            guard let data = try? Data(contentsOf: url(name)) else { return nil }
            return try? decoder.decode(T.self, from: data)
        }
    }

    public func save<T: Encodable>(_ value: T, to name: String) throws {
        try queue.sync {
            let data = try encoder.encode(value)
            try data.write(to: url(name), options: [.atomic])
        }
    }

    // MARK: - 便捷访问

    public func loadPreferences() -> Preferences {
        load(Preferences.self, from: "preferences.json") ?? .default
    }

    public func savePreferences(_ prefs: Preferences) throws {
        try save(prefs, to: "preferences.json")
    }

    public func loadStylePacks() -> [StylePack] {
        load([StylePack].self, from: "style-packs.json") ?? StylePack.builtins()
    }

    public func saveStylePacks(_ packs: [StylePack]) throws {
        try save(packs, to: "style-packs.json")
    }

    // 凭据：模拟器/未签名阶段存沙盒 JSON（Keychain 需签名后的 access group，未签名会 -34018 失败）。
    // 真机签名后改走 Keychain（见 KeychainStore）。
    public func loadCredentials() -> CredsRoot {
        load(CredsRoot.self, from: "credentials.json") ?? CredsRoot()
    }

    public func saveCredentials(_ creds: CredsRoot) throws {
        try save(creds, to: "credentials.json")
    }
}
