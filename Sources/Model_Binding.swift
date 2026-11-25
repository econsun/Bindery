import Foundation

enum BindingKind: String, Codable, CaseIterable, Identifiable {
    case folder = "Folder"
    case file = "File"
    case generator = "Generator"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .folder: return "folder"
        case .file: return "doc"
        case .generator: return "wand.and.stars"
        }
    }

    var isFolderLike: Bool { self == .folder }
}

enum BindingCreator: String, Codable, CaseIterable, Identifiable {
    case deepseek = "DeepSeek"
    case openai = "OpenAI"
    case human = "Human"

    var id: String { rawValue }
}

enum CardTone: String, Codable, CaseIterable, Identifiable {
    case slate = "Slate"
    case red = "Red"
    case orange = "Orange"
    case yellow = "Yellow"
    case green = "Green"
    case cyan = "Cyan"
    case blue = "Blue"
    case purple = "Purple"
    case pink = "Pink"

    var id: String { rawValue }
}

struct BackupRecord: Codable, Identifiable, Equatable {
    var id: UUID
    var date: Date
    var snapshotPath: String
    var snapshotID: String
    var storeID: UUID?
    var storeName: String?
    var categoryPath: String?
    var projectDate: Date?
    var packaging: SnapshotPackaging?
    var sourceName: String?
    var legacy: Bool
    var availability: SnapshotAvailability?
    var copyCount: Int
    var byteCount: Int64?

    init(
        id: UUID = UUID(),
        date: Date,
        snapshotPath: String = "",
        snapshotID: String = "",
        storeID: UUID? = nil,
        storeName: String? = nil,
        categoryPath: String? = nil,
        projectDate: Date? = nil,
        packaging: SnapshotPackaging? = nil,
        sourceName: String? = nil,
        legacy: Bool = false,
        availability: SnapshotAvailability? = nil,
        copyCount: Int = 1,
        byteCount: Int64? = nil
    ) {
        self.id = id
        self.date = date
        self.snapshotPath = snapshotPath
        self.snapshotID = snapshotID
        self.storeID = storeID
        self.storeName = storeName
        self.categoryPath = categoryPath
        self.projectDate = projectDate
        self.packaging = packaging
        self.sourceName = sourceName
        self.legacy = legacy
        self.availability = availability
        self.copyCount = copyCount
        self.byteCount = byteCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        date = try container.decode(Date.self, forKey: .date)
        snapshotPath = try container.decodeIfPresent(String.self, forKey: .snapshotPath) ?? ""
        snapshotID = try container.decodeIfPresent(String.self, forKey: .snapshotID) ?? ""
        storeID = try container.decodeIfPresent(UUID.self, forKey: .storeID)
        storeName = try container.decodeIfPresent(String.self, forKey: .storeName)
        categoryPath = try container.decodeIfPresent(String.self, forKey: .categoryPath)
        projectDate = try container.decodeIfPresent(Date.self, forKey: .projectDate)
        packaging = try container.decodeIfPresent(SnapshotPackaging.self, forKey: .packaging)
        sourceName = try container.decodeIfPresent(String.self, forKey: .sourceName)
        legacy = try container.decodeIfPresent(Bool.self, forKey: .legacy) ?? false
        availability = try container.decodeIfPresent(SnapshotAvailability.self, forKey: .availability)
        copyCount = try container.decodeIfPresent(Int.self, forKey: .copyCount) ?? 1
        byteCount = try container.decodeIfPresent(Int64.self, forKey: .byteCount)
    }
}

struct BackupBinding: Codable, Identifiable, Equatable {
    var id = UUID()
    var name = ""
    var sourcePath = ""
    var destinationPath = ""
    var storeID: UUID?
    var kind = BindingKind.folder
    var category = "Uncategorized"
    var creators: Set<BindingCreator> = [.human]
    var note: String?
    var tone = CardTone.slate
    var isFavorite = false
    var isArchived = false
    var createdAt = Date()
    var backupDates: [Date] = []
    var lastSnapshotPath: String?
    var backupRecords: [BackupRecord] = []
    var iconName: String?
    var iconSVG: String?
    var previewImagePath: String?
    var previewFilePath: String?
    var showPreviewOnCover: Bool = true
    var compressBackups = false
    var archiveAfterFirstBackup = false
    var includeGitMetadata = true
    var respectsGitignore = false
    var filenameFormat = BackupFilenameFormat.defaultFormat
    var projectDate: Date?

    init() {}

    init(
        id: UUID = UUID(),
        name: String = "",
        sourcePath: String = "",
        destinationPath: String = "",
        storeID: UUID? = nil,
        kind: BindingKind = .folder,
        category: String = "Uncategorized",
        creators: Set<BindingCreator> = [.human],
        note: String? = nil,
        tone: CardTone = .slate,
        isFavorite: Bool = false,
        isArchived: Bool = false,
        createdAt: Date = Date(),
        backupDates: [Date] = [],
        lastSnapshotPath: String? = nil,
        backupRecords: [BackupRecord] = [],
        iconName: String? = nil,
        iconSVG: String? = nil,
        previewImagePath: String? = nil,
        previewFilePath: String? = nil,
        showPreviewOnCover: Bool = true,
        compressBackups: Bool = false,
        archiveAfterFirstBackup: Bool = false,
        includeGitMetadata: Bool = true,
        respectsGitignore: Bool = false,
        filenameFormat: String = BackupFilenameFormat.defaultFormat,
        projectDate: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.sourcePath = sourcePath
        self.destinationPath = destinationPath
        self.storeID = storeID
        self.kind = kind
        self.category = category
        self.creators = creators
        self.note = note
        self.tone = tone
        self.isFavorite = isFavorite
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.backupDates = backupDates
        self.lastSnapshotPath = lastSnapshotPath
        self.backupRecords = backupRecords
        self.iconName = iconName
        self.iconSVG = iconSVG
        self.previewImagePath = previewImagePath
        self.previewFilePath = previewFilePath
        self.showPreviewOnCover = showPreviewOnCover
        self.compressBackups = compressBackups
        self.archiveAfterFirstBackup = archiveAfterFirstBackup
        self.includeGitMetadata = includeGitMetadata
        self.respectsGitignore = respectsGitignore
        self.filenameFormat = filenameFormat
        self.projectDate = projectDate
    }

    var hasExplicitPreview: Bool {
        if let path = previewFilePath, !path.isEmpty { return true }
        if let path = previewImagePath, !path.isEmpty { return true }
        return false
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, sourcePath, destinationPath, storeID, kind, category, creators, note, tone, isFavorite, isArchived
        case legacyCreator = "creator"
        case createdAt, backupDates, lastSnapshotPath, backupRecords, iconName, iconSVG, previewImagePath, previewFilePath, showPreviewOnCover, compressBackups, archiveAfterFirstBackup, includeGitMetadata, respectsGitignore, filenameFormat, projectDate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        sourcePath = try container.decodeIfPresent(String.self, forKey: .sourcePath) ?? ""
        destinationPath = try container.decodeIfPresent(String.self, forKey: .destinationPath) ?? ""
        storeID = try container.decodeIfPresent(UUID.self, forKey: .storeID)
        kind = try container.decodeIfPresent(BindingKind.self, forKey: .kind) ?? .folder
        category = try container.decodeIfPresent(String.self, forKey: .category) ?? "Uncategorized"
        if let list = try container.decodeIfPresent([BindingCreator].self, forKey: .creators) {
            creators = Set(list)
        } else if let legacy = try container.decodeIfPresent(BindingCreator.self, forKey: .legacyCreator) {
            creators = [legacy]
        } else {
            creators = [.human]
        }
        note = try container.decodeIfPresent(String.self, forKey: .note)
        tone = try container.decodeIfPresent(CardTone.self, forKey: .tone) ?? .slate
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        isArchived = try container.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        backupDates = try container.decodeIfPresent([Date].self, forKey: .backupDates) ?? []
        lastSnapshotPath = try container.decodeIfPresent(String.self, forKey: .lastSnapshotPath)
        backupRecords = try container.decodeIfPresent([BackupRecord].self, forKey: .backupRecords) ?? []
        iconName = try container.decodeIfPresent(String.self, forKey: .iconName)
        iconSVG = try container.decodeIfPresent(String.self, forKey: .iconSVG)
        previewImagePath = try container.decodeIfPresent(String.self, forKey: .previewImagePath)
        previewFilePath = try container.decodeIfPresent(String.self, forKey: .previewFilePath)
        showPreviewOnCover = try container.decodeIfPresent(Bool.self, forKey: .showPreviewOnCover) ?? true
        compressBackups = try container.decodeIfPresent(Bool.self, forKey: .compressBackups) ?? false
        archiveAfterFirstBackup = try container.decodeIfPresent(Bool.self, forKey: .archiveAfterFirstBackup) ?? false
        includeGitMetadata = try container.decodeIfPresent(Bool.self, forKey: .includeGitMetadata) ?? true
        respectsGitignore = try container.decodeIfPresent(Bool.self, forKey: .respectsGitignore) ?? false
        filenameFormat = BackupFilenameFormat.normalize(try container.decodeIfPresent(String.self, forKey: .filenameFormat))
        projectDate = try container.decodeIfPresent(Date.self, forKey: .projectDate)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(sourcePath, forKey: .sourcePath)
        try container.encode(destinationPath, forKey: .destinationPath)
        try container.encodeIfPresent(storeID, forKey: .storeID)
        try container.encode(kind, forKey: .kind)
        try container.encode(category, forKey: .category)
        try container.encode(Array(creators), forKey: .creators)
        try container.encodeIfPresent(note, forKey: .note)
        try container.encode(tone, forKey: .tone)
        try container.encode(isFavorite, forKey: .isFavorite)
        try container.encode(isArchived, forKey: .isArchived)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(backupDates, forKey: .backupDates)
        try container.encodeIfPresent(lastSnapshotPath, forKey: .lastSnapshotPath)
        try container.encode(backupRecords, forKey: .backupRecords)
        try container.encodeIfPresent(iconName, forKey: .iconName)
        try container.encodeIfPresent(iconSVG, forKey: .iconSVG)
        try container.encodeIfPresent(previewImagePath, forKey: .previewImagePath)
        try container.encodeIfPresent(previewFilePath, forKey: .previewFilePath)
        try container.encode(showPreviewOnCover, forKey: .showPreviewOnCover)
        try container.encode(compressBackups, forKey: .compressBackups)
        try container.encode(archiveAfterFirstBackup, forKey: .archiveAfterFirstBackup)
        try container.encode(includeGitMetadata, forKey: .includeGitMetadata)
        try container.encode(respectsGitignore, forKey: .respectsGitignore)
        try container.encode(filenameFormat, forKey: .filenameFormat)
        try container.encodeIfPresent(projectDate, forKey: .projectDate)
    }

    var sourceExists: Bool {
        !sourcePath.isEmpty && FileManager.default.fileExists(atPath: sourcePath)
    }

    var destinationExists: Bool {
        !destinationPath.isEmpty && FileManager.default.fileExists(atPath: destinationPath)
    }

    var isGenerator: Bool { kind == .generator }
    var needsInput: Bool {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        if storeID == nil { return true }
        if isGenerator { return false }
        return sourcePath.isEmpty
    }
    var isOffline: Bool {
        if needsInput { return false }
        if !isGenerator && !sourceExists { return true }
        return !destinationExists
    }
    var lastBackupAt: Date? { backupRecords.map(\.date).max() ?? backupDates.max() }
    var sourceName: String { sourcePath.isEmpty ? "No source" : URL(fileURLWithPath: sourcePath).lastPathComponent }
    var destinationName: String { destinationPath.isEmpty ? "No destination" : URL(fileURLWithPath: destinationPath).lastPathComponent }

    /// Total size of every copy belonging to this binding. `nil` when no
    /// record has a measured size yet (for example a legacy catalog).
    var totalBackupBytes: Int64? {
        let sizes = backupRecords.compactMap(\.byteCount)
        guard !sizes.isEmpty else { return nil }
        return sizes.reduce(0, +)
    }

    var backupHistory: [BackupRecord] {
        if !backupRecords.isEmpty {
            return backupRecords.sorted { $0.date > $1.date }
        }
        return backupDates.map { date in
            BackupRecord(
                date: date,
                snapshotPath: abs((backupDates.max() ?? date).timeIntervalSince(date)) < 1 ? (lastSnapshotPath ?? "") : ""
            )
        }.sorted { $0.date > $1.date }
    }
}

struct BindingDocument: Codable, Equatable {
    var version = 2
    var bindings: [BackupBinding]
    var stores: [StoreRef] = []

    init(version: Int = 2, bindings: [BackupBinding], stores: [StoreRef] = []) {
        self.version = version
        self.bindings = bindings
        self.stores = stores
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        bindings = try container.decodeIfPresent([BackupBinding].self, forKey: .bindings) ?? []
        stores = try container.decodeIfPresent([StoreRef].self, forKey: .stores) ?? []
    }
}

enum LibraryViewMode: String, CaseIterable, Identifiable {
    case grid
    case list

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .grid: return "square.grid.2x2"
        case .list: return "list.bullet"
        }
    }
}

enum LibrarySort: String, CaseIterable, Identifiable {
    case name = "Name"
    case lastBackup = "Last Backup"
    case created = "Created"
    case category = "Category"
    case kind = "Type"
    case status = "Status"
    var id: String { rawValue }

    var defaultAscending: Bool {
        switch self {
        case .created, .lastBackup: return false
        default: return true
        }
    }
}

enum TimeScope: String, CaseIterable, Identifiable {
    case week = "Past Week"
    case month = "Past Month"
    case threeMonths = "Past 3 Months"
    case sixMonths = "Past 6 Months"
    case all = "All"

    var id: String { rawValue }
    var startDate: Date? {
        let calendar = Calendar.current
        switch self {
        case .week: return calendar.date(byAdding: .day, value: -7, to: Date())
        case .month: return calendar.date(byAdding: .month, value: -1, to: Date())
        case .threeMonths: return calendar.date(byAdding: .month, value: -3, to: Date())
        case .sixMonths: return calendar.date(byAdding: .month, value: -6, to: Date())
        case .all: return nil
        }
    }
}

enum SidebarSelection: Hashable {
    case all
    case backups
    case unmanaged
    case timeline
    case active
    case neverBackedUp
    case favorites
    case needsInput
    case offline
    case archived
    case category(String)
    case creator(BindingCreator)
    case kind(BindingKind)
    case tone(CardTone)
}

func matchesSidebar(_ binding: BackupBinding, selection: SidebarSelection) -> Bool {
    switch selection {
    case .all: return true
    case .backups, .unmanaged, .timeline: return false
    case .active: return !binding.isArchived
    case .neverBackedUp: return binding.lastBackupAt == nil && !binding.isArchived
    case .favorites: return binding.isFavorite
    case .needsInput: return binding.needsInput
    case .offline: return !binding.isArchived && binding.isOffline
    case .archived: return binding.isArchived
    case .category(let category): return binding.category == category && !binding.isArchived
    case .creator(let creator): return binding.creators.contains(creator)
    case .kind(let kind): return binding.kind == kind
    case .tone(let tone): return binding.tone == tone
    }
}

func matchesTime(_ binding: BackupBinding, scope: TimeScope) -> Bool {
    guard let startDate = scope.startDate else { return true }
    return (binding.lastBackupAt ?? binding.createdAt) >= startDate
}

func sortedBindings(_ bindings: [BackupBinding], by sort: LibrarySort, ascending: Bool = true) -> [BackupBinding] {
    let sorted = bindings.sorted { lhs, rhs in
        switch sort {
        case .name:
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        case .created:
            return lhs.createdAt < rhs.createdAt
        case .category:
            let comparison = lhs.category.localizedStandardCompare(rhs.category)
            if comparison != .orderedSame { return comparison == .orderedAscending }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        case .lastBackup:
            let left = lhs.lastBackupAt ?? .distantPast
            let right = rhs.lastBackupAt ?? .distantPast
            if left != right { return left < right }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        case .kind:
            let comparison = lhs.kind.rawValue.localizedStandardCompare(rhs.kind.rawValue)
            if comparison != .orderedSame { return comparison == .orderedAscending }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        case .status:
            let comparison = backupStatusText(for: lhs).localizedStandardCompare(backupStatusText(for: rhs))
            if comparison != .orderedSame { return comparison == .orderedAscending }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
    return ascending ? sorted : sorted.reversed()
}

func backupStatusText(for binding: BackupBinding, isRunning: Bool = false, now: Date = Date()) -> String {
    if isRunning { return "Backing up…" }
    if binding.isArchived { return "Archived" }
    if binding.storeID == nil || binding.destinationPath.isEmpty { return "Store not set" }
    let backupCount = binding.backupRecords.count
    if !binding.destinationExists {
        return backupCount > 0 ? "\(backupCount) backup\(backupCount == 1 ? "" : "s") · store offline" : "Store offline"
    }
    if binding.isGenerator {
        guard let last = binding.lastBackupAt else { return "Drop to back up" }
        return relativeBackupText(last, now: now, prefix: "Backed up")
    }
    if binding.sourcePath.isEmpty { return "Source not set" }
    if !binding.sourceExists {
        return backupCount > 0 ? "\(backupCount) backup\(backupCount == 1 ? "" : "s") · source missing" : "Source unavailable"
    }
    guard let last = binding.lastBackupAt else { return "Never backed up" }
    return relativeBackupText(last, now: now, prefix: "Backed up")
}

/// Short status for the front of a folder card. The count and footprint live
/// on their own line, so this never has to squeeze both facts into one
/// truncated label.
func backupCardStatusText(for binding: BackupBinding, isRunning: Bool = false, now: Date = Date()) -> String {
    if isRunning { return "Backing up…" }
    if binding.isArchived { return "Archived" }
    if binding.storeID == nil || binding.destinationPath.isEmpty { return "Store not set" }
    if !binding.destinationExists { return "Store offline" }
    if binding.isGenerator {
        guard let last = binding.lastBackupAt else { return "Drop to back up" }
        return relativeBackupText(last, now: now, prefix: "Backed up")
    }
    if binding.sourcePath.isEmpty { return "Source not set" }
    if !binding.sourceExists { return "Source missing" }
    guard let last = binding.lastBackupAt else { return "Never backed up" }
    return relativeBackupText(last, now: now, prefix: "Backed up")
}

private func relativeBackupText(_ last: Date, now: Date, prefix: String) -> String {
    let seconds = max(0, now.timeIntervalSince(last))
    if seconds < 3_600 { return "\(prefix) just now" }
    if seconds < 86_400 { return "\(prefix) \(Int(seconds / 3_600))h ago" }
    if seconds < 172_800 { return "\(prefix) yesterday" }
    if seconds < 2_592_000 { return "\(prefix) \(Int(seconds / 86_400))d ago" }
    let months = max(1, Int(seconds / 2_592_000))
    if months < 12 { return "\(prefix) \(months)mo ago" }
    return "\(prefix) \(months / 12)y ago"
}
