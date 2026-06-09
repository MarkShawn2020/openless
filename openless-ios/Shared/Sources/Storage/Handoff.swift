import Foundation

/// 主 App ↔ 键盘扩展 的「识别结果」交接：主 App 识别完写入共享容器，键盘下次激活时取出并插入。
/// 仅用共享 UserDefaults（键盘侧用同名 suite + key 读取，无需链接本框架）。
public enum Handoff {
    public static let pendingInsertKey = "pendingInsertText"

    public static func setPendingInsert(_ text: String) {
        AppGroup.defaults.set(text, forKey: pendingInsertKey)
    }

    /// 取出并清空待插入文本。
    public static func takePendingInsert() -> String? {
        let d = AppGroup.defaults
        guard let t = d.string(forKey: pendingInsertKey), !t.isEmpty else { return nil }
        d.removeObject(forKey: pendingInsertKey)
        return t
    }
}
