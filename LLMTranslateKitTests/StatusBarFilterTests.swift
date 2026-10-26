import CoreGraphics
import XCTest
@testable import LLMTranslateKit

final class StatusBarFilterTests: XCTestCase {
    private let screenshot = CGSize(width: 1290, height: 2796) // iPhone 16 Pro Max и подобные

    func test_phoneScreenshot_dropsClockAndBattery_keepsContent() {
        let clock = TextRegion(id: 0, rect: CGRect(x: 0.1, y: 0.02, width: 0.12, height: 0.015))
        let title = TextRegion(id: 1, rect: CGRect(x: 0.3, y: 0.09, width: 0.4, height: 0.02))
        let kept = StatusBarFilter.removingStatusBar([clock, title], imageSize: screenshot)
        XCTAssertEqual(kept.map(\.id), [1])
    }

    func test_regionCrossingTheStrip_isKept() {
        let tall = TextRegion(id: 0, rect: CGRect(x: 0.1, y: 0.04, width: 0.5, height: 0.05))
        XCTAssertEqual(StatusBarFilter.removingStatusBar([tall], imageSize: screenshot).count, 1)
    }

    func test_photoOrCroppedImage_isUntouched() {
        let top = TextRegion(id: 0, rect: CGRect(x: 0.1, y: 0.01, width: 0.3, height: 0.02))
        XCTAssertEqual(StatusBarFilter.removingStatusBar([top], imageSize: CGSize(width: 4032, height: 3024)).count, 1)
        XCTAssertEqual(StatusBarFilter.removingStatusBar([top], imageSize: CGSize(width: 1058, height: 215)).count, 1)
        XCTAssertEqual(StatusBarFilter.removingStatusBar([top], imageSize: CGSize(width: 1290, height: 1600)).count, 1)
    }

    func test_knownScreenshotSizes_areRecognized() {
        for size in [CGSize(width: 1290, height: 2796), CGSize(width: 1179, height: 2556), CGSize(width: 1170, height: 2532), CGSize(width: 1206, height: 2622)] {
            XCTAssertTrue(StatusBarFilter.isFullScreenPhoneScreenshot(size), "\(size)")
        }
    }
}
