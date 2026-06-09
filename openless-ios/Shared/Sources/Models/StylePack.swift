import Foundation

/// 风格包来源类型，对齐桌面 `StylePackKind`。
public enum StylePackKind: String, Codable, Sendable {
    case builtin
    case imported
}

/// 风格包示例（标题 + 输入 → 输出）。
public struct StylePackExample: Codable, Hashable, Sendable {
    public var title: String
    public var input: String
    public var output: String

    public init(title: String, input: String, output: String) {
        self.title = title
        self.input = input
        self.output = output
    }
}

/// 风格包，字段对齐桌面 `StylePack`（types.rs:275-298），JSON 采用 camelCase。
/// iOS 本地 `style-packs.json` 与云端市场下载的 ZIP 清单共用此结构。
public struct StylePack: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var description: String
    public var author: String?
    public var version: String
    public var kind: StylePackKind
    public var baseMode: PolishMode
    public var prompt: String
    public var examples: [StylePackExample]
    public var tags: [String]
    public var iconPath: String?
    public var createdAt: String?
    public var updatedAt: String?
    public var enabled: Bool
    public var active: Bool
    public var recommendedModel: String?
    public var compatibleAppVersion: String?
    public var originPackId: String?
    public var originAuthorLogin: String?

    public init(
        id: String,
        name: String,
        description: String = "",
        author: String? = nil,
        version: String = "1.0.0",
        kind: StylePackKind = .imported,
        baseMode: PolishMode = .light,
        prompt: String = "",
        examples: [StylePackExample] = [],
        tags: [String] = [],
        iconPath: String? = nil,
        createdAt: String? = nil,
        updatedAt: String? = nil,
        enabled: Bool = true,
        active: Bool = false,
        recommendedModel: String? = nil,
        compatibleAppVersion: String? = nil,
        originPackId: String? = nil,
        originAuthorLogin: String? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.author = author
        self.version = version
        self.kind = kind
        self.baseMode = baseMode
        self.prompt = prompt
        self.examples = examples
        self.tags = tags
        self.iconPath = iconPath
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.enabled = enabled
        self.active = active
        self.recommendedModel = recommendedModel
        self.compatibleAppVersion = compatibleAppVersion
        self.originPackId = originPackId
        self.originAuthorLogin = originAuthorLogin
    }
}

public extension StylePack {
    /// 四个内置风格包，对齐桌面 builtin.{raw,light,structured,formal}。
    static func builtins() -> [StylePack] {
        PolishMode.allCases.map { mode in
            StylePack(
                id: "builtin.\(mode.rawValue)",
                name: mode.displayName,
                description: "内置风格：\(mode.displayName)",
                author: "OpenLess",
                version: "1.0.0",
                kind: .builtin,
                baseMode: mode,
                enabled: true,
                active: mode == .light
            )
        }
    }
}
