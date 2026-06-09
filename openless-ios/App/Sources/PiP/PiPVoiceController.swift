import AVKit
import AVFoundation
import UIKit

/// PiP（画中画）保活：用 AVSampleBufferDisplayLayer 自定义内容源开一个视频小窗，
/// 把主 App 保活在后台，从而能在键盘场景下持续使用麦克风（豆包的做法）。
/// 仅真机可用（模拟器 isPictureInPictureSupported == false）。
final class PiPVoiceController: NSObject, ObservableObject {
    @Published var isActive = false
    let isSupported = AVPictureInPictureController.isPictureInPictureSupported()

    let displayLayer = AVSampleBufferDisplayLayer()
    private var pip: AVPictureInPictureController?
    private var displayLink: CADisplayLink?
    private var pool: CVPixelBufferPool?
    private let size = CGSize(width: 160, height: 120)

    override init() {
        super.init()
        displayLayer.videoGravity = .resizeAspect
        displayLayer.frame = CGRect(origin: .zero, size: size)
        makePool()
    }

    /// 把 displayLayer 挂到可见 view 上（PiP 需从内联视频启动），并创建控制器。
    func configure(hostView: UIView) {
        if displayLayer.superlayer == nil {
            displayLayer.frame = CGRect(origin: .zero, size: size)
            hostView.layer.addSublayer(displayLayer)
        }
        guard isSupported, pip == nil else { return }
        let source = AVPictureInPictureController.ContentSource(
            sampleBufferDisplayLayer: displayLayer, playbackDelegate: self)
        let controller = AVPictureInPictureController(contentSource: source)
        controller.delegate = self
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        pip = controller
    }

    func start() {
        guard isSupported, let pip else { return }
        startFeeding()
        if !pip.isPictureInPictureActive { pip.startPictureInPicture() }
    }

    func stop() {
        pip?.stopPictureInPicture()
        stopFeeding()
    }

    // MARK: - 帧供给（让 layer 持续 "playing"）

    private func startFeeding() {
        stopFeeding()
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.preferredFramesPerSecond = 6
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopFeeding() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func tick() { enqueueFrame() }

    private func makePool() {
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height),
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
        ]
        CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attrs as CFDictionary, &pool)
    }

    private func enqueueFrame() {
        guard displayLayer.isReadyForMoreMediaData,
              let pixelBuffer = renderPixelBuffer(),
              let sample = makeSampleBuffer(from: pixelBuffer) else { return }
        displayLayer.enqueue(sample)
    }

    private func renderPixelBuffer() -> CVPixelBuffer? {
        guard let pool else { return nil }
        var pb: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pb)
        guard let pixelBuffer = pb else { return nil }
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let ctx = CGContext(
            data: CVPixelBufferGetBaseAddress(pixelBuffer),
            width: Int(size.width), height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        ctx.setFillColor(UIColor(red: 0.36, green: 0.30, blue: 0.95, alpha: 1).cgColor)
        ctx.fill(CGRect(origin: .zero, size: size))
        let str = NSAttributedString(string: "🎤", attributes: [.font: UIFont.systemFont(ofSize: 56)])
        UIGraphicsPushContext(ctx)
        let ts = str.size()
        str.draw(at: CGPoint(x: (size.width - ts.width) / 2, y: (size.height - ts.height) / 2))
        UIGraphicsPopContext()
        return pixelBuffer
    }

    private func makeSampleBuffer(from pixelBuffer: CVPixelBuffer) -> CMSampleBuffer? {
        var formatDesc: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer, formatDescriptionOut: &formatDesc)
        guard let formatDesc else { return nil }
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 6),
            presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
            decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        CMSampleBufferCreateForImageBuffer(
            allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer,
            dataReady: true, makeDataReadyCallback: nil, refcon: nil,
            formatDescription: formatDesc, sampleTiming: &timing, sampleBufferOut: &sample)
        return sample
    }

    private func setActive(_ v: Bool) { DispatchQueue.main.async { self.isActive = v } }
}

extension PiPVoiceController: AVPictureInPictureControllerDelegate {
    func pictureInPictureControllerDidStartPictureInPicture(_ c: AVPictureInPictureController) { setActive(true) }
    func pictureInPictureControllerDidStopPictureInPicture(_ c: AVPictureInPictureController) { setActive(false) }
    func pictureInPictureController(_ c: AVPictureInPictureController,
                                    failedToStartPictureInPictureWithError error: Error) { setActive(false) }
}

extension PiPVoiceController: AVPictureInPictureSampleBufferPlaybackDelegate {
    func pictureInPictureController(_ c: AVPictureInPictureController, setPlaying playing: Bool) {}
    func pictureInPictureControllerTimeRangeForPlayback(_ c: AVPictureInPictureController) -> CMTimeRange {
        CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
    }
    func pictureInPictureControllerIsPlaybackPaused(_ c: AVPictureInPictureController) -> Bool { false }
    func pictureInPictureController(_ c: AVPictureInPictureController,
                                    didTransitionToRenderSize newRenderSize: CMVideoDimensions) {}
    func pictureInPictureController(_ c: AVPictureInPictureController, skipByInterval skipInterval: CMTime,
                                    completion completionHandler: @escaping () -> Void) { completionHandler() }
}
