#if canImport(UIKit)
import Photos

/// Раздел 10.4 ТЗ: последний элемент смарт-альбома «Снимки экрана» через
/// `PHPhotoLibrary`. Доступ к «Фото» запрашивается здесь, по факту первого
/// вызова E2/E3 — не на онбординге (раздел 13 ТЗ).
public enum ScreenshotFetcher {
    public static func fetchLatestScreenshotData() async throws -> Data {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized || status == .limited else {
            throw TranslationError.noPhotoAccess
        }

        let albums = PHAssetCollection.fetchAssetCollections(
            with: .smartAlbum, subtype: .smartAlbumScreenshots, options: nil
        )
        guard let album = albums.firstObject else {
            throw TranslationError.noScreenshotsFound
        }

        let fetchOptions = PHFetchOptions()
        fetchOptions.fetchLimit = 1
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let assets = PHAsset.fetchAssets(in: album, options: fetchOptions)
        guard let asset = assets.firstObject else {
            throw TranslationError.noScreenshotsFound
        }

        return try await withCheckedThrowingContinuation { continuation in
            let requestOptions = PHImageRequestOptions()
            // Синхронно — гарантирует ровно один вызов колбэка (иначе
            // requestImageDataAndOrientation может дважды прогрессивно
            // отдать данные при iCloud-фото, что ломает continuation).
            requestOptions.isSynchronous = true
            requestOptions.deliveryMode = .highQualityFormat
            requestOptions.isNetworkAccessAllowed = true
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: requestOptions) { data, _, _, _ in
                if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: TranslationError.other(code: nil, message: "не удалось прочитать данные скриншота"))
                }
            }
        }
    }
}
#endif
