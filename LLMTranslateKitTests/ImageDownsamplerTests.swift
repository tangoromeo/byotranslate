import XCTest
import ImageIO
import UniformTypeIdentifiers
@testable import LLMTranslateKit

final class ImageDownsamplerTests: XCTestCase {
    private func pngData(width: Int, height: Int) -> Data {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        CGImageDestinationFinalize(destination)
        return data as Data
    }

    func test_largeImage_isShrunkToMaxLongSide_keepingAspect() throws {
        let image = try XCTUnwrap(ImageDownsampler.cgImage(from: pngData(width: 4032, height: 3024), maxLongSide: 1000))
        XCTAssertEqual(max(image.width, image.height), 1000)
        XCTAssertEqual(Double(image.width) / Double(image.height), 4032.0 / 3024.0, accuracy: 0.01)
    }

    func test_smallImage_isNotUpscaled() throws {
        let image = try XCTUnwrap(ImageDownsampler.cgImage(from: pngData(width: 200, height: 100), maxLongSide: 3000))
        XCTAssertEqual(image.width, 200)
        XCTAssertEqual(image.height, 100)
    }

    func test_portrait_usesHeightAsLongSide() throws {
        let image = try XCTUnwrap(ImageDownsampler.cgImage(from: pngData(width: 1290, height: 2796), maxLongSide: 1398))
        XCTAssertEqual(image.height, 1398)
        XCTAssertEqual(image.width, 645)
    }

    func test_pixelLongSide_readsWithoutDecoding() {
        XCTAssertEqual(ImageDownsampler.pixelLongSide(of: pngData(width: 640, height: 480)), 640)
    }

    func test_garbageData_returnsNil() {
        XCTAssertNil(ImageDownsampler.cgImage(from: Data([1, 2, 3, 4]), maxLongSide: 1000))
        XCTAssertNil(ImageDownsampler.pixelLongSide(of: Data([1, 2, 3, 4])))
    }
}
