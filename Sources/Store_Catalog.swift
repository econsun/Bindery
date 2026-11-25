import Foundation

enum CatalogStore {
    static let markerName = "store.json"
    static let catalogName = "catalog.json"
    static let directoryName = ".bindery"

    private static let lock = NSLock()

    // MARK: - Locations

    static func metadataDirectory(for storeURL: URL) -> URL {
        storeURL.appendingPathComponent(directoryName, isDirectory: true)
    }

    static func markerURL(for storeURL: URL) -> URL {
        metadataDirectory(for: storeURL).appendingPathComponent(markerName)
    }

    static func catalogURL(for storeURL: URL) -> URL {
        metadataDirectory(for: storeURL).appendingPathComponent(catalogName)
    }

    static var cacheDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Bindery", isDirectory: true)
            .appendingPathComponent("Catalogs", isDirectory: true)
    }

    static func cacheURL(for storeID: UUID) -> URL {
        cacheDirectory.appendingPathComponent("\(storeID.uuidString).json")
    }

    // MARK: - Store marker

    @discardableResult
    static func ensureStore(at storeURL: URL, label: String = "", preferredID: UUID? = nil) throws -> StoreMarker {
        try FileManager.default.createDirectory(
            at: metadataDirectory(for: storeURL),
            withIntermediateDirectories: true
        )
        let url = markerURL(for: storeURL)
        if let data = try? Data(contentsOf: url),
           let marker = try? decoder.decode(StoreMarker.self, from: data) {
            return marker
        }
        let marker = StoreMarker(
            storeID: preferredID ?? UUID(),
            label: label.isEmpty ? storeURL.lastPathComponent : label
        )
        try write(marker, to: url)
        return marker
    }

    static func readMarker(for storeURL: URL) -> StoreMarker? {
        guard let data = try? Data(contentsOf: markerURL(for: storeURL)) else { return nil }
        return try? decoder.decode(StoreMarker.self, from: data)
    }

    static func writeMarker(_ marker: StoreMarker, for storeURL: URL) throws {
        try FileManager.default.createDirectory(
            at: metadataDirectory(for: storeURL),
            withIntermediateDirectories: true
        )
        try write(marker, to: markerURL(for: storeURL))
    }

    // MARK: - Catalog

    static func readCatalog(for storeURL: URL, storeID: UUID) -> StoreCatalog {
        guard let data = try? Data(contentsOf: catalogURL(for: storeURL)),
              let catalog = try? decoder.decode(StoreCatalog.self, from: data) else {
            return StoreCatalog(storeID: storeID)
        }
        return catalog
    }

    static func writeCatalog(_ catalog: StoreCatalog, for storeURL: URL) throws {
        try FileManager.default.createDirectory(
            at: metadataDirectory(for: storeURL),
            withIntermediateDirectories: true
        )
        var copy = catalog
        copy.format = 2
        copy.updatedAt = Date()
        try write(copy, to: catalogURL(for: storeURL))
        try cacheCatalog(copy)
    }

    /// Read-modify-write with a process-wide lock. The app is the only writer,
    /// but backup runs and scans can overlap.
    @discardableResult
    static func updateCatalog(
        for storeURL: URL,
        storeID: UUID,
        mutate: (inout StoreCatalog) -> Void
    ) throws -> StoreCatalog {
        lock.lock()
        defer { lock.unlock() }
        var catalog = readCatalog(for: storeURL, storeID: storeID)
        mutate(&catalog)
        catalog.storeID = storeID
        catalog.revision += 1
        try writeCatalog(catalog, for: storeURL)
        return catalog
    }

    /// Merges a scan result into the current catalog without dropping records
    /// that a concurrent backup may have added while the scan was walking.
    static func mergeCatalog(_ scanned: StoreCatalog, for storeURL: URL, storeID: UUID) throws -> StoreCatalog {
        lock.lock()
        defer { lock.unlock() }
        var current = readCatalog(for: storeURL, storeID: storeID)
        current.storeID = storeID
        var byID: [String: SnapshotRecord] = [:]
        for record in current.snapshots { byID[record.id] = record }
        for record in scanned.snapshots { byID[record.id] = record }
        current.snapshots = Array(byID.values).sorted { $0.capturedAt > $1.capturedAt }
        current.externals = scanned.externals
        current.revision += 1
        try writeCatalog(current, for: storeURL)
        return current
    }

    // MARK: - Offline cache

    static func cacheCatalog(_ catalog: StoreCatalog) throws {
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try write(catalog, to: cacheURL(for: catalog.storeID))
    }

    static func cachedCatalog(for storeID: UUID) -> StoreCatalog? {
        guard let data = try? Data(contentsOf: cacheURL(for: storeID)) else { return nil }
        return try? decoder.decode(StoreCatalog.self, from: data)
    }

    // MARK: - Category paths

    static func sanitizedCategoryPath(_ raw: String) -> String {
        let parts = raw
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { BackupFilenameFormat.sanitize(String($0)) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? "Uncategorized" : parts.joined(separator: "/")
    }

    static func categoryURL(for storeURL: URL, categoryPath: String) -> URL {
        let parts = sanitizedCategoryPath(categoryPath).split(separator: "/").map(String.init)
        return parts.reduce(storeURL) { url, part in
            url.appendingPathComponent(part, isDirectory: true)
        }
    }

    static func relativePath(categoryPath: String, fileName: String) -> String {
        sanitizedCategoryPath(categoryPath) + "/" + fileName
    }

    static func snapshotURL(storePath: String, relativePath: String) -> URL {
        URL(fileURLWithPath: storePath).appendingPathComponent(relativePath)
    }

    // MARK: - Scan helpers

    static func isIgnored(_ name: String) -> Bool {
        if name == directoryName || name == ".DS_Store" || name == "__MACOSX" { return true }
        if name.hasPrefix(".") { return true }
        if name == "Legacy" || name == "_Legacy" { return true }
        return false
    }

    static func fileSize(at url: URL) -> Int64? {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .totalFileAllocatedSizeKey]),
              values.isRegularFile == true else { return nil }
        return Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
    }

    // MARK: - JSON

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }()

    private static func write<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try encoder.encode(value)
        try data.write(to: url, options: .atomic)
    }
}
