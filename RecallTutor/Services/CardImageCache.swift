import CryptoKit
import Foundation
import UIKit

/// Disk cache for generated card illustrations, so revisiting a lecture
/// reuses its images instead of paying to generate them again.
///
/// Keyed by a hash of the card's text rather than its index: regenerating a
/// lecture reshuffles card order, and identical cards across conversations
/// should share one image. The key includes the aspect ratio so a change
/// there doesn't serve up stale letterboxed art.
///
/// Lives in Application Support, not Caches. The OS purges Caches under
/// storage pressure, and every purged image costs the user another image-API
/// call on the next visit.
enum CardImageCache {

    /// JPEG rather than PNG — these are soft-gradient illustrations, where
    /// lossless buys nothing and costs several times the bytes on disk.
    private static let compressionQuality: CGFloat = 0.85

    private static var directory: URL? {
        guard let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first else { return nil }
        let dir = base.appendingPathComponent("CardImages", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            guard (try? FileManager.default.createDirectory(
                at: dir, withIntermediateDirectories: true
            )) != nil else { return nil }
            // Regenerable from the API, so keep it out of iCloud/iTunes backups.
            var url = dir
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? url.setResourceValues(values)
        }
        return dir
    }

    private static func fileURL(forCardContent content: String) -> URL? {
        let digest = SHA256.hash(data: Data(content.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return directory?.appendingPathComponent("\(name).jpg")
    }

    static func image(forCardContent content: String) -> UIImage? {
        guard let url = fileURL(forCardContent: content),
              let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    static func store(_ image: UIImage, forCardContent content: String) {
        guard let url = fileURL(forCardContent: content),
              let data = image.jpegData(compressionQuality: compressionQuality) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
