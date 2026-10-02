#if canImport(UIKit)
import SwiftUI
import UIKit

/// Раздел B6 бэклога: результат для изображения — скриншот с областями
/// текста в трёх режимах.
/// - «Фрагменты»: области подсвечены, тап по области переводит только её и
///   показывает результат в шторке (этап 1).
/// - «Весь экран» (по умолчанию): перевод всех областей сразу поверх
///   оригинала полупрозрачными плашками — чтобы окинуть экран взглядом и
///   найти нужный пункт (этап 3); тап по плашке открывает ту же шторку.
///   Скриншот можно увеличивать щипком.
/// - «Текст»: прежний связный перевод всего снимка.
/// Если детектор ничего не нашёл, сразу показывается «Текст».
///
/// Используется из `ContentView` (E2/E3) и `LLMTranslateShareExt` (E1).
public struct ScreenshotRegionsView: View {
    private let originalImageData: Data
    private let appGroupSuiteName: String

    private enum Phase: Equatable {
        case detecting
        case ready([TextRegion])
    }

    private enum Mode: Hashable {
        case fragments, overlay, full
    }

    private struct SelectedFragment: Identifiable {
        let id: Int
        let imageData: Data
    }

    /// Непрозрачность фона плашки: оригинал под ней должен просвечивать
    /// (можно сверить место на экране), но не мешать читать перевод.
    private static let plaqueOpacity = 0.62
    /// Сдвиг плашки вниз относительно оригинала, в высотах строки: верх
    /// исходной надписи остаётся видимым, и обе читаются.
    private static let plaqueShift: CGFloat = 0.35

    @State private var phase: Phase = .detecting
    @State private var displayImage: UIImage?
    @State private var mode: Mode = .overlay
    @State private var selected: SelectedFragment?
    @StateObject private var overlay = RegionOverlayModel()

    public init(originalImageData: Data, appGroupSuiteName: String) {
        self.originalImageData = originalImageData
        self.appGroupSuiteName = appGroupSuiteName
    }

    public var body: some View {
        Group {
            switch phase {
            case .detecting:
                ProgressView { Text("Ищу текст…", bundle: .kit) }
            case let .ready(regions):
                if regions.isEmpty {
                    ImageTranslationView(originalImageData: originalImageData, appGroupSuiteName: appGroupSuiteName)
                } else {
                    VStack(spacing: 8) {
                        modePicker
                        content(regions)
                    }
                }
            }
        }
        .sheet(item: $selected) { fragment in
            NavigationStack {
                ImageTranslationView(originalImageData: fragment.imageData, appGroupSuiteName: appGroupSuiteName)
                    .navigationTitle(Text("Перевод", bundle: .kit))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button { selected = nil } label: { Text("Готово", bundle: .kit) }
                        }
                    }
            }
            .presentationDetents([.medium, .large])
        }
        // `id:` — как и в ImageTranslationView: ContentView держит cover
        // открытым между запусками, вью не пересоздаётся.
        .task(id: originalImageData) { await detect() }
        .onChange(of: mode) { _, newMode in
            if newMode == .overlay { startOverlay() }
        }
    }

    private var modePicker: some View {
        Picker(selection: $mode) {
            Text("Фрагменты", bundle: .kit).tag(Mode.fragments)
            Text("Весь экран", bundle: .kit).tag(Mode.overlay)
            Text("Текст", bundle: .kit).tag(Mode.full)
        } label: {
            EmptyView()
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
    }

    @ViewBuilder
    private func content(_ regions: [TextRegion]) -> some View {
        switch mode {
        case .full:
            ImageTranslationView(originalImageData: originalImageData, appGroupSuiteName: appGroupSuiteName)
        case .fragments:
            hint(Text("Нажмите на подсвеченный текст, чтобы перевести", bundle: .kit))
            imagePane { regionButtons(regions) }
        case .overlay:
            overlayStatus(regions)
            imagePane { plaques(regions) }
        }
    }

    private func hint(_ text: Text) -> some View {
        text
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.horizontal)
    }

    private func imagePane<Layer: View>(@ViewBuilder layer: @escaping () -> Layer) -> some View {
        Group {
            if let displayImage {
                ZoomableImagePane(image: displayImage, layer: layer)
                    .padding([.horizontal, .bottom])
            }
        }
    }

    // MARK: - Фрагменты

    private func regionButtons(_ regions: [TextRegion]) -> some View {
        GeometryReader { geometry in
            ForEach(regions) { region in
                let frame = tapFrame(for: region, in: geometry.size)
                Button { open(region) } label: {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.accentColor.opacity(0.18))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.accentColor, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)
                .accessibilityLabel(Text("Фрагмент текста", bundle: .kit))
            }
        }
    }

    /// Рамка в координатах показанной картинки. Совсем мелкие области
    /// расширяются до размера, в который можно попасть пальцем.
    private func tapFrame(for region: TextRegion, in size: CGSize) -> CGRect {
        let rect = displayRect(for: region, in: size)
        let width = max(rect.width, 28)
        let height = max(rect.height, 22)
        return CGRect(x: rect.midX - width / 2, y: rect.midY - height / 2, width: width, height: height)
    }

    private func displayRect(for region: TextRegion, in size: CGSize) -> CGRect {
        CGRect(
            x: region.rect.minX * size.width,
            y: region.rect.minY * size.height,
            width: region.rect.width * size.width,
            height: region.rect.height * size.height
        )
    }

    // MARK: - Плашки

    @ViewBuilder
    private func overlayStatus(_ regions: [TextRegion]) -> some View {
        if overlay.error != nil {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                if overlay.translations.isEmpty {
                    Text("Не удалось перевести", bundle: .kit)
                } else {
                    Text("Переведено не всё", bundle: .kit)
                }
                Button { retryOverlay(regions) } label: { Text("Повторить", bundle: .kit) }
                    .buttonStyle(.bordered)
            }
            .font(.footnote)
            .padding(.horizontal)
        } else if overlay.isRunning {
            HStack(spacing: 8) {
                ProgressView()
                Text("Перевожу…", bundle: .kit)
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        } else {
            hint(Text("Нажмите на плашку, чтобы увидеть подробности", bundle: .kit))
        }
    }

    private func plaques(_ regions: [TextRegion]) -> some View {
        GeometryReader { geometry in
            ForEach(regions) { region in
                let rect = displayRect(for: region, in: geometry.size).insetBy(dx: -2, dy: -1)
                if let text = overlay.translations[region.id] {
                    plaque(text: text, region: region, size: geometry.size, rect: rect)
                } else {
                    // Ждёт перевода или модель его не вернула — пунктир
                    // виден в обоих случаях, а по тапу область переводится
                    // отдельно (как в режиме «Фрагменты»).
                    let isPending = overlay.pendingIDs.contains(region.id)
                    Button { open(region) } label: {
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(
                                Color.accentColor.opacity(isPending ? 0.5 : 0.9),
                                style: StrokeStyle(lineWidth: 1, dash: [3, 2])
                            )
                    }
                    .buttonStyle(.plain)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                    .accessibilityLabel(Text("Фрагмент текста", bundle: .kit))
                }
            }
        }
    }

    private func plaque(text: String, region: TextRegion, size: CGSize, rect: CGRect) -> some View {
        let lineHeight = max(region.lineHeight * size.height, 1)
        let fontSize = max(8, lineHeight * 0.78)
        let lines = max(1, Int((rect.height / lineHeight).rounded()))
        let background = overlay.backgrounds[region.id]
        let alignment: Alignment = overlay.isTargetRTL ? .trailing : .leading
        let haloColor = (background?.color ?? Color(.systemBackground)).opacity(0.95)
        let centerY = min(rect.midY + lineHeight * Self.plaqueShift, size.height - rect.height / 2)
        return Button { open(region) } label: {
            Text(text)
                .font(.system(size: fontSize, weight: .medium))
                .foregroundStyle(background?.textColor ?? Color.primary)
                // Ореол цвета фона отделяет перевод от просвечивающего оригинала.
                .shadow(color: haloColor, radius: 1.2)
                .shadow(color: haloColor, radius: 1.2)
                .multilineTextAlignment(overlay.isTargetRTL ? .trailing : .leading)
                .lineLimit(lines)
                .minimumScaleFactor(0.5)
                .padding(.horizontal, 3)
                .frame(width: rect.width, height: rect.height, alignment: alignment)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill((background?.color ?? Color(.systemBackground)).opacity(Self.plaqueOpacity))
                )
        }
        .buttonStyle(.plain)
        .position(x: rect.midX, y: centerY)
        .accessibilityLabel(Text(text))
    }

    private func startOverlay() {
        guard case let .ready(regions) = phase else { return }
        let data = originalImageData
        let suite = appGroupSuiteName
        Task { await overlay.start(imageData: data, regions: regions, appGroupSuiteName: suite) }
    }

    private func retryOverlay(_ regions: [TextRegion]) {
        let data = originalImageData
        let suite = appGroupSuiteName
        Task { await overlay.retry(imageData: data, regions: regions, appGroupSuiteName: suite) }
    }

    // MARK: - Общее

    private func open(_ region: TextRegion) {
        let data = originalImageData
        Task {
            let crop = await Task.detached(priority: .userInitiated) {
                ScreenshotImageTools.cropData(from: data, region: region)
            }.value
            if let crop { selected = SelectedFragment(id: region.id, imageData: crop) }
        }
    }

    private func detect() async {
        phase = .detecting
        mode = .overlay
        selected = nil
        overlay.reset()
        displayImage = ImageDownsampler.uiImage(from: originalImageData, maxLongSide: ScreenshotImageTools.maxLongSide)

        let data = originalImageData
        let regions = await Task.detached(priority: .userInitiated) {
            ScreenshotImageTools.detectRegions(in: data)
        }.value
        phase = .ready(regions)
        // Плашки — режим по умолчанию: перевод стартует сразу, а не после
        // переключения сегмента (повторный вызов для того же кадра — no-op).
        if mode == .overlay, !regions.isEmpty { startOverlay() }
    }
}

/// Вне `View`, потому что `View` на iOS 18 изолирован на главном акторе, а
/// декодирование и Vision должны выполняться в фоне. Изображения только в
/// памяти (раздел 10.7 ТЗ), на диск ничего не пишется.
enum ScreenshotImageTools {
    /// Для кропов важно оригинальное разрешение (в общий запрос скриншот
    /// ужимается до 1024 px, мелкий текст при этом смазывается), но фото в
    /// 12 Мп целиком в память расширения тянуть незачем.
    /// В расширении («Поделиться») памяти мало: растр поменьше.
    static var maxLongSide: CGFloat {
        Bundle.main.bundlePath.hasSuffix(".appex") ? 2048 : 3000
    }

    static func detectRegions(in data: Data) -> [TextRegion] {
        guard let image = normalizedCGImage(from: data) else { return [] }
        return (try? TextRegionDetector.detectRegions(in: image)) ?? []
    }

    static func cropData(from data: Data, region: TextRegion) -> Data? {
        guard let image = normalizedCGImage(from: data) else { return nil }
        let rect = TextRegionGrouper.cropRect(
            for: region,
            imageSize: CGSize(width: image.width, height: image.height)
        )
        guard let part = image.cropping(to: rect) else { return nil }
        return UIImage(cgImage: part).pngData()
    }

    /// Ориентация «вверх», масштаб 1, ограничение по длинной стороне. Читается
    /// сразу в уменьшенном размере (ImageIO): полная распаковка фото в 12 Мп
    /// стоит ~48 МБ и убивала расширение «Поделиться».
    static func normalizedCGImage(from data: Data) -> CGImage? {
        ImageDownsampler.cgImage(from: data, maxLongSide: maxLongSide)
    }
}
#endif
