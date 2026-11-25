import AppKit
import Foundation

enum PreviewImageStore {
    private static let cache = NSCache<NSString, NSImage>()

    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base
            .appendingPathComponent("Bindery", isDirectory: true)
            .appendingPathComponent("Previews", isDirectory: true)
    }

    static func importImage(from source: URL, bindingID: UUID) throws -> String {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let ext = source.pathExtension.isEmpty ? "png" : source.pathExtension.lowercased()
        let destination = directory.appendingPathComponent("\(bindingID.uuidString).\(ext)")
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: source, to: destination)
        cache.removeObject(forKey: destination.path as NSString)
        return destination.path
    }

    static func remove(path: String?) {
        guard let path, !path.isEmpty else { return }
        let url = URL(fileURLWithPath: path).standardizedFileURL
        guard url.path.hasPrefix(directory.standardizedFileURL.path + "/") else { return }
        try? FileManager.default.removeItem(at: url)
        cache.removeObject(forKey: path as NSString)
    }

    static func image(at path: String?) -> NSImage? {
        guard let path, !path.isEmpty else { return nil }
        if let cached = cache.object(forKey: path as NSString) { return cached }
        guard let image = NSImage(contentsOfFile: path) else { return nil }
        cache.setObject(image, forKey: path as NSString)
        return image
    }
}
