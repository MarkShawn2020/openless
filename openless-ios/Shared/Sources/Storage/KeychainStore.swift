import Foundation
import Security

/// 凭据存储：把整个 `CredsRoot` 以一条 JSON 存入 iOS Keychain（generic password）。
/// 结构沿用桌面 keyring 的 CredsRoot；ASR/LLM 的 API Key 等敏感数据只走这里，不落 App Group 明文。
public final class KeychainStore {
    public static let shared = KeychainStore()

    private let service = "top.openless.ios.credentials"
    private let account = "credentials.v1"

    public init() {}

    public func loadCreds() -> CredsRoot {
        guard let data = read() else { return CredsRoot() }
        return (try? JSONDecoder().decode(CredsRoot.self, from: data)) ?? CredsRoot()
    }

    public func saveCreds(_ creds: CredsRoot) throws {
        let data = try JSONEncoder().encode(creds)
        try write(data)
    }

    // MARK: - SecItem 封装

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private func read() -> Data? {
        var q = baseQuery()
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        let status = SecItemCopyMatching(q as CFDictionary, &out)
        guard status == errSecSuccess else { return nil }
        return out as? Data
    }

    private func write(_ data: Data) throws {
        let q = baseQuery()
        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(q as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = q
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.status(addStatus) }
        } else if status != errSecSuccess {
            throw KeychainError.status(status)
        }
    }
}

public enum KeychainError: Error {
    case status(OSStatus)
}
