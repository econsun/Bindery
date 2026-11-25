import CryptoKit
import Foundation

struct SnapshotDigests: Equatable {
    var content: String?
    var artifact: String?
}

enum DigestEngine {
    /// SHA-256 of a single file, streamed so large snapshots do not load into memory.
    static func fileDigest(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while autoreleasepool(invoking: {
            let data = handle.readData(ofLength: 1_048_576)
            if data.isEmpty { return false }
            hasher.update(data: data)
            return true
        }) {}
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Merkle-style digest over relative paths and file hashes. Folder metadata
    /// is intentionally omitted so copying a folder does not change its identity.
    static func treeDigest(_ root: URL) throws -> String {
        let manager = FileManager.default
        let keys: [URLResourceKey] = [.isRegularFileKey]
        guard let enumerator = manager.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsPackageDescendants]
        ) else {
            return try fileDigest(root)
        }

        var entries: [(path: String, digest: String)] = []
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile == true else { continue }
            let path = relativePath(of: url, in: root)
            entries.append((path, try fileDigest(url)))
        }
        entries.sort { $0.path < $1.path }

        var hasher = SHA256()
        hasher.update(data: Data("bindery-tree-v1\n".utf8))
        for entry in entries {
            hasher.update(data: Data(entry.path.utf8))
            hasher.update(data: Data([0]))
            hasher.update(data: Data(entry.digest.utf8))
            hasher.update(data: Data([0x0a]))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func digests(for url: URL, packaging: SnapshotPackaging) -> SnapshotDigests {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return SnapshotDigests()
        }
        switch packaging {
        case .file:
            let digest = try? fileDigest(url)
            return SnapshotDigests(content: digest, artifact: digest)
        case .zip:
            return SnapshotDigests(content: nil, artifact: try? fileDigest(url))
        case .folder:
            return SnapshotDigests(content: try? treeDigest(url), artifact: nil)
        }
    }

    static func matches(_ record: SnapshotRecord, url: URL) -> Bool {
        guard let expected = record.contentDigest ?? record.artifactDigest else { return false }
        switch record.packaging {
        case .folder:
            guard (try? treeDigest(url)) == expected else { return false }
            return true
        case .zip, .file:
            guard (try? fileDigest(url)) == expected else { return false }
            return true
        }
    }

    private static func relativePath(of url: URL, in root: URL) -> String {
        let prefix = root.standardizedFileURL.path.hasSuffix("/")
            ? root.standardizedFileURL.path
            : root.standardizedFileURL.path + "/"
        let path = url.standardizedFileURL.path
        return path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : url.lastPathComponent
    }
}
