import CoreGraphics

enum ScreenClamp {
    static func clamp(origin: CGPoint, size: CGSize, into rect: CGRect) -> CGPoint {
        let maxX = rect.maxX - size.width
        let maxY = rect.maxY - size.height
        return CGPoint(
            x: min(max(rect.minX, origin.x), maxX),
            y: min(max(rect.minY, origin.y), maxY)
        )
    }
}
