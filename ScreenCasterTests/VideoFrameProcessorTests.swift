import XCTest
@testable import ScreenCaster

final class VideoFrameProcessorTests: XCTestCase {

    // MARK: - uprightTransform

    func testUpOrientationReturnsIdentity() {
        let t = VideoFrameProcessor.uprightTransform(
            for: .up, sourceWidth: 1920, sourceHeight: 1080
        )
        XCTAssertTrue(t.isIdentity)
    }

    func testLeftOrientationProducesSwappedDimensions() {
        let w: CGFloat = 1080
        let h: CGFloat = 1920
        let t = VideoFrameProcessor.uprightTransform(
            for: .left, sourceWidth: w, sourceHeight: h
        )
        XCTAssertFalse(t.isIdentity)

        let result = CGRect(x: 0, y: 0, width: w, height: h).applying(t)
        XCTAssertEqual(result.width, h, accuracy: 0.001)
        XCTAssertEqual(result.height, w, accuracy: 0.001)
        XCTAssertEqual(result.origin.x, 0, accuracy: 0.001)
        XCTAssertEqual(result.origin.y, 0, accuracy: 0.001)
    }

    func testRightOrientationProducesSwappedDimensions() {
        let w: CGFloat = 1080
        let h: CGFloat = 1920
        let t = VideoFrameProcessor.uprightTransform(
            for: .right, sourceWidth: w, sourceHeight: h
        )
        XCTAssertFalse(t.isIdentity)

        let result = CGRect(x: 0, y: 0, width: w, height: h).applying(t)
        XCTAssertEqual(result.width, h, accuracy: 0.001)
        XCTAssertEqual(result.height, w, accuracy: 0.001)
        XCTAssertEqual(result.origin.x, 0, accuracy: 0.001)
        XCTAssertEqual(result.origin.y, 0, accuracy: 0.001)
    }

    func testDownOrientationPreservesDimensions() {
        let w: CGFloat = 1920
        let h: CGFloat = 1080
        let t = VideoFrameProcessor.uprightTransform(
            for: .down, sourceWidth: w, sourceHeight: h
        )
        XCTAssertFalse(t.isIdentity)

        let result = CGRect(x: 0, y: 0, width: w, height: h).applying(t)
        XCTAssertEqual(result.width, w, accuracy: 0.001)
        XCTAssertEqual(result.height, h, accuracy: 0.001)
    }

    func testLeftAndRightProduceDifferentTransforms() {
        let w: CGFloat = 1080
        let h: CGFloat = 1920
        let left = VideoFrameProcessor.uprightTransform(
            for: .left, sourceWidth: w, sourceHeight: h
        )
        let right = VideoFrameProcessor.uprightTransform(
            for: .right, sourceWidth: w, sourceHeight: h
        )
        // Both produce the same bounding box but different point mappings
        XCTAssertNotEqual(left.b, right.b)
    }

    func testSquareSourceIdenticalBounds() {
        let s: CGFloat = 1080
        for orientation: CGImagePropertyOrientation in [.left, .right, .down] {
            let t = VideoFrameProcessor.uprightTransform(
                for: orientation, sourceWidth: s, sourceHeight: s
            )
            let result = CGRect(x: 0, y: 0, width: s, height: s).applying(t)
            XCTAssertEqual(result.width, s, accuracy: 0.001)
            XCTAssertEqual(result.height, s, accuracy: 0.001)
        }
    }

    // MARK: - fitTransform

    func testSameSizeReturnsNil() {
        let result = VideoFrameProcessor.fitTransform(
            contentSize: CGSize(width: 1920, height: 1080),
            canvasSize: CGSize(width: 1920, height: 1080)
        )
        XCTAssertNil(result)
    }

    func testPortraitOnLandscapeCanvasPillarbox() {
        // Portrait content on landscape canvas → pillarbox (black bars on sides)
        let t = VideoFrameProcessor.fitTransform(
            contentSize: CGSize(width: 1080, height: 1920),
            canvasSize: CGSize(width: 1920, height: 1080)
        )!

        let result = CGRect(x: 0, y: 0, width: 1080, height: 1920).applying(t)
        // Scale limited by height: 1080 / 1920 = 0.5625
        XCTAssertEqual(result.height, 1080, accuracy: 0.001)
        XCTAssertEqual(result.width, 607.5, accuracy: 0.001)
        // Centered horizontally
        XCTAssertEqual(result.origin.x, 656.25, accuracy: 0.001)
        XCTAssertEqual(result.origin.y, 0, accuracy: 0.001)
    }

    func testLandscapeOnPortraitCanvasLetterbox() {
        // Landscape content on portrait canvas → letterbox (black bars top/bottom)
        let t = VideoFrameProcessor.fitTransform(
            contentSize: CGSize(width: 1920, height: 1080),
            canvasSize: CGSize(width: 1080, height: 1920)
        )!

        let result = CGRect(x: 0, y: 0, width: 1920, height: 1080).applying(t)
        // Scale limited by width: 1080 / 1920 = 0.5625
        XCTAssertEqual(result.width, 1080, accuracy: 0.001)
        XCTAssertEqual(result.height, 607.5, accuracy: 0.001)
        // Centered vertically
        XCTAssertEqual(result.origin.x, 0, accuracy: 0.001)
        XCTAssertEqual(result.origin.y, 656.25, accuracy: 0.001)
    }

    func testLargerContentScaledDownExactFit() {
        // 2x canvas but same aspect ratio → scaled to fit exactly
        let t = VideoFrameProcessor.fitTransform(
            contentSize: CGSize(width: 3840, height: 2160),
            canvasSize: CGSize(width: 1920, height: 1080)
        )!

        let result = CGRect(x: 0, y: 0, width: 3840, height: 2160).applying(t)
        XCTAssertEqual(result.width, 1920, accuracy: 0.001)
        XCTAssertEqual(result.height, 1080, accuracy: 0.001)
        XCTAssertEqual(result.origin.x, 0, accuracy: 0.001)
        XCTAssertEqual(result.origin.y, 0, accuracy: 0.001)
    }

    func testSmallerContentScaledUp() {
        // Smaller content with same aspect ratio → scaled up
        let t = VideoFrameProcessor.fitTransform(
            contentSize: CGSize(width: 960, height: 540),
            canvasSize: CGSize(width: 1920, height: 1080)
        )!

        let result = CGRect(x: 0, y: 0, width: 960, height: 540).applying(t)
        XCTAssertEqual(result.width, 1920, accuracy: 0.001)
        XCTAssertEqual(result.height, 1080, accuracy: 0.001)
    }
}
