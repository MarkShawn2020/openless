import Foundation

/// 凭据模型，结构沿用桌面 keyring 的 `CredsRoot`（persistence.rs:538-651），JSON 采用 camelCase。
/// iOS 端整体以一条 JSON 存入 Keychain（见 KeychainStore，Phase 1）。

public struct CredsAsrEntry: Codable, Sendable {
    public var apiKey: String?
    public var baseURL: String?
    public var model: String?
    public var appKey: String?        // 火山引擎 App Key
    public var accessKey: String?     // 火山引擎 Access Token
    public var resourceId: String?    // 火山引擎 Resource ID
    public var vocabularyId: String?  // Bailian 词汇表 ID

    public init(apiKey: String? = nil, baseURL: String? = nil, model: String? = nil,
                appKey: String? = nil, accessKey: String? = nil,
                resourceId: String? = nil, vocabularyId: String? = nil) {
        self.apiKey = apiKey; self.baseURL = baseURL; self.model = model
        self.appKey = appKey; self.accessKey = accessKey
        self.resourceId = resourceId; self.vocabularyId = vocabularyId
    }
}

public struct CredsLlmEntry: Codable, Sendable {
    public var displayName: String?
    public var apiKey: String?
    public var baseURL: String?
    public var model: String?
    public var temperature: Double?
    public var extraHeaders: [String: String]?

    public init(displayName: String? = nil, apiKey: String? = nil, baseURL: String? = nil,
                model: String? = nil, temperature: Double? = nil,
                extraHeaders: [String: String]? = nil) {
        self.displayName = displayName; self.apiKey = apiKey; self.baseURL = baseURL
        self.model = model; self.temperature = temperature; self.extraHeaders = extraHeaders
    }
}

public struct CredsActive: Codable, Sendable {
    public var asr: String
    public var llm: String
    public init(asr: String = "", llm: String = "") { self.asr = asr; self.llm = llm }
}

public struct CredsProviders: Codable, Sendable {
    public var asr: [String: CredsAsrEntry]
    public var llm: [String: CredsLlmEntry]
    public init(asr: [String: CredsAsrEntry] = [:], llm: [String: CredsLlmEntry] = [:]) {
        self.asr = asr; self.llm = llm
    }
}

public struct CredsRoot: Codable, Sendable {
    public var version: Int
    public var active: CredsActive
    public var providers: CredsProviders

    public init(version: Int = 1, active: CredsActive = .init(), providers: CredsProviders = .init()) {
        self.version = version
        self.active = active
        self.providers = providers
    }
}
