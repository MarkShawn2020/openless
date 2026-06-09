import Foundation

/// 润色模式，对齐桌面 `PolishMode`（types.rs）。
/// raw=不润色 / light=轻度 / structured=结构化 / formal=正式。
public enum PolishMode: String, Codable, CaseIterable, Sendable {
    case raw
    case light
    case structured
    case formal

    public var displayName: String {
        switch self {
        case .raw: return "原文"
        case .light: return "轻度润色"
        case .structured: return "结构化"
        case .formal: return "正式"
        }
    }
}
