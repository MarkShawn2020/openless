import Foundation

/// 免跳转语音的进程间桥：键盘扩展 ↔ 主 App。
/// - Darwin 通知：跨进程信号（start/stop/partial/final）。
/// - App Group UserDefaults：传文本(partial/final) + 主 App 是否在后台保活(hostAlive)。
///
/// 用法：主 App(被 PiP 保活)observe(startNote) 开始录音、把 partial/final 写进 App Group 并 post 通知；
/// 键盘 post(startNote) 触发、observe(finalNote) 后取 final 插入。

private var voiceObservers: [String: () -> Void] = [:]

private let voiceCallback: CFNotificationCallback = { _, _, name, _, _ in
    guard let raw = name?.rawValue as String? else { return }
    let handler = voiceObservers[raw]
    DispatchQueue.main.async { handler?() }
}

public enum VoiceBridge {
    public static let appGroup = "group.top.openless.ios"

    // Darwin 通知名
    public static let startNote = "top.openless.voice.start"
    public static let stopNote = "top.openless.voice.stop"
    public static let partialNote = "top.openless.voice.partial"
    public static let finalNote = "top.openless.voice.final"

    // App Group keys
    public static let partialKey = "voice.partial"
    public static let finalKey = "voice.final"
    public static let hostAliveKey = "voice.hostAlive"

    public static var defaults: UserDefaults { UserDefaults(suiteName: appGroup) ?? .standard }

    public static func post(_ name: String) {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(name as CFString), nil, nil, true)
    }

    public static func observe(_ name: String, _ handler: @escaping () -> Void) {
        voiceObservers[name] = handler
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            nil, voiceCallback, name as CFString, nil, .deliverImmediately)
    }

    // 保活标志
    public static func setHostAlive(_ v: Bool) { defaults.set(v, forKey: hostAliveKey) }
    public static func isHostAlive() -> Bool { defaults.bool(forKey: hostAliveKey) }

    // partial / final 文本
    public static func setPartial(_ t: String) { defaults.set(t, forKey: partialKey) }
    public static func partial() -> String { defaults.string(forKey: partialKey) ?? "" }
    public static func setFinal(_ t: String) { defaults.set(t, forKey: finalKey) }
    public static func takeFinal() -> String? {
        guard let t = defaults.string(forKey: finalKey), !t.isEmpty else { return nil }
        defaults.removeObject(forKey: finalKey)
        return t
    }
}
