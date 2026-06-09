import Foundation

/// 火山引擎大模型流式 ASR 二进制帧编解码（移植自桌面 asr/frame.rs）。
/// 帧结构：4 字节 header + 可选大端 i32 sequence + 4 字节大端 u32 payload size + payload。
/// 固定 no-compression。

public enum VolcMessageType: UInt8 {
    case fullClientRequest = 0b0001
    case audioOnlyRequest = 0b0010
    case fullServerResponse = 0b1001
    case errorMessage = 0b1111
}

public enum VolcFlags: UInt8 {
    case none = 0b0000
    case positiveSequence = 0b0001
    case lastPacket = 0b0010
    case negativeSequence = 0b0011
}

public enum VolcSerialization: UInt8 {
    case none = 0b0000
    case json = 0b0001
}

public struct VolcParsedFrame {
    public var messageType: VolcMessageType?
    public var flags: UInt8
    public var sequence: Int32?
    public var errorCode: UInt32?
    public var payload: Data

    /// 流结束信号只信帧头 flags（lastPacket / negativeSequence / 负序号）。
    public var isFinal: Bool {
        flags == VolcFlags.lastPacket.rawValue
            || flags == VolcFlags.negativeSequence.rawValue
            || (sequence ?? 0) < 0
    }
}

public enum VolcFrame {
    static let headerByte0: UInt8 = 0x11  // header_size=1*4=4, version=1
    static let compressionNone: UInt8 = 0b0000

    public static func build(_ type: VolcMessageType,
                             _ flags: VolcFlags,
                             _ serialization: VolcSerialization,
                             payload: Data,
                             sequence: Int32?) -> Data {
        var frame = Data()
        frame.append(headerByte0)
        frame.append((type.rawValue << 4) | flags.rawValue)
        frame.append((serialization.rawValue << 4) | compressionNone)
        frame.append(0x00)

        if (flags == .positiveSequence || flags == .negativeSequence), let seq = sequence {
            var be = seq.bigEndian
            withUnsafeBytes(of: &be) { frame.append(contentsOf: $0) }
        }

        var size = UInt32(payload.count).bigEndian
        withUnsafeBytes(of: &size) { frame.append(contentsOf: $0) }
        frame.append(payload)
        return frame
    }

    public static func parse(_ data: Data) -> VolcParsedFrame? {
        let bytes = [UInt8](data)
        guard bytes.count >= 8 else { return nil }

        let headerSize = Int(bytes[0] & 0x0F) * 4
        guard headerSize >= 4, bytes.count >= headerSize + 4 else { return nil }

        let mt = VolcMessageType(rawValue: (bytes[1] >> 4) & 0x0F)
        let flags = bytes[1] & 0x0F
        let compression = bytes[2] & 0x0F
        guard compression == compressionNone else { return nil }

        var offset = headerSize
        var sequence: Int32?
        if flags == VolcFlags.positiveSequence.rawValue || flags == VolcFlags.negativeSequence.rawValue {
            guard let v = readU32(bytes, offset) else { return nil }
            sequence = Int32(bitPattern: v)
            offset += 4
        }

        if mt == .errorMessage {
            guard let code = readU32(bytes, offset), let msz = readU32(bytes, offset + 4) else { return nil }
            offset += 8
            let size = Int(msz)
            guard bytes.count >= offset + size else { return nil }
            return VolcParsedFrame(messageType: mt, flags: flags, sequence: sequence,
                                   errorCode: code, payload: Data(bytes[offset..<offset + size]))
        }

        guard let psz = readU32(bytes, offset) else { return nil }
        offset += 4
        let size = Int(psz)
        guard bytes.count >= offset + size else { return nil }
        return VolcParsedFrame(messageType: mt, flags: flags, sequence: sequence,
                               errorCode: nil, payload: Data(bytes[offset..<offset + size]))
    }

    private static func readU32(_ b: [UInt8], _ o: Int) -> UInt32? {
        guard b.count >= o + 4 else { return nil }
        return (UInt32(b[o]) << 24) | (UInt32(b[o + 1]) << 16) | (UInt32(b[o + 2]) << 8) | UInt32(b[o + 3])
    }
}
