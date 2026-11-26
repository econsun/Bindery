import AppKit
import Foundation
import Combine

enum ActivityLevel: String, Codable, CaseIterable {
    case major
    case normal
    case minor
    case error

    var sortRank: Int {
        switch self {
        case .error: return 3
        case .major: return 2
        case .normal: return 1
        case .minor: return 0
        }
    }
}

enum ActivityActor: String, Codable {
    case user
    case system
    case scan
}

enum ActivityKind: String, Codable, CaseIterable {
    case appLaunch = "app.launch"
    case scan = "scan.completed"
    case backupStarted = "backup.started"
    case backupCompleted = "backup.completed"
    case backupFailed = "backup.failed"
    case bindingCreated = "binding.created"
    case bindingUpdated = "binding.updated"
    case bindingDeleted = "binding.deleted"
    case bindingArchived = "binding.archived"
    case bindingFavorite = "binding.favorite"
    case bindingCategory = "binding.category_changed"
    case categoryCreated = "category.created"
    case categoryRenamed = "category.renamed"
    case categoryMoved = "category.moved"
    case categoryRemoved = "category.removed"
    case storeAdded = "store.added"
    case storeRemoved = "store.removed"
    case snapshotAssigned = "snapshot.assigned"
    case snapshotMovedStore = "snapshot.moved_store"
    case snapshotRenamed = "snapshot.renamed"
    case snapshotDeleted = "snapshot.deleted"
    case snapshotVerified = "snapshot.verified"
    case unmanagedImported = "unmanaged.imported"
    case unmanagedIgnored = "unmanaged.ignored"

    enum Group: String, CaseIterable {
        case backup
        case change
        case scan
        case store
        case system

        var title: String {
            switch self {
            case .backup: return "Backups"
            case .change: return "Changes"
            case .scan: return "Scans"
            case .store: return "Stores"
            case .system: return "System"
            }
        }
    }

    var group: Group {
        switch self {
        case .backupStarted, .backupCompleted, .backupFailed:
            return .backup
        case .scan:
            return .scan
        case .storeAdded, .storeRemoved:
            return .store
        case .appLaunch:
            return .system
        default:
            return .change
        }
    }

    var icon: String {
        switch self {
        case .appLaunch: return "power"
        case .scan: return "magnifyingglass"
        case .backupStarted, .backupCompleted: return "arrow.triangle.2.circlepath"
        case .backupFailed: return "exclamationmark.triangle"
        case .bindingCreated: return "plus.rectangle.on.folder"
        case .bindingUpdated: return "slider.horizontal.3"
        case .bindingDeleted: return "trash"
        case .bindingArchived: return "archivebox"
        case .bindingFavorite: return "star"
        case .bindingCategory: return "folder.badge.gearshape"
        case .categoryCreated, .categoryRenamed, .categoryMoved, .categoryRemoved: return "folder"
        case .storeAdded: return "externaldrive.badge.plus"
        case .storeRemoved: return "externaldrive.badge.minus"
        case .snapshotAssigned: return "link"
        case .snapshotMovedStore: return "externaldrive"
        case .snapshotRenamed: return "textformat"
        case .snapshotDeleted: return "trash"
        case .snapshotVerified: return "checkmark.shield"
        case .unmanagedImported: return "tray.and.arrow.down"
        case .unmanagedIgnored: return "eye.slash"
        }
    }

    var tintName: String {
        switch self {
        case .backupFailed: return "red"
        case .backupStarted, .backupCompleted: return "green"
        case .bindingCreated, .bindingUpdated, .bindingDeleted, .bindingArchived, .bindingFavorite, .bindingCategory:
            return "purple"
        case .categoryCreated, .categoryRenamed, .categoryMoved, .categoryRemoved:
            return "orange"
        case .storeAdded, .storeRemoved:
            return "cyan"
        case .snapshotAssigned, .snapshotMovedStore, .snapshotRenamed, .snapshotDeleted, .snapshotVerified:
            return "blue"
        case .unmanagedImported, .unmanagedIgnored:
            return "orange"
        case .scan:
            return "green"
        case .appLaunch:
            return "gray"
        }
    }
}

struct ActivityEvent: Codable, Identifiable, Equatable {
    var schema: Int = 1
    var id: UUID = UUID()
    var timestamp: Date = Date()
    var kind: ActivityKind
    var level: ActivityLevel
    var actor: ActivityActor
    var title: String
    var summary: String
    var details: [String: String]

    init(
        kind: ActivityKind,
        level: ActivityLevel,
        actor: ActivityActor,
        title: String,
        summary: String = "",
        details: [String: String] = [:],
        timestamp: Date = Date()
    ) {
        self.kind = kind
        self.level = level
        self.actor = actor
        self.title = title
        self.summary = summary
        self.details = details
        self.timestamp = timestamp
    }

    var searchText: String {
        ([title, summary, kind.rawValue, level.rawValue, actor.rawValue]
            + details.flatMap { [$0.key, $0.value] })
            .joined(separator: "\n")
    }
}

/// A durable, append-only JSON Lines activity log. The UI reads the in-memory
/// tail; the file is the source of truth for later inspection (including by an
/// AI): every line is a self-contained event with stable keys and ISO dates.
@MainActor
final class ActivityLog: ObservableObject {
    static let shared = ActivityLog()

    nonisolated static let logURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Bindery", isDirectory: true)
            .appendingPathComponent("activity.jsonl")
    }()

    nonisolated static var previousURL: URL {
        logURL.deletingLastPathComponent().appendingPathComponent("activity.previous.jsonl")
    }

    nonisolated static let maximumFileBytes = 8 * 1024 * 1024

    @Published private(set) var events: [ActivityEvent] = []

    private let maximumInMemory = 5_000
    private let queue = DispatchQueue(label: "Bindery.ActivityLog", qos: .utility)

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private init() {
        load()
    }

    func log(
        _ kind: ActivityKind,
        level: ActivityLevel,
        actor: ActivityActor = .user,
        title: String,
        summary: String = "",
        details: [String: String] = [:]
    ) {
        let event = ActivityEvent(
            kind: kind,
            level: level,
            actor: actor,
            title: title,
            summary: summary,
            details: details
        )
        events.insert(event, at: 0)
        if events.count > maximumInMemory {
            events.removeLast(events.count - maximumInMemory)
        }
        let data = try? encoder.encode(event)
        guard let data else { return }
        var line = data
        line.append(0x0A)
        queue.async {
            ActivityLog.append(line, to: Self.logURL)
        }
    }

    func shouldRecordLaunch(version: String) -> Bool {
        guard let last = events.first(where: { $0.kind == .appLaunch }) else { return true }
        if last.details["version"] != version { return true }
        return Date().timeIntervalSince(last.timestamp) >= 86_400
    }

    func jsonLines(for events: [ActivityEvent]) -> String {
        var lines: [String] = []
        for event in events.sorted(by: { $0.timestamp < $1.timestamp }) {
            guard let data = try? encoder.encode(event),
                  let text = String(data: data, encoding: .utf8) else { continue }
            lines.append(text)
        }
        return lines.joined(separator: "\n")
    }

    func revealLogFile() {
        let url = Self.logURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func load() {
        var loaded: [ActivityEvent] = []
        for url in [Self.previousURL, Self.logURL] {
            guard let data = try? Data(contentsOf: url),
                  let text = String(data: data, encoding: .utf8) else { continue }
            for line in text.split(separator: "\n") {
                guard let lineData = line.data(using: .utf8),
                      let event = try? decoder.decode(ActivityEvent.self, from: lineData) else { continue }
                loaded.append(event)
            }
        }
        events = Array(loaded.sorted { $0.timestamp > $1.timestamp }.prefix(maximumInMemory))
    }

    private nonisolated static func append(_ data: Data, to url: URL) {
        let manager = FileManager.default
        try? manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !manager.fileExists(atPath: url.path) {
            manager.createFile(atPath: url.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            // Logging must never break a backup operation.
        }

        guard let size = try? manager.attributesOfItem(atPath: url.path)[.size] as? Int,
              size > maximumFileBytes else { return }
        rotate(url: url, manager: manager)
    }

    private nonisolated static func rotate(url: URL, manager: FileManager) {
        let previous = previousURL
        try? manager.removeItem(at: previous)
        try? manager.moveItem(at: url, to: previous)
        manager.createFile(atPath: url.path, contents: nil)
    }
}
