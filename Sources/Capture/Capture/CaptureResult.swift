import AppKit

struct CaptureResult {
    let image: CGImage
    /// Global CG points: origin at the primary display's top-left, y increasing down.
    let rect: CGRect
    let displayID: CGDirectDisplayID
    let scale: CGFloat

    func llmImage(maxSide: Int) -> (png: Data, size: CGSize) {
        precondition(maxSide >= 1)
        let longestSide = CGFloat(max(image.width, image.height))
        let factor = min(1, CGFloat(maxSide) / longestSide)
        let width = max(1, Int((CGFloat(image.width) * factor).rounded(.down)))
        let height = max(1, Int((CGFloat(image.height) * factor).rounded(.down)))
        let output: CGImage
        if width == image.width && height == image.height {
            output = image
        } else {
            guard let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { preconditionFailure("Unable to allocate resized capture") }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            guard let resized = context.makeImage() else {
                preconditionFailure("Unable to resize capture")
            }
            output = resized
        }
        guard let png = NSBitmapImageRep(cgImage: output).representation(using: .png, properties: [:]) else {
            preconditionFailure("Unable to encode capture as PNG")
        }
        return (png, CGSize(width: width, height: height))
    }

    /// `pixel` uses the sent image's top-left origin; `sentImageSize` is returned by llmImage.
    func screenPoint(for pixel: CGPoint, sentImageSize: CGSize) -> CGPoint {
        precondition(sentImageSize.width > 0 && sentImageSize.height > 0)
        return CGPoint(
            x: rect.minX + pixel.x * rect.width / sentImageSize.width,
            y: rect.minY + pixel.y * rect.height / sentImageSize.height
        )
    }
}
