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

    private static func loadImageData(from provider: NSItemProvider) async throws -> Data {
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
                    if let data = image.pngData() {
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
            ImageTranslationView(originalImageData: imageData, appGroupSuiteName: SharedIdentifiers.appGroup)
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
