import SwiftUI
import ImageIO

// Artwork has its own unauthenticated session. CDN redirects are allowed only between
// known artwork hosts; account credentials can never enter this session.
final class ArtworkRedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let url = request.url, NetworkPolicy.artwork(url) else { completionHandler(nil); return }
        completionHandler(request)
    }
}

enum LocalArtwork {
    static let glow: NSImage? = Bundle.main.path(forResource: "track-glow", ofType: "png").flatMap(NSImage.init(contentsOfFile:))
    static let previewCover: NSImage? = Bundle.main.path(forResource: "reference-cover", ofType: "png").flatMap(NSImage.init(contentsOfFile:))
}

@MainActor
final class ArtworkCache {
    static let shared = ArtworkCache()
    private let cache = NSCache<NSURL, NSImage>()
    private let session: URLSession
    init() {
        cache.totalCostLimit = 8 * 1024 * 1024
        cache.countLimit = 80
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil; config.timeoutIntervalForRequest = 15
        session = URLSession(configuration: config, delegate: ArtworkRedirectPolicy(), delegateQueue: nil)
    }
    func image(_ url: URL) async -> NSImage? {
        guard NetworkPolicy.artwork(url) else { return nil }
        if let image = cache.object(forKey: url as NSURL) { return image }
        do {
            let (data, response) = try await session.data(from: url)
            try Task.checkCancellation()
            guard (response as? HTTPURLResponse)?.statusCode == 200, data.count < 4_000_000 else { return nil }
            let cgImage = await Task.detached(priority: .utility) {
                guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil as CGImage? }
                return CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 240,
                    kCGImageSourceCreateThumbnailWithTransform: true
                ] as CFDictionary)
            }.value
            try Task.checkCancellation()
            guard let cgImage else { return nil }
            let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            cache.setObject(image, forKey: url as NSURL, cost: cgImage.bytesPerRow * cgImage.height)
            return image
        } catch { return nil }
    }
    func clear() { cache.removeAllObjects() }
}

struct CoverArt: View {
    let uri: String?
    var size: CGFloat = 84
    var demo = false
    @State private var image: NSImage?
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(Theme.surface)
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else if demo, let cover = LocalArtwork.previewCover {
                Image(nsImage: cover).resizable().scaledToFill()
            } else {
                Image(systemName: "music.note").font(.system(size: size * 0.3, weight: .light)).foregroundStyle(Theme.muted)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size > 60 ? 10 : 6))
        .overlay(RoundedRectangle(cornerRadius: size > 60 ? 10 : 6).strokeBorder(.white.opacity(0.14), lineWidth: 1))
        .accessibilityHidden(true)
        .task(id: uri) {
            image = nil
            guard let url = ArtworkURL.make(uri, size: 200) else { return }
            image = await ArtworkCache.shared.image(url)
        }
    }
}
