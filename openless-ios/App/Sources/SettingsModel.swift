import SwiftUI
import OpenLessShared

/// 设置页状态：偏好（App Group JSON）+ 凭据（Keychain）。
/// 编辑即时自动落盘；同时提供显式 `save()` 供「保存」按钮调用并回报结果。
@MainActor
final class SettingsModel: ObservableObject {
    @Published var prefs: Preferences
    @Published var creds: CredsRoot

    init() {
        prefs = SharedStore.shared.loadPreferences()
        creds = SharedStore.shared.loadCredentials()
    }

    /// 显式保存：失败会抛错，供 UI 给出明确反馈。
    func save() throws {
        try SharedStore.shared.savePreferences(prefs)
        try SharedStore.shared.saveCredentials(creds)
    }

    /// 编辑时的尽力自动保存（不打断输入）。
    private func autosave() { try? save() }

    func pref<T>(_ kp: WritableKeyPath<Preferences, T>) -> Binding<T> {
        Binding(
            get: { self.prefs[keyPath: kp] },
            set: { self.prefs[keyPath: kp] = $0; self.autosave() }
        )
    }

    func asr(_ kp: WritableKeyPath<CredsAsrEntry, String?>) -> Binding<String> {
        Binding(
            get: { self.creds.providers.asr[self.prefs.activeAsrProvider]?[keyPath: kp] ?? "" },
            set: { v in
                var e = self.creds.providers.asr[self.prefs.activeAsrProvider] ?? CredsAsrEntry()
                e[keyPath: kp] = v.isEmpty ? nil : v
                self.creds.providers.asr[self.prefs.activeAsrProvider] = e
                self.creds.active.asr = self.prefs.activeAsrProvider
                self.autosave()
            }
        )
    }

    func llm(_ kp: WritableKeyPath<CredsLlmEntry, String?>) -> Binding<String> {
        Binding(
            get: { self.creds.providers.llm[self.prefs.activeLlmProvider]?[keyPath: kp] ?? "" },
            set: { v in
                var e = self.creds.providers.llm[self.prefs.activeLlmProvider] ?? CredsLlmEntry()
                e[keyPath: kp] = v.isEmpty ? nil : v
                self.creds.providers.llm[self.prefs.activeLlmProvider] = e
                self.creds.active.llm = self.prefs.activeLlmProvider
                self.autosave()
            }
        )
    }
}
