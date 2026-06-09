import Foundation
import OpenLessShared

/// 火山引擎 SAUC bigmodel 流式 ASR 客户端（移植自桌面 asr/volcengine.rs）。
/// 用 URLSessionWebSocketTask 连接，发首帧 → 流式发 16k/16bit/mono PCM 音频帧 → 末帧收尾，
/// 接收 FullServerResponse，拼 utterances 文本，partial/final 回调。
final class VolcengineASR {
    struct Credentials {
        let appKey: String
        let accessToken: String
        let resourceId: String
    }

    var onPartial: ((String) -> Void)?
    var onFinal: ((String) -> Void)?
    var onError: ((String) -> Void)?

    private let creds: Credentials
    private var task: URLSessionWebSocketTask?
    private var session: URLSession?
    private var nextSeq: Int32 = 1
    private var pending = Data()
    private var lastPartial = ""
    private var finished = false

    private let chunkBytes = 6_400  // 200ms @ 16k/16bit/mono
    private let endpoint = URL(string: "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async")!

    init(creds: Credentials) { self.creds = creds }

    func start() {
        let connectId = UUID().uuidString
        var req = URLRequest(url: endpoint)
        req.setValue(creds.appKey, forHTTPHeaderField: "X-Api-App-Key")
        req.setValue(creds.accessToken, forHTTPHeaderField: "X-Api-Access-Key")
        req.setValue(creds.resourceId, forHTTPHeaderField: "X-Api-Resource-Id")
        req.setValue(connectId, forHTTPHeaderField: "X-Api-Connect-Id")

        let s = URLSession(configuration: .default)
        session = s
        let t = s.webSocketTask(with: req)
        task = t
        t.resume()

        // 首帧：FullClientRequest + JSON（音频参数 + 请求参数）
        let payload: [String: Any] = [
            "user": ["uid": connectId],
            "audio": ["format": "pcm", "rate": 16_000, "bits": 16, "channel": 1, "codec": "raw"],
            "request": [
                "model_name": "bigmodel",
                "enable_itn": true,
                "enable_punc": true,
                "show_utterances": true,
            ],
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
            onError?("payload 编码失败"); return
        }
        send(VolcFrame.build(.fullClientRequest, .positiveSequence, .json, payload: body, sequence: allocSeq()))
        receiveLoop()
    }

    /// 喂入 16k/16bit/mono PCM；满 6400 字节就发一帧。
    func consume(pcm: Data) {
        pending.append(pcm)
        while pending.count >= chunkBytes {
            let chunk = pending.prefix(chunkBytes)
            pending.removeFirst(chunkBytes)
            send(VolcFrame.build(.audioOnlyRequest, .positiveSequence, .none, payload: Data(chunk), sequence: allocSeq()))
        }
    }

    /// 停止说话：把剩余音频发出，再发负序号末帧收尾，等服务端回 final。
    func finish() {
        if !pending.isEmpty {
            send(VolcFrame.build(.audioOnlyRequest, .positiveSequence, .none, payload: pending, sequence: allocSeq()))
            pending.removeAll()
        }
        let finalSeq = -nextSeq
        nextSeq += 1
        send(VolcFrame.build(.audioOnlyRequest, .negativeSequence, .none, payload: Data(), sequence: finalSeq))
    }

    func cancel() {
        finished = true
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    // MARK: - 内部

    private func allocSeq() -> Int32 { let s = nextSeq; nextSeq += 1; return s }

    private func send(_ data: Data) {
        task?.send(.data(data)) { [weak self] err in
            if let err { self?.fail("发送失败：\(err.localizedDescription)") }
        }
    }

    private func receiveLoop() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let err):
                // 断连/出错：有 partial 就兜底回 final，不丢已识别文字。
                if self.finished { return }
                if !self.lastPartial.isEmpty {
                    self.finished = true
                    self.onFinal?(self.lastPartial)
                } else {
                    self.fail(err.localizedDescription)
                }
            case .success(let msg):
                if case .data(let data) = msg { self.handle(data) }
                if !self.finished { self.receiveLoop() }
            }
        }
    }

    private func handle(_ data: Data) {
        guard let parsed = VolcFrame.parse(data) else { return }

        if parsed.messageType == .errorMessage {
            let body = String(data: parsed.payload, encoding: .utf8) ?? ""
            fail("ASR \(parsed.errorCode ?? 0)：\(body)")
            return
        }
        guard parsed.messageType == .fullServerResponse else { return }
        guard let json = try? JSONSerialization.jsonObject(with: parsed.payload) as? [String: Any] else { return }

        let text = Self.extractText(json)
        if parsed.isFinal {
            finished = true
            onFinal?(text.isEmpty ? lastPartial : text)
        } else if !text.isEmpty {
            lastPartial = text
            onPartial?(text)
        }
    }

    private func fail(_ msg: String) {
        guard !finished else { return }
        finished = true
        onError?(msg)
    }

    /// 优先用 utterances 拼接（含全部分段），否则取 result.text。
    private static func extractText(_ json: [String: Any]) -> String {
        var result: [String: Any]?
        if let r = json["result"] as? [String: Any] {
            result = r
        } else if let arr = json["result"] as? [[String: Any]], let first = arr.first {
            result = first
        } else if json["text"] is String {
            result = json
        }
        guard let result else { return "" }
        if let utts = result["utterances"] as? [[String: Any]] {
            let pieces = utts.compactMap { $0["text"] as? String }
            if !pieces.isEmpty { return pieces.joined() }
        }
        return (result["text"] as? String) ?? ""
    }
}
