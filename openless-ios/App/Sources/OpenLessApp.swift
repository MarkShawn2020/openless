import SwiftUI
import OpenLessShared

/// OpenLess iOS 主 App 入口。
/// 职责（随阶段填充）：麦克风录音 → 语音识别 → 润色 → 经 App Group 回传键盘扩展；
/// 配置/凭据管理；云端风格包市场。
@main
struct OpenLessApp: App {
    init() {
        // 启动即把偏好写入 App Group 共享容器（签名后生效）；也用于验证共享容器可写。
        let store = SharedStore.shared
        try? store.savePreferences(store.loadPreferences())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
