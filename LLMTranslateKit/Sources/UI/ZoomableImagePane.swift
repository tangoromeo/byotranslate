#if canImport(UIKit)
import SwiftUI
import UIKit

/// Скриншот со слоем поверх (рамки/плашки), который можно увеличивать щипком
/// и двигать пальцем. Зум — через размер вёрстки, а не через масштаб готовой
/// картинки: плашки и их шрифты пересчитываются от нового размера и остаются
/// чёткими. Точка под пальцами при щипке остаётся на месте.
struct ZoomableImagePane<Layer: View>: View {
    let image: UIImage
    @ViewBuilder let layer: () -> Layer

    private static var maxZoom: CGFloat { 5 }

    @State private var zoom: CGFloat = 1
    @State private var offset: CGPoint = .zero
    @State private var position = ScrollPosition()
    /// Состояние на начало текущего щипка; `nil` — щипка нет.
    @State private var pinchStart: (zoom: CGFloat, offset: CGPoint)?

    var body: some View {
        GeometryReader { geometry in
            let viewport = geometry.size
            let base = fitSize(in: viewport)
            let content = CGSize(width: base.width * zoom, height: base.height * zoom)
            ScrollView([.horizontal, .vertical], showsIndicators: false) {
                Image(uiImage: image)
                    .resizable()
                    .frame(width: content.width, height: content.height)
                    .overlay { layer() }
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .frame(width: max(content.width, viewport.width), height: max(content.height, viewport.height))
            }
            .scrollPosition($position)
            .scrollBounceBehavior(.basedOnSize)
            .onScrollGeometryChange(for: CGPoint.self) { $0.contentOffset } action: { _, new in offset = new }
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { value in pinch(value, viewport: viewport, base: base) }
                    .onEnded { _ in pinchStart = nil }
            )
        }
    }

    private func fitSize(in viewport: CGSize) -> CGSize {
        guard image.size.width > 0, image.size.height > 0, viewport.width > 0, viewport.height > 0 else { return .zero }
        let scale = min(viewport.width / image.size.width, viewport.height / image.size.height)
        return CGSize(width: image.size.width * scale, height: image.size.height * scale)
    }

    /// Поля вокруг картинки, пока она меньше области просмотра (она по центру).
    private func margin(content: CGSize, viewport: CGSize) -> CGPoint {
        CGPoint(x: max(0, (viewport.width - content.width) / 2), y: max(0, (viewport.height - content.height) / 2))
    }

    private func pinch(_ value: MagnifyGesture.Value, viewport: CGSize, base: CGSize) {
        guard base.width > 0, base.height > 0 else { return }
        let start = pinchStart ?? (zoom, offset)
        pinchStart = start

        let newZoom = min(max(start.zoom * value.magnification, 1), Self.maxZoom)
        let anchor = CGPoint(x: value.startAnchor.x * viewport.width, y: value.startAnchor.y * viewport.height)
        let oldContent = CGSize(width: base.width * start.zoom, height: base.height * start.zoom)
        let newContent = CGSize(width: base.width * newZoom, height: base.height * newZoom)
        let oldMargin = margin(content: oldContent, viewport: viewport)
        let newMargin = margin(content: newContent, viewport: viewport)

        // Какая доля картинки лежала под пальцами в начале щипка — туда же
        // ставим их после увеличения.
        let fractionX = (start.offset.x + anchor.x - oldMargin.x) / oldContent.width
        let fractionY = (start.offset.y + anchor.y - oldMargin.y) / oldContent.height
        zoom = newZoom
        position.scrollTo(
            x: max(0, fractionX * newContent.width + newMargin.x - anchor.x),
            y: max(0, fractionY * newContent.height + newMargin.y - anchor.y)
        )
    }
}
#endif
