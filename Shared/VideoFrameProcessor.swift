import CoreImage

/// Pure-function helpers for rotating and fitting video frames
/// into a fixed-size landscape output canvas.
enum VideoFrameProcessor {

    /// Returns a CGAffineTransform that rotates content to upright orientation.
    ///
    /// - `.up` (portrait): identity — content is already upright.
    /// - `.left` / `.right` (landscape): rotation to correct orientation.
    /// - `.down`: 180° rotation.
    ///
    /// The resulting CIImage extent always starts at origin (0, 0).
    static func uprightTransform(
        for orientation: CGImagePropertyOrientation,
        sourceWidth w: CGFloat,
        sourceHeight h: CGFloat
    ) -> CGAffineTransform {
        switch orientation {
        case .left:
            // Device landscape (home-right): rotate 90° CW
            return CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: w)
        case .right:
            // Device landscape (home-left): rotate 90° CCW
            return CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: h, ty: 0)
        case .down:
            // Upside-down portrait: rotate 180°
            return CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: w, ty: h)
        default:
            return .identity
        }
    }

    /// Returns a CGAffineTransform that aspect-fits and centers `contentSize`
    /// within `canvasSize`, or `nil` when the sizes already match.
    ///
    /// Apply the returned transform to a CIImage, then render onto a
    /// pre-cleared (black) pixel buffer to get automatic pillarbox / letterbox bars.
    static func fitTransform(
        contentSize: CGSize,
        canvasSize: CGSize
    ) -> CGAffineTransform? {
        guard contentSize != canvasSize else { return nil }

        let scale = min(
            canvasSize.width / contentSize.width,
            canvasSize.height / contentSize.height
        )
        let scaledW = contentSize.width * scale
        let scaledH = contentSize.height * scale
        let offsetX = (canvasSize.width - scaledW) / 2
        let offsetY = (canvasSize.height - scaledH) / 2

        return CGAffineTransform(scaleX: scale, y: scale)
            .concatenating(CGAffineTransform(translationX: offsetX, y: offsetY))
    }
}
