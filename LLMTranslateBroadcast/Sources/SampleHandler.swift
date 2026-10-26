import CoreImage
import CoreMedia
import Foundation
import ImageIO
import ReplayKit
import os

/// B8: расширение трансляции экрана. Принимает поток кадров и держит в папке
/// App Group несколько последних (`FrameRingBuffer`), чтобы приложение по
/// нажатию на PiP взяло кадр, снятый чуть ДО нажатия.
///
/// Лимит памяти расширения ~50 МБ: кадры не копятся (лишние сбрасываются сразу,
/// раз в `interval` берётся один), кодирование идёт в `autoreleasepool`, Kit не
/// линкуется — в таргет собираются только `FrameRingBuffer` и `SharedIdentifiers`.
final class SampleHandler: RPBroadcastSampleHandler {
    private static let interval: TimeInterval = 0.7
    private static let maxLongSide: CGFloat = 2048

    private let ring: FrameRingBuffer?
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private var lastAccepted = Date.distantPast
    private var acceptedCount = 0
    private var minAvailableMB = Int.max

    override init() {
        ring = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: SharedIdentifiers.appGroup)
            .map { FrameRingBuffer(directory: $0.appendingPathComponent("frames", isDirectory: true), capacity: 4) }
        super.init()
    }

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        ring?.removeAll()
        LiveDebugLog.write("extension: broadcastStarted, доступно памяти \(Self.availableMB()) МБ")
    }

    override func broadcastPaused() { LiveDebugLog.write("extension: paused") }
    override func broadcastResumed() { LiveDebugLog.write("extension: resumed") }

    override func broadcastFinished() {
        ring?.removeAll()
        LiveDebugLog.write("extension: broadcastFinished, кадров принято \(acceptedCount), минимум свободной памяти \(minAvailableMB) МБ")
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video else { return }
        let now = Date()
        // Остальные кадры сбрасываем сразу: очередь ReplayKit при отставании копит буферы
        // и расширение убивается по памяти.
        guard now.timeIntervalSince(lastAccepted) >= Self.interval else { return }
        lastAccepted = now

        autoreleasepool {
            guard let data = encode(sampleBuffer) else {
                LiveDebugLog.write("extension: не удалось закодировать кадр")
                return
            }
            do {
                try ring?.write(data, at: now)
                acceptedCount += 1
            } catch {
                LiveDebugLog.write("extension: запись кадра не удалась: \(error.localizedDescription)")
            }
            let available = Self.availableMB()
            minAvailableMB = min(minAvailableMB, available)
            if acceptedCount == 1 || acceptedCount % 25 == 0 {
                LiveDebugLog.write("extension: кадр #\(acceptedCount), \(data.count / 1024) КБ, свободно памяти \(available) МБ")
            }
        }
    }

    private func encode(_ sampleBuffer: CMSampleBuffer) -> Data? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
        var image = CIImage(cvPixelBuffer: pixelBuffer)
        // ReplayKit отдаёт кадр в «родной» ориентации дисплея; настоящая — во вложении буфера.
        if let raw = CMGetAttachment(sampleBuffer, key: RPVideoSampleOrientationKey as CFString, attachmentModeOut: nil) as? NSNumber,
           let orientation = CGImagePropertyOrientation(rawValue: raw.uint32Value) {
            image = image.oriented(orientation)
        }
        let longSide = max(image.extent.width, image.extent.height)
        if longSide > Self.maxLongSide {
            let scale = Self.maxLongSide / longSide
            image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }
        return context.jpegRepresentation(
            of: image,
            colorSpace: colorSpace,
            options: [CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): 0.8]
        )
    }

    private static func availableMB() -> Int { os_proc_available_memory() / 1_048_576 }
}
