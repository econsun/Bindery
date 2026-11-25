import Foundation

// MARK: - Store

/// A physical place where snapshots live. The identity comes from
/// `.bindery/store.json`, not from the current path, so a store can be
/// renamed or moved to another volume.
struct StoreRef: Codable, Identifiable, Equatable {
    var id: UUID
    var path: String
    var label: String
    var bookmark: Data?
    var volumeUUID: String?
    var lastScanAt: Date?
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        path: String,
        label: String = "",
        bookmark: Data? = nil,
        volumeUUID: String? = nil,
        lastScanAt: Date? = nil,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.path = path
        self.label = label
        self.bookmark = bookmark
        self.volumeUUID = volumeUUID
        self.lastScanAt = lastScanAt
        self.isEnabled = isEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        path = try container.decodeIfPresent(String.self, forKey: .path) ?? ""
        label = try container.decodeIfPresent(String.self, forKey: .label) ?? ""
        bookmark = try container.decodeIfPresent(Data.self, forKey: .bookmark)
        volumeUUID = try container.decodeIfPresent(String.self, forKey: .volumeUUID)
        lastScanAt = try container.decodeIfPresent(Date.self, forKey: .lastScanAt)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
    }

    var name: String {
        if !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return label }
        let resolved = URL(fileURLWithPath: path).lastPathComponent
        return resolved.isEmpty ? "Store" : resolved
    }

    /// Returns a currently reachable path. A bookmark lets a renamed or
    /// remounted store be found even when its old path is gone.
    var reachablePath: String? {
        if !path.isEmpty, FileManager.default.fileExists(atPath: path) { return path }
        guard let bookmark else { return nil }
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: [.withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ), FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url.path
    }

    var isOnline: Bool { reachablePath != nil }

    var resolvedPath: String { reachablePath ?? path }

    mutating func refreshBookmark() {
        if let reachable = reachablePath { path = reachable }
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else { return }
        bookmark = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        volumeUUID = try? url.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString
    }
}

struct StoreMarker: Codable, Equatable {
    var format: Int
    var storeID: UUID
    var label: String
    var createdAt: Date

    init(storeID: UUID = UUID(), label: String = "", createdAt: Date = Date()) {
        self.format = 2
        self.storeID = storeID
        self.label = label
        self.createdAt = createdAt
    }
}

// MARK: - Snapshots

enum SnapshotPackaging: String, Codable, CaseIterable {
    case zip
    case folder
    case file

    var icon: String {
        switch self {
        case .zip: return "archivebox"
        case .folder: return "folder"
        case .file: return "doc"
        }
    }
}

enum SnapshotSourceKind: String, Codable {
    case file
    case folder
}

struct SnapshotRecord: Codable, Identifiable, Equatable {
    /// Permanent, human-readable identity: backup date + two letters.
    var id: String
    var bindingID: UUID?
    var bindingName: String
    var categoryPath: String
    var capturedAt: Date
    var projectDate: Date?
    var projectDateText: String?
    var relativePath: String
    var packaging: SnapshotPackaging
    var sourceName: String
    var sourcePath: String
    var sourceKind: SnapshotSourceKind
    var format: String
    var renderedName: String
    var byteCount: Int64?
    var contentDigest: String?
    var artifactDigest: String?
    var legacy: Bool
    var lastSeenAt: Date?
    var updatedAt: Date

    init(
        id: String,
        bindingID: UUID?,
        bindingName: String,
        categoryPath: String,
        capturedAt: Date,
        projectDate: Date? = nil,
        projectDateText: String? = nil,
        relativePath: String,
        packaging: SnapshotPackaging,
        sourceName: String,
        sourcePath: String,
        sourceKind: SnapshotSourceKind,
        format: String,
        renderedName: String,
        byteCount: Int64? = nil,
        contentDigest: String? = nil,
        artifactDigest: String? = nil,
        legacy: Bool = false,
        lastSeenAt: Date? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.bindingID = bindingID
        self.bindingName = bindingName
        self.categoryPath = categoryPath
        self.capturedAt = capturedAt
        self.projectDate = projectDate
        self.projectDateText = projectDateText
        self.relativePath = relativePath
        self.packaging = packaging
        self.sourceName = sourceName
        self.sourcePath = sourcePath
        self.sourceKind = sourceKind
        self.format = format
        self.renderedName = renderedName
        self.byteCount = byteCount
        self.contentDigest = contentDigest
        self.artifactDigest = artifactDigest
        self.legacy = legacy
        self.lastSeenAt = lastSeenAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        bindingID = try container.decodeIfPresent(UUID.self, forKey: .bindingID)
        bindingName = try container.decodeIfPresent(String.self, forKey: .bindingName) ?? "Legacy"
        categoryPath = try container.decodeIfPresent(String.self, forKey: .categoryPath) ?? "Uncategorized"
        capturedAt = try container.decodeIfPresent(Date.self, forKey: .capturedAt) ?? Date(timeIntervalSince1970: 0)
        projectDate = try container.decodeIfPresent(Date.self, forKey: .projectDate)
        projectDateText = try container.decodeIfPresent(String.self, forKey: .projectDateText)
        relativePath = try container.decodeIfPresent(String.self, forKey: .relativePath) ?? ""
        packaging = try container.decodeIfPresent(SnapshotPackaging.self, forKey: .packaging) ?? .zip
        sourceName = try container.decodeIfPresent(String.self, forKey: .sourceName) ?? ""
        sourcePath = try container.decodeIfPresent(String.self, forKey: .sourcePath) ?? ""
        sourceKind = try container.decodeIfPresent(SnapshotSourceKind.self, forKey: .sourceKind) ?? .folder
        format = try container.decodeIfPresent(String.self, forKey: .format) ?? BackupFilenameFormat.defaultFormat
        renderedName = try container.decodeIfPresent(String.self, forKey: .renderedName) ?? ""
        byteCount = try container.decodeIfPresent(Int64.self, forKey: .byteCount)
        contentDigest = try container.decodeIfPresent(String.self, forKey: .contentDigest)
        artifactDigest = try container.decodeIfPresent(String.self, forKey: .artifactDigest)
        legacy = try container.decodeIfPresent(Bool.self, forKey: .legacy) ?? false
        lastSeenAt = try container.decodeIfPresent(Date.self, forKey: .lastSeenAt)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? capturedAt
    }

    var fileName: String {
        URL(fileURLWithPath: relativePath).lastPathComponent
    }

    func absolutePath(storePath: String) -> String {
        URL(fileURLWithPath: storePath).appendingPathComponent(relativePath).path
    }

    var displayCategory: String {
        categoryPath.isEmpty ? "Uncategorized" : categoryPath
    }
}

struct ExternalCollection: Codable, Identifiable, Equatable {
    var storeID: UUID?
    var relativePath: String
    var kind: String
    var label: String
    var lastSeenAt: Date

    var id: String { (storeID?.uuidString ?? "") + ":" + relativePath }
}

struct StoreCatalog: Codable, Equatable {
    var format: Int
    var storeID: UUID
    var revision: Int
    var updatedAt: Date
    var snapshots: [SnapshotRecord]
    var ignoredPaths: [String]
    var externals: [ExternalCollection]

    init(
        storeID: UUID,
        snapshots: [SnapshotRecord] = [],
        revision: Int = 0,
        updatedAt: Date = Date(),
        ignoredPaths: [String] = [],
        externals: [ExternalCollection] = []
    ) {
        self.format = 2
        self.storeID = storeID
        self.revision = revision
        self.updatedAt = updatedAt
        self.snapshots = snapshots
        self.ignoredPaths = ignoredPaths
        self.externals = externals
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        format = try container.decodeIfPresent(Int.self, forKey: .format) ?? 2
        storeID = try container.decode(UUID.self, forKey: .storeID)
        revision = try container.decodeIfPresent(Int.self, forKey: .revision) ?? 0
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        snapshots = try container.decodeIfPresent([SnapshotRecord].self, forKey: .snapshots) ?? []
        ignoredPaths = try container.decodeIfPresent([String].self, forKey: .ignoredPaths) ?? []
        externals = try container.decodeIfPresent([ExternalCollection].self, forKey: .externals) ?? []
    }
}

struct UnmanagedItem: Identifiable, Equatable {
    let storeID: UUID
    let storeName: String
    let storePath: String
    let relativePath: String
    let isDirectory: Bool
    let byteCount: Int64?
    let modifiedAt: Date?

    var id: String { storeID.uuidString + ":" + relativePath }
    var name: String { URL(fileURLWithPath: relativePath).lastPathComponent }
    var categoryPath: String {
        let parent = (relativePath as NSString).deletingLastPathComponent
        return parent == "." || parent.isEmpty ? "Uncategorized" : parent
    }
    var absolutePath: String {
        URL(fileURLWithPath: storePath).appendingPathComponent(relativePath).path
    }
}

enum SnapshotAvailability: String, Codable, Equatable {
    case available
    case offline
    case missing
}

struct SnapshotEnvelope: Identifiable, Equatable {
    let storeID: UUID
    let storeName: String
    let storePath: String
    let storeOnline: Bool
    let record: SnapshotRecord
    let exists: Bool

    var id: String { storeID.uuidString + ":" + record.id }

    var absolutePath: String { record.absolutePath(storePath: storePath) }

    var availability: SnapshotAvailability {
        if !storeOnline { return .offline }
        return exists ? .available : .missing
    }

    var statusText: String {
        switch availability {
        case .available: return "Available"
        case .offline: return "Store offline"
        case .missing: return "Missing"
        }
    }
}

struct SnapshotGroup: Identifiable, Equatable {
    let id: String
    let copies: [SnapshotEnvelope]

    var primary: SnapshotEnvelope {
        copies.first { $0.availability == .available }
            ?? copies.first { $0.availability == .offline }
            ?? copies.first!
    }

    var record: SnapshotRecord { primary.record }
    var copyCount: Int { copies.count }
    var storeNames: [String] { copies.map(\.storeName) }

    var availability: SnapshotAvailability {
        if copies.contains(where: { $0.availability == .available }) { return .available }
        if copies.contains(where: { $0.availability == .offline }) { return .offline }
        return .missing
    }
}

// MARK: - Scan

struct ScanReport: Equatable {
    var startedAt: Date
    var finishedAt: Date
    var onlineStores: Int
    var offlineStores: Int
    var found: Int
    var missing: Int
    var relocated: Int
    var unmanaged: Int
    var errors: [String]

    init(
        startedAt: Date = Date(),
        finishedAt: Date = Date(),
        onlineStores: Int = 0,
        offlineStores: Int = 0,
        found: Int = 0,
        missing: Int = 0,
        relocated: Int = 0,
        unmanaged: Int = 0,
        errors: [String] = []
    ) {
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.onlineStores = onlineStores
        self.offlineStores = offlineStores
        self.found = found
        self.missing = missing
        self.relocated = relocated
        self.unmanaged = unmanaged
        self.errors = errors
    }

    var summary: String {
        var parts: [String] = []
        if onlineStores > 0 { parts.append("\(onlineStores) online") }
        if offlineStores > 0 { parts.append("\(offlineStores) offline") }
        if found > 0 { parts.append("\(found) found") }
        if relocated > 0 { parts.append("\(relocated) moved") }
        if missing > 0 { parts.append("\(missing) missing") }
        if unmanaged > 0 { parts.append("\(unmanaged) unmanaged") }
        if !errors.isEmpty { parts.append("\(errors.count) errors") }
        return parts.isEmpty ? "Scan complete" : parts.joined(separator: " · ")
    }
}
