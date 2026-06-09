import Foundation

/// App Group：主 App ↔ 键盘扩展 的共享身份与容器。
public enum AppGroup {
    /// 必须与两端 entitlements 的 application-groups 一致。
    public static let identifier = "group.top.openless.ios"

    /// 共享容器根目录；若未配置（如纯单测环境）退化到 caches，避免崩溃。
    public static var containerURL: URL {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) {
            return url
        }
        return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    }

    /// 共享 UserDefaults（轻量标志位 / 跳转信令）。
    public static var defaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }
}
