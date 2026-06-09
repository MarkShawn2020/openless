import Foundation
import Speech
import AVFoundation
import OpenLessShared

/// 语音转写：按配置选择引擎——火山引擎(Volcengine 流式 ASR，复刻桌面)配了 Key 就用它，
/// 否则退回 Apple 系统识别。麦克风采集统一走 AVAudioEngine；火山路径把音频重采样成 16k/16bit/mono。
final class SpeechDictator: ObservableObject {
    enum Phase { case idle, recording, finished }

    @Published var phase: Phase = .idle
    @Published var transcript: String = ""
    @Published var level: CGFloat = 0
    @Published var error: String?
    @Published var engineLabel: String = ""

    private let appleRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    private var volc: VolcengineASR?
    private var converter: AVAudioConverter?
    private let targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000,
                                             channels: 1, interleaved: true)!
    private var usingVolc = false
    private var finalTimeout: DispatchWorkItem?

    func requestAuthorization() {
        SFSpeechRecognizer.requestAuthorization { _ in }
        AVAudioApplication.requestRecordPermission { _ in }
    }

    func toggle() {
        switch phase {
        case .recording: stop()
        default: start()
        }
    }

    func start() {
        transcript = ""
        error = nil
        let prefs = SharedStore.shared.loadPreferences()
        let creds = SharedStore.shared.loadCredentials()

        if prefs.activeAsrProvider == "volcengine",
           let e = creds.providers.asr["volcengine"],
           let appKey = e.appKey, !appKey.isEmpty,
           let token = e.accessKey, !token.isEmpty {
            let resource = (e.resourceId?.isEmpty == false) ? e.resourceId! : "volc.seedasr.sauc.duration"
            usingVolc = true
            engineLabel = "火山引擎"
            startVolc(.init(appKey: appKey, accessToken: token, resourceId: resource))
        } else {
            usingVolc = false
            engineLabel = (prefs.activeAsrProvider == "volcengine") ? "火山引擎（缺 Key→系统识别）" : "系统识别"
            startApple()
        }
    }

    func reset() {
        transcript = ""
        error = nil
        phase = .idle
        level = 0
    }

    // MARK: - Apple 系统识别

    private func startApple() {
        guard let recognizer = appleRecognizer, recognizer.isAvailable else {
            setError("语音识别暂不可用（检查网络或语言支持）"); return
        }
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            guard let self else { return }
            guard status == .authorized else { self.setError("未授权语音识别"); return }
            AVAudioApplication.requestRecordPermission { granted in
                guard granted else { self.setError("未授权麦克风"); return }
                DispatchQueue.main.async { self.beginAppleAudio(recognizer) }
            }
        }
    }

    private func beginAppleAudio(_ recognizer: SFSpeechRecognizer) {
        do {
            try activateSession()
            let req = SFSpeechAudioBufferRecognitionRequest()
            req.shouldReportPartialResults = true
            request = req
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                self?.request?.append(buffer)
                self?.updateLevel(buffer)
            }
            engine.prepare()
            try engine.start()
            phase = .recording
            task = recognizer.recognitionTask(with: req) { [weak self] result, err in
                guard let self else { return }
                if let result {
                    let text = result.bestTranscription.formattedString
                    DispatchQueue.main.async { self.transcript = text }
                }
                if err != nil || (result?.isFinal ?? false) { self.teardown(finished: true) }
            }
        } catch {
            setError(error.localizedDescription); teardown(finished: false)
        }
    }

    // MARK: - 火山引擎流式 ASR

    private func startVolc(_ creds: VolcengineASR.Credentials) {
        AVAudioApplication.requestRecordPermission { [weak self] granted in
            guard let self else { return }
            guard granted else { self.setError("未授权麦克风"); return }
            DispatchQueue.main.async { self.beginVolcAudio(creds) }
        }
    }

    private func beginVolcAudio(_ creds: VolcengineASR.Credentials) {
        do {
            try activateSession()
            let v = VolcengineASR(creds: creds)
            v.onPartial = { [weak self] t in DispatchQueue.main.async { self?.transcript = t } }
            v.onFinal = { [weak self] t in
                DispatchQueue.main.async { self?.transcript = t; self?.teardown(finished: true) }
            }
            v.onError = { [weak self] m in
                DispatchQueue.main.async { self?.setError(m); self?.teardown(finished: false) }
            }
            volc = v
            v.start()

            let input = engine.inputNode
            let inFormat = input.outputFormat(forBus: 0)
            converter = AVAudioConverter(from: inFormat, to: targetFormat)
            input.installTap(onBus: 0, bufferSize: 2048, format: inFormat) { [weak self] buffer, _ in
                guard let self else { return }
                self.updateLevel(buffer)
                if let data = self.convertToPCM16(buffer) { self.volc?.consume(pcm: data) }
            }
            engine.prepare()
            try engine.start()
            phase = .recording
        } catch {
            setError(error.localizedDescription); teardown(finished: false)
        }
    }

    /// 把任意输入格式重采样为 16k/16bit/mono 的 PCM 字节。
    private func convertToPCM16(_ buffer: AVAudioPCMBuffer) -> Data? {
        guard let converter else { return nil }
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return nil }
        var fed = false
        var convErr: NSError?
        let status = converter.convert(to: out, error: &convErr) { _, outStatus in
            if fed { outStatus.pointee = .noDataNow; return nil }
            fed = true
            outStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, convErr == nil, out.frameLength > 0,
              let ch = out.int16ChannelData else { return nil }
        return Data(bytes: ch[0], count: Int(out.frameLength) * 2)
    }

    // MARK: - 停止 / 公共

    func stop() {
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        if usingVolc {
            volc?.finish()  // 发末帧，等 onFinal 回最终结果
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.phase == .recording else { return }
                self.teardown(finished: true)  // 12s 兜底：用已识别 transcript 收尾
            }
            finalTimeout = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 12, execute: work)
        } else {
            request?.endAudio()
            DispatchQueue.main.async { if self.phase == .recording { self.phase = .finished } }
        }
    }

    private func activateSession() throws {
        let s = AVAudioSession.sharedInstance()
        try s.setCategory(.record, mode: .measurement, options: .duckOthers)
        try s.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private func teardown(finished: Bool) {
        finalTimeout?.cancel(); finalTimeout = nil
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        request = nil
        task = nil
        volc?.cancel(); volc = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        DispatchQueue.main.async {
            self.level = 0
            if finished { self.phase = .finished }
        }
    }

    private func updateLevel(_ buffer: AVAudioPCMBuffer) {
        guard let ch = buffer.floatChannelData?[0] else { return }
        let n = Int(buffer.frameLength)
        guard n > 0 else { return }
        var sum: Float = 0
        for i in 0..<n { sum += ch[i] * ch[i] }
        let rms = sqrt(sum / Float(n))
        let lvl = CGFloat(min(1, rms * 12))
        DispatchQueue.main.async { self.level = lvl }
    }

    private func setError(_ msg: String) {
        DispatchQueue.main.async { self.error = msg }
    }
}
