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
        guard let image = NSImage(contentsOfFile: path) else { return nil }
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
}
