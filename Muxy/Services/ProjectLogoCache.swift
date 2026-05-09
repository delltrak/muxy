import AppKit
import Foundation

@MainActor
final class ProjectLogoCache {
    static let shared = ProjectLogoCache()

    private let cache: NSCache<NSString, NSImage>

    private init() {
        cache = NSCache()
        cache.countLimit = 64
    }

    func image(forFilename filename: String?) -> NSImage? {
        guard let filename, !filename.isEmpty else { return nil }
        let path = ProjectLogoStorage.logoPath(for: filename)
        let key = path as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        guard let raw = NSImage(contentsOfFile: path) else { return nil }
        let image = Self.trimmedToContent(raw) ?? raw
        cache.setObject(image, forKey: key)
        return image
    }

    func invalidate(filename: String?) {
        guard let filename else { return }
        let path = ProjectLogoStorage.logoPath(for: filename)
        cache.removeObject(forKey: path as NSString)
    }

    func invalidateAll() {
        cache.removeAllObjects()
    }

    private static func trimmedToContent(_ image: NSImage) -> NSImage? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return nil }

        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        let alphaThreshold: UInt8 = 16
        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1

        for y in 0..<height {
            for x in 0..<width {
                let alpha = pixels[(y * width + x) * bytesPerPixel + 3]
                guard alpha > alphaThreshold else { continue }
                if x < minX { minX = x }
                if y < minY { minY = y }
                if x > maxX { maxX = x }
                if y > maxY { maxY = y }
            }
        }

        guard maxX >= minX, maxY >= minY else { return nil }
        let trimmedWidth = maxX - minX + 1
        let trimmedHeight = maxY - minY + 1
        guard trimmedWidth < width || trimmedHeight < height else { return nil }
        let cropRect = CGRect(x: minX, y: minY, width: trimmedWidth, height: trimmedHeight)
        guard let cropped = cgImage.cropping(to: cropRect) else { return nil }
        return NSImage(cgImage: cropped, size: NSSize(width: trimmedWidth, height: trimmedHeight))
    }
}
