import SwiftUI

/// Circular user avatar that loads a remote profile photo into local state
/// (ported from podchat).
///
/// `AsyncImage` is unreliable inside frequently re-evaluated chrome: each
/// rebuild creates a fresh `AsyncImage` that cancels the previous in-flight
/// download, so the photo can be stuck on the placeholder. Loading into
/// `@State`, seeded from a small in-memory cache, makes the image survive
/// rebuilds and render immediately once fetched.
struct UserAvatarView: View {
    private let photoURL: URL?
    private let size: CGFloat

    @State private var image: UIImage?

    init(photoURL: URL?, size: CGFloat = 32) {
        self.photoURL = photoURL
        self.size = size
        // Seed from cache so a rebuilt instance shows the photo without a flash.
        _image = State(initialValue: photoURL.flatMap { AvatarImageCache.shared.image(for: $0) })
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: size * 0.7))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: size, height: size)
            }
        }
        .task(id: photoURL) { await load() }
    }

    private func load() async {
        guard let photoURL else {
            image = nil
            return
        }
        if let cached = AvatarImageCache.shared.image(for: photoURL) {
            image = cached
            return
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: photoURL)
            guard let loaded = UIImage(data: data) else { return }
            AvatarImageCache.shared.store(loaded, for: photoURL)
            image = loaded
        } catch {
            // Leave the placeholder in place on failure.
        }
    }
}

/// Tiny in-memory cache of decoded avatar images, keyed by URL, so chrome
/// rebuilds and re-navigations don't refetch or flicker.
private final class AvatarImageCache {
    static let shared = AvatarImageCache()
    private let cache = NSCache<NSURL, UIImage>()

    func image(for url: URL) -> UIImage? { cache.object(forKey: url as NSURL) }
    func store(_ image: UIImage, for url: URL) { cache.setObject(image, forKey: url as NSURL) }
}
