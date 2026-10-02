import UIKit
import SwiftUI
import UniformTypeIdentifiers
import LLMTranslateKit

/// Раздел 10.3 ТЗ: NSExtensionActivationRule ограничивает вход одним
/// изображением (см. Info.plist), поэтому здесь всегда ровно один
/// attachment. Показывает свой UI немедленно, без экранов подтверждения.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        Task { await loadImageAndPresent() }
    }

    private func loadImageAndPresent() async {
        guard
            let item = extensionContext?.inputItems.first as? NSExtensionItem,
            let attachments = item.attachments,
            let provider = attachments.first(where: {
                $0.hasItemConformingToTypeIdentifier(UTType.image.identifier)
            })
        else {
            close()
            return
        }

        do {
            let data = try await Self.loadImageData(from: provider)
            presentResult(imageData: data)
        } catch {
            close()
        }
    }

    /// Сначала сырые байты файла (JPEG/HEIC на несколько МБ) — без
    /// декодирования: у расширения жёсткий лимит памяти, а `UIImage` из
    /// «Фото» на 12 Мп это ~48 МБ растра плюс кодирование огромного PNG.
    private static func loadImageData(from provider: NSItemProvider) async throws -> Data {
        let raw: Data? = await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
        if let raw, !raw.isEmpty { return raw }
        return try await loadImageDataViaItem(from: provider)
    }

    private static func loadImageDataViaItem(from provider: NSItemProvider) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { item, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                switch item {
                case let data as Data:
                    continuation.resume(returning: data)
                case let url as URL:
                    do {
                        continuation.resume(returning: try Data(contentsOf: url))
                    } catch {
                        continuation.resume(throwing: error)
                    }
                case let image as UIImage:
                    // Уже распакованное изображение: хотя бы не кодировать
                    // его в полном размере.
                    if let data = downscaledJPEG(image, maxLongSide: 2048) {
                        continuation.resume(returning: data)
                    } else {
                        continuation.resume(throwing: TranslationError.other(code: nil, message: "не удалось прочитать изображение"))
                    }
                default:
                    continuation.resume(throwing: TranslationError.other(code: nil, message: "неизвестный формат вложения"))
                }
            }
        }
    }

    private static func downscaledJPEG(_ image: UIImage, maxLongSide: CGFloat) -> Data? {
        let longSide = max(image.size.width, image.size.height) * image.scale
        let shrink = min(1, maxLongSide / max(longSide, 1))
        let target = CGSize(width: image.size.width * image.scale * shrink, height: image.size.height * image.scale * shrink)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format)
            .jpegData(withCompressionQuality: 0.9) { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
    }

    private func presentResult(imageData: Data) {
        let rootView = ShareRootView(imageData: imageData) { [weak self] in
            self?.close()
        }
        let hosting = UIHostingController(rootView: rootView)
        addChild(hosting)
        hosting.view.frame = view.bounds
        hosting.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(hosting.view)
        hosting.didMove(toParent: self)
    }

    private func close() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}

private struct ShareRootView: View {
    let imageData: Data
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            ScreenshotRegionsView(originalImageData: imageData, appGroupSuiteName: SharedIdentifiers.appGroup)
                .navigationTitle("Перевод")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Готово", action: onDone)
                    }
                }
        }
    }
}
