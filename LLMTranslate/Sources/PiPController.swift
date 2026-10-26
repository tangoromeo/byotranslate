import AVFoundation
import AVKit
import CoreMedia
import LLMTranslateKit
import UIKit

/// B8: PiP-«язычок». Окно показывает статичную карточку; по «развернуть» система
/// возвращает приложение на экран, а мы берём кадр трансляции, снятый чуть ДО
/// нажатия (`FrameRingBuffer`), и открываем обычный экран перевода.
///
/// Спайк (M0): события пишутся в `live-debug.log` в App Group (только текст),
/// чтобы забрать их с устройства `devicectl`. Журнал убрать в M4.
@MainActor
final class PiPController: NSObject, ObservableObject {
    static let shared = PiPController()

    @Published private(set) var status = "не запущен"
    @Published private(set) var isActive = false

    private let displayLayer = AVSampleBufferDisplayLayer()
    private let hostView = UIView(frame: CGRect(x: 0, y: 0, width: 4, height: 4))
    private var pip: AVPictureInPictureController?
    private var timer: Timer?
    private var observations: [NSKeyValueObservation] = []
    private var lastReady: Bool?
    // Размер окна PiP определяется пропорцией кадра, а не его пикселями; сделать
    // окно «спрятанным» приложение не может. Очень вытянутая карточка даёт узкую
    // полоску вместо большого прямоугольника (предел пропорции у системы неизвестен — проверяем).
    private let size = CGSize(width: 960, height: 120)

    var framesDirectory: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: SharedIdentifiers.appGroup)?
            .appendingPathComponent("frames", isDirectory: true)
    }

    // MARK: - Запуск и остановка

    func prepare() {
        LiveDebugLog.write("host: prepare() вызван, pip уже есть: \(pip != nil)")
        guard pip == nil else { return }
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            update("PiP не поддерживается")
            return
        }
        do {
            // Без активной аудиосессии PiP для своего содержимого молча не стартует.
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            update("аудиосессия: \(error.localizedDescription)")
        }

        displayLayer.videoGravity = .resizeAspect
        displayLayer.frame = hostView.bounds
        hostView.layer.addSublayer(displayLayer)
        hostView.alpha = 0.02
        hostView.isUserInteractionEnabled = false
        // Слой должен быть в иерархии окна, иначе PiP не стартует.
        if let window = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.windows.first(where: \.isKeyWindow) }).first {
            window.addSubview(hostView)
        }

        let source = AVPictureInPictureController.ContentSource(
            sampleBufferDisplayLayer: displayLayer,
            playbackDelegate: self
        )
        let controller = AVPictureInPictureController(contentSource: source)
        controller.delegate = self
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.requiresLinearPlayback = true
        pip = controller
        // Спайк: что меняется, когда окно уводят к краю («язычок») и вытаскивают обратно.
        observations = [
            controller.observe(\.isPictureInPictureSuspended, options: [.new]) { _, change in
                LiveDebugLog.write("host: KVO suspended = \(change.newValue ?? false)")
            },
            controller.observe(\.isPictureInPictureActive, options: [.new]) { _, change in
                LiveDebugLog.write("host: KVO active = \(change.newValue ?? false)")
            },
            controller.observe(\.isPictureInPicturePossible, options: [.new]) { _, change in
                LiveDebugLog.write("host: KVO possible = \(change.newValue ?? false)")
            },
        ]
        enqueueCard()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.enqueueCard() }
        }
        update("готов (PiP возможен: \(controller.isPictureInPicturePossible))")
        LiveDebugLog.write("host: prepared, possible=\(controller.isPictureInPicturePossible)")
    }

    func start() {
        prepare()
        guard let pip else { return }
        LiveDebugLog.write("host: startPictureInPicture, possible=\(pip.isPictureInPicturePossible)")
        pip.startPictureInPicture()
    }

    func stop() {
        pip?.stopPictureInPicture()
    }

    // MARK: - Перевод кадра

    /// Общий путь для «развернуть» и тестовой кнопки: кадр до нажатия → экран результата.
    @discardableResult
    func presentLatestFrame() -> Bool {
        guard let directory = framesDirectory,
              let data = FrameRingBuffer(directory: directory).data(now: Date()) else {
            LiveDebugLog.write("host: кадров нет — переводить нечего")
            update("кадров нет: запущена ли трансляция?")
            return false
        }
        LiveDebugLog.write("host: берём кадр \(data.count / 1024) КБ для перевода")
        PendingImageTranslation.shared.present(imageData: data)
        return true
    }

    // MARK: - Карточка

    private func update(_ text: String) {
        status = text
    }

    private func enqueueCard() {
        let ready = displayLayer.sampleBufferRenderer.isReadyForMoreMediaData
        if ready != lastReady {
            lastReady = ready
            LiveDebugLog.write("host: слой готов принимать кадры = \(ready)")
        }
        guard let buffer = Self.makeCard(size: size, text: "Перевести экран ⤢") else { return }
        if displayLayer.sampleBufferRenderer.status == .failed {
            displayLayer.sampleBufferRenderer.flush()
        }
        displayLayer.sampleBufferRenderer.enqueue(buffer)
    }

    private static func makeCard(size: CGSize, text: String) -> CMSampleBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let attributes: [CFString: Any] = [kCVPixelBufferIOSurfacePropertiesKey: [:] as [String: Any]]
        guard CVPixelBufferCreate(nil, Int(size.width), Int(size.height), kCVPixelFormatType_32BGRA, attributes as CFDictionary, &pixelBuffer) == kCVReturnSuccess,
              let pixelBuffer else { return nil }
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(pixelBuffer), width: Int(size.width), height: Int(size.height),
            bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        UIGraphicsPushContext(context)
        UIColor(red: 0.10, green: 0.14, blue: 0.30, alpha: 1).setFill()
        context.fill(CGRect(origin: .zero, size: size))
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)
        let attributesText: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 56, weight: .semibold),
            .foregroundColor: UIColor.white,
        ]
        let string = text as NSString
        let textSize = string.size(withAttributes: attributesText)
        string.draw(at: CGPoint(x: (size.width - textSize.width) / 2, y: (size.height - textSize.height) / 2), withAttributes: attributesText)
        UIGraphicsPopContext()

        var format: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: pixelBuffer, formatDescriptionOut: &format) == noErr,
              let format else { return nil }
        var timing = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
            decodeTimeStamp: .invalid
        )
        var sampleBuffer: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(
            allocator: nil, imageBuffer: pixelBuffer, formatDescription: format, sampleTiming: &timing, sampleBufferOut: &sampleBuffer
        ) == noErr, let sampleBuffer else { return nil }
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true),
           CFArrayGetCount(attachments) > 0 {
            let dictionary = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(
                dictionary,
                Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                Unmanaged.passUnretained(kCFBooleanTrue).toOpaque()
            )
        }
        return sampleBuffer
    }
}

// MARK: - Воспроизведение (содержимое статичное, кнопки не делают ничего)

extension PiPController: AVPictureInPictureSampleBufferPlaybackDelegate {
    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, setPlaying playing: Bool) {
        LiveDebugLog.write("host: setPlaying(\(playing))")
    }

    nonisolated func pictureInPictureControllerTimeRangeForPlayback(_ pictureInPictureController: AVPictureInPictureController) -> CMTimeRange {
        CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
    }

    nonisolated func pictureInPictureControllerIsPlaybackPaused(_ pictureInPictureController: AVPictureInPictureController) -> Bool {
        false
    }

    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, didTransitionToRenderSize newRenderSize: CMVideoDimensions) {
        LiveDebugLog.write("host: размер окна PiP \(newRenderSize.width)x\(newRenderSize.height)")
    }

    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, skipByInterval skipInterval: CMTime, completion completionHandler: @escaping @Sendable () -> Void) {
        completionHandler()
    }
}

// MARK: - События PiP

extension PiPController: AVPictureInPictureControllerDelegate {
    nonisolated func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        LiveDebugLog.write("host: PiP willStart")
    }

    nonisolated func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        LiveDebugLog.write("host: PiP didStart")
        Task { @MainActor in
            self.isActive = true
            self.update("окно PiP показано")
        }
    }

    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: any Error) {
        LiveDebugLog.write("host: PiP НЕ стартовал: \(error.localizedDescription)")
        Task { @MainActor in self.update("PiP не стартовал: \(error.localizedDescription)") }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        LiveDebugLog.write("host: PiP didStop")
        Task { @MainActor in
            self.isActive = false
            self.update("окно PiP закрыто")
        }
    }

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping @Sendable (Bool) -> Void
    ) {
        LiveDebugLog.write("host: RESTORE (нажали «развернуть»)")
        Task { @MainActor in
            self.presentLatestFrame()
            completionHandler(true)
        }
    }
}
