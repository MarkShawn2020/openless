import Foundation

/// 用户偏好的 iOS 子集，对齐桌面 `UserPreferences`（types.rs:524-752）中与移动端相关的字段。
/// 桌面端的热键/插入方式/Less Computer 等桌面特有项不移植。JSON 采用 camelCase。
public struct Preferences: Codable, Sendable {
    // 润色与风格
    public var defaultMode: PolishMode
    public var activeStylePackId: String

    // Provider 选择
    public var activeAsrProvider: String   // volcengine | bailian | whisper
    public var activeLlmProvider: String   // openai | ark | gemini

    // 语言
    public var workingLanguages: [String]          // 例：["zh", "en"]
    public var outputLanguagePreference: String    // auto | zhCn | zhTw | en | ja | ko
    public var chineseScriptPreference: String     // auto | simplified | traditional

    // 行为
    public var llmThinkingEnabled: Bool
    public var streamingInsert: Bool

    // 市场
    public var marketplaceBaseUrl: String          // 空 = 用默认 https://apic.openless.top

    // 免跳转保持时长（分钟）：0=每次跳转；>0=保持 N 分钟；-1=一直保持
    public var voiceHoldMinutes: Int

    public init(
        defaultMode: PolishMode = .light,
        activeStylePackId: String = "builtin.light",
        activeAsrProvider: String = "volcengine",
        activeLlmProvider: String = "openai",
        workingLanguages: [String] = ["zh", "en"],
        outputLanguagePreference: String = "auto",
        chineseScriptPreference: String = "auto",
        llmThinkingEnabled: Bool = false,
        streamingInsert: Bool = true,
        marketplaceBaseUrl: String = "",
        voiceHoldMinutes: Int = 30
    ) {
        self.defaultMode = defaultMode
        self.activeStylePackId = activeStylePackId
        self.activeAsrProvider = activeAsrProvider
        self.activeLlmProvider = activeLlmProvider
        self.workingLanguages = workingLanguages
        self.outputLanguagePreference = outputLanguagePreference
        self.chineseScriptPreference = chineseScriptPreference
        self.llmThinkingEnabled = llmThinkingEnabled
        self.streamingInsert = streamingInsert
        self.marketplaceBaseUrl = marketplaceBaseUrl
        self.voiceHoldMinutes = voiceHoldMinutes
    }

    public static let `default` = Preferences()

    /// 解码时容忍缺字段（老版本/部分写）。
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Preferences.default
        defaultMode = try c.decodeIfPresent(PolishMode.self, forKey: .defaultMode) ?? d.defaultMode
        activeStylePackId = try c.decodeIfPresent(String.self, forKey: .activeStylePackId) ?? d.activeStylePackId
        activeAsrProvider = try c.decodeIfPresent(String.self, forKey: .activeAsrProvider) ?? d.activeAsrProvider
        activeLlmProvider = try c.decodeIfPresent(String.self, forKey: .activeLlmProvider) ?? d.activeLlmProvider
        workingLanguages = try c.decodeIfPresent([String].self, forKey: .workingLanguages) ?? d.workingLanguages
        outputLanguagePreference = try c.decodeIfPresent(String.self, forKey: .outputLanguagePreference) ?? d.outputLanguagePreference
        chineseScriptPreference = try c.decodeIfPresent(String.self, forKey: .chineseScriptPreference) ?? d.chineseScriptPreference
        llmThinkingEnabled = try c.decodeIfPresent(Bool.self, forKey: .llmThinkingEnabled) ?? d.llmThinkingEnabled
        streamingInsert = try c.decodeIfPresent(Bool.self, forKey: .streamingInsert) ?? d.streamingInsert
        marketplaceBaseUrl = try c.decodeIfPresent(String.self, forKey: .marketplaceBaseUrl) ?? d.marketplaceBaseUrl
        voiceHoldMinutes = try c.decodeIfPresent(Int.self, forKey: .voiceHoldMinutes) ?? d.voiceHoldMinutes
    }
}
