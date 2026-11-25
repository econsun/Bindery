import AppKit
import Combine
import Foundation

struct CategoryNode: Identifiable, Equatable {
    let path: String
    let name: String
    let depth: Int
    let directCount: Int
    let snapshotCount: Int
    let children: [CategoryNode]

    var id: String { path }
    /// Sidebar counts are binding counts, not snapshot counts. A category with
    /// 26 font backups but a single ComputerFont binding shows `1`.
    var totalBindingCount: Int { directCount + children.reduce(0) { $0 + $1.totalBindingCount } }
    var totalCount: Int { directCount + snapshotCount + children.reduce(0) { $0 + $1.totalCount } }
}

struct SnapshotRenamePreview: Identifiable, Equatable {
    enum Status: Equatable {
        case changed
        case unchanged
        case conflict
        case unavailable
    }

    let id: String
    let oldName: String
    let newName: String
    let status: Status
}

@MainActor
final class LibraryState: ObservableObject {
    @Published private(set) var bindings: [BackupBinding] = []
    @Published private(set) var stores: [StoreRef] = []
    @Published private(set) var snapshots: [SnapshotEnvelope] = []
    @Published private(set) var unmanagedItems: [UnmanagedItem] = []
    @Published private(set) var externalCollections: [ExternalCollection] = []
    @Published private(set) var scanReport: ScanReport?
    @Published private(set) var isScanning = false
    @Published private(set) var runningIDs: Set<UUID> = []
    @Published var errorMessage: String?
    @Published var statusMessage = ""
    @Published private(set) var customCategories: [String] = []
    @Published private(set) var categoryColors: [String: CardTone] = [:]
    private var statusGeneration = 0
    private let categoryColorsKey = "Bindery.CategoryColors"

    private let store: BindingStore
    private let customCategoriesKey = "Bindery.CustomCategories"

    init(store: BindingStore = BindingStore()) {
        self.store = store
        load()
        customCategories = UserDefaults.standard.stringArray(forKey: customCategoriesKey) ?? []
        loadCategoryColors()
        normalizeCategoryColors()
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        ActivityLog.shared.log(
            .appLaunch,
            level: .minor,
            actor: .system,
            title: "Bindery launched",
            summary: "Version \(version)",
            details: ["version": version, "bindings": "\(bindings.count)", "stores": "\(stores.count)"]
        )
    }

    var snapshotGroups: [SnapshotGroup] {
        Dictionary(grouping: snapshots, by: \.record.id)
            .map { SnapshotGroup(id: $0.key, copies: $0.value) }
            .sorted { $0.primary.record.capturedAt > $1.primary.record.capturedAt }
    }

    /// Snapshots that do not belong to any (existing) binding. They are shown
    /// in Unmanaged until the user explicitly moves them to a binding.
    var unboundSnapshotGroups: [SnapshotGroup] {
        let bindingIDs = Set(bindings.map(\.id))
        return snapshotGroups.filter { group in
            guard let bindingID = group.record.bindingID else { return true }
            return !bindingIDs.contains(bindingID)
        }
    }

    var categories: [String] {
        // Categories belong to bindings. Snapshots inherit their binding's
        // category and must never introduce a category of their own.
        let names = Set(bindings.filter { !$0.isArchived }.map(\.category).filter { !$0.isEmpty })
            .union(customCategories)
        return Array(names).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    var allCategoryPaths: [String] {
        categories
    }

    var categoryTree: [CategoryNode] {
        var paths = Set(categories)
        for category in categories {
            let parts = category.split(separator: "/", omittingEmptySubsequences: true)
            var accumulated: [String] = []
            for part in parts {
                accumulated.append(String(part))
                paths.insert(accumulated.joined(separator: "/"))
            }
        }

        func children(of parent: String?, depth: Int) -> [CategoryNode] {
            paths
                .filter { categoryParent($0) == parent }
                .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
                .map { path in
                    let direct = bindings.filter { $0.category == path && !$0.isArchived }.count
                    let records = snapshots.filter { $0.record.categoryPath == path }.count
                    let name = path.split(separator: "/").last.map(String.init) ?? path
                    return CategoryNode(
                        path: path,
                        name: name,
                        depth: depth,
                        directCount: direct,
                        snapshotCount: records,
                        children: children(of: path, depth: depth + 1)
                    )
                }
        }

        return children(of: nil, depth: 0)
    }

    func categoryColor(_ path: String) -> CardTone {
        if let explicit = categoryColors[path] { return explicit }
        if let parent = categoryParent(path) { return categoryColor(parent) }
        if let first = bindings.first(where: { $0.category == path })?.tone { return first }
        return .slate
    }

    func setCategoryColor(_ path: String, _ tone: CardTone) {
        categoryColors[path] = tone
        saveCategoryColors()
        for index in bindings.indices {
            let category = bindings[index].category
            if category == path || category.hasPrefix(path + "/") {
                bindings[index].tone = categoryColor(category)
            }
        }
        persist(message: "Updated \(path) color")
    }

    private func categoryParent(_ path: String) -> String? {
        guard let slash = path.lastIndex(of: "/") else { return nil }
        let parent = String(path[..<slash])
        return parent.isEmpty ? nil : parent
    }

    private func loadCategoryColors() {
        guard let data = UserDefaults.standard.data(forKey: categoryColorsKey),
              let decoded = try? JSONDecoder().decode([String: CardTone].self, from: data) else { return }
        categoryColors = decoded
    }

    private func saveCategoryColors() {
        guard let data = try? JSONEncoder().encode(categoryColors) else { return }
        UserDefaults.standard.set(data, forKey: categoryColorsKey)
    }

    private func normalizeCategoryColors() {
        let categories = Set(bindings.map(\.category).filter { !$0.isEmpty })
            .sorted { lhs, rhs in
                let l = lhs.split(separator: "/").count
                let r = rhs.split(separator: "/").count
                return l == r ? lhs.localizedStandardCompare(rhs) == .orderedAscending : l < r
            }
        var changed = false
        for category in categories {
            if categoryColors[category] == nil,
               categoryParent(category).flatMap({ categoryColors[$0] }) == nil,
               let tone = bindings.first(where: { $0.category == category })?.tone {
                categoryColors[category] = tone
                changed = true
            }
        }
        for index in bindings.indices {
            let tone = categoryColor(bindings[index].category)
            if bindings[index].tone != tone {
                bindings[index].tone = tone
                changed = true
            }
        }
        if changed {
            try? store.save(BindingDocument(bindings: bindings, stores: stores))
            saveCategoryColors()
        }
    }

    func addCategory(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !customCategories.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            customCategories.append(trimmed)
            customCategories.sort { $0.localizedStandardCompare($1) == .orderedAscending }
            UserDefaults.standard.set(customCategories, forKey: customCategoriesKey)
            ActivityLog.shared.log(.categoryCreated, level: .minor, title: "Created category \(trimmed)", details: ["category": trimmed])
            showStatus("Created \(trimmed)")
        }
    }

    func addNewCategory() -> String {
        var candidate = "New Category"
        var index = 2
        while categories.contains(candidate) {
            candidate = "New Category \(index)"
            index += 1
        }
        addCategory(candidate)
        return candidate
    }

    func renameCategory(_ path: String, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let parent = categoryParent(path)
        let newPath = parent.map { "\($0)/\(trimmed)" } ?? trimmed
        guard newPath != path else { return }
        repathCategory(path, to: newPath, message: "Renamed category")
        ActivityLog.shared.log(
            .categoryRenamed,
            level: .normal,
            title: "Renamed category",
            summary: "\(path) → \(newPath)",
            details: ["from": path, "to": newPath]
        )
    }

    func moveCategory(_ path: String, under parent: String?) {
        guard parent != path else { return }
        if let parent, parent.hasPrefix(path + "/") { return }
        let name = path.split(separator: "/").last.map(String.init) ?? path
        let newPath = parent.map { "\($0)/\(name)" } ?? name
        guard newPath != path else { return }
        repathCategory(path, to: newPath, message: parent == nil ? "Moved category to root" : "Moved category")
        ActivityLog.shared.log(
            .categoryMoved,
            level: .normal,
            title: "Moved category",
            summary: "\(path) → \(newPath)",
            details: ["from": path, "to": newPath, "parent": parent ?? "root"]
        )
    }

    func removeCategoryIfEmpty(_ path: String) {
        let hasBindings = bindings.contains { $0.category == path || $0.category.hasPrefix(path + "/") }
        guard !hasBindings else { return }
        customCategories.removeAll { $0 == path || $0.hasPrefix(path + "/") }
        categoryColors = categoryColors.filter { !($0.key == path || $0.key.hasPrefix(path + "/")) }
        UserDefaults.standard.set(customCategories, forKey: customCategoriesKey)
        saveCategoryColors()
        ActivityLog.shared.log(.categoryRemoved, level: .minor, title: "Removed empty category \(path)", details: ["category": path])
        objectWillChange.send()
    }

    private func repathCategory(_ oldPath: String, to newPath: String, message: String) {
        for index in bindings.indices {
            let category = bindings[index].category
            if category == oldPath {
                bindings[index].category = newPath
            } else if category.hasPrefix(oldPath + "/") {
                bindings[index].category = newPath + String(category.dropFirst(oldPath.count))
            }
        }

        customCategories = customCategories.map { category in
            if category == oldPath { return newPath }
            if category.hasPrefix(oldPath + "/") {
                return newPath + String(category.dropFirst(oldPath.count))
            }
            return category
        }
        customCategories = Array(Set(customCategories)).sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
        if !customCategories.contains(newPath) {
            customCategories.append(newPath)
            customCategories.sort { $0.localizedStandardCompare($1) == .orderedAscending }
        }
        UserDefaults.standard.set(customCategories, forKey: customCategoriesKey)

        var colors: [String: CardTone] = [:]
        for (key, tone) in categoryColors {
            if key == oldPath {
                colors[newPath] = tone
            } else if key.hasPrefix(oldPath + "/") {
                colors[newPath + String(key.dropFirst(oldPath.count))] = tone
            } else {
                colors[key] = tone
            }
        }
        categoryColors = colors
        saveCategoryColors()

        for index in bindings.indices {
            let category = bindings[index].category
            if category == newPath || category.hasPrefix(newPath + "/") {
                bindings[index].tone = categoryColor(category)
            }
        }
        persist(message: message)
        relocateSnapshots(oldCategory: oldPath, newCategory: newPath)
    }

    func isParentCategory(_ category: String) -> Bool {
        categories.contains { $0.hasPrefix(category + "/") }
            || bindings.contains { $0.category.hasPrefix(category + "/") }
    }

    func assignCategory(_ id: UUID, _ category: String) {
        guard !isParentCategory(category) else {
            showStatus("Choose a subcategory for this binding")
            return
        }
        guard let index = bindings.firstIndex(where: { $0.id == id }) else { return }
        bindings[index].category = category
        bindings[index].tone = categoryColor(category)
        bindings[index].isArchived = false
        addCategory(category)
        persist(message: "Moved to \(category)")
        relocateSnapshots(bindingID: id, newCategory: category)
        ActivityLog.shared.log(
            .bindingCategory,
            level: .normal,
            title: "Moved binding \(bindings[index].name) to \(category)",
            details: ["binding": bindings[index].name, "category": category, "bindingID": id.uuidString]
        )
    }

    func assignArchived(_ id: UUID, _ archived: Bool) {
        guard let index = bindings.firstIndex(where: { $0.id == id }) else { return }
        bindings[index].isArchived = archived
        persist(message: archived ? "Archived" : "Unarchived")
        ActivityLog.shared.log(
            .bindingArchived,
            level: .minor,
            actor: .user,
            title: archived ? "Archived \(bindings[index].name)" : "Unarchived \(bindings[index].name)",
            details: ["binding": bindings[index].name, "archived": archived ? "true" : "false"]
        )
    }

    func addCreator(_ id: UUID, _ creator: BindingCreator) {
        guard let index = bindings.firstIndex(where: { $0.id == id }) else { return }
        bindings[index].creators.insert(creator)
        bindings[index].isArchived = false
        persist(message: "Added creator: \(creator.rawValue)")
        ActivityLog.shared.log(
            .bindingUpdated,
            level: .minor,
            title: "Added creator to \(bindings[index].name)",
            summary: creator.rawValue,
            details: ["binding": bindings[index].name, "creator": creator.rawValue]
        )
    }

    func setCreator(_ id: UUID, _ creator: BindingCreator) {
        guard let index = bindings.firstIndex(where: { $0.id == id }) else { return }
        bindings[index].creators = [creator]
        bindings[index].isArchived = false
        persist(message: "Creator: \(creator.rawValue)")
        ActivityLog.shared.log(
            .bindingUpdated,
            level: .minor,
            title: "Changed creator for \(bindings[index].name)",
            summary: creator.rawValue,
            details: ["binding": bindings[index].name, "creator": creator.rawValue]
        )
    }

    func load() {
        do {
            let document = try store.load()
            bindings = document.bindings
            stores = document.stores
            refreshStorePaths()
            rebuildSnapshotsFromCache()
            hydrateBindings()
        } catch {
            errorMessage = "Could not load bindings: \(error.localizedDescription)"
        }
    }

    private func refreshStorePaths() {
        for index in stores.indices {
            if let reachable = stores[index].reachablePath, reachable != stores[index].path {
                stores[index].path = reachable
            }
            // Do not create security-scoped bookmarks on the main thread here.
            // On iCloud/removable volumes that can block waiting for a sandbox
            // extension; the scanner refreshes bookmarks off the main thread.
        }
    }

    private func rebuildSnapshotsFromCache() {
        var result: [SnapshotEnvelope] = []
        var externals: [ExternalCollection] = []
        for store in stores {
            let catalog: StoreCatalog
            if store.isOnline {
                _ = try? CatalogStore.ensureStore(at: URL(fileURLWithPath: store.path), label: store.label, preferredID: store.id)
                catalog = CatalogStore.readCatalog(for: URL(fileURLWithPath: store.path), storeID: store.id)
            } else {
                catalog = CatalogStore.cachedCatalog(for: store.id) ?? StoreCatalog(storeID: store.id)
            }
            externals.append(contentsOf: catalog.externals)
            for record in catalog.snapshots {
                let path = record.absolutePath(storePath: store.path)
                result.append(
                    SnapshotEnvelope(
                        storeID: store.id,
                        storeName: store.name,
                        storePath: store.path,
                        storeOnline: store.isOnline,
                        record: record,
                        exists: store.isOnline && FileManager.default.fileExists(atPath: path)
                    )
                )
            }
        }
        snapshots = result.sorted { $0.record.capturedAt > $1.record.capturedAt }
        externalCollections = externals
    }

    func save(_ binding: BackupBinding) {
        var saved = binding
        saved.category = CatalogStore.sanitizedCategoryPath(saved.category)
        saved.tone = categoryColor(saved.category)
        addCategory(saved.category)
        let previous = bindings.first { $0.id == saved.id }
        var previousCategory: String?
        if let index = bindings.firstIndex(where: { $0.id == saved.id }) {
            previousCategory = bindings[index].category
            bindings[index] = saved
        } else {
            bindings.append(saved)
        }
        persist(message: "Saved \(saved.name)")
        if let previousCategory, previousCategory != saved.category {
            relocateSnapshots(bindingID: saved.id, newCategory: saved.category)
        }
        var details = bindingDetails(saved)
        if let previous {
            details["changed"] = bindingChanges(from: previous, to: saved)
            ActivityLog.shared.log(
                .bindingUpdated,
                level: .major,
                title: "Updated binding \(saved.name)",
                summary: "Changed: \(details["changed"] ?? "")",
                details: details
            )
        } else {
            ActivityLog.shared.log(
                .bindingCreated,
                level: .major,
                title: "Created binding \(saved.name)",
                summary: "\(saved.kind.rawValue) · \(saved.category)",
                details: details
            )
        }
    }

    func delete(_ binding: BackupBinding) {
        PreviewImageStore.remove(path: binding.previewImagePath)

        // A snapshot must always have an owner. Detach this binding's snapshots
        // first and immediately re-home them under `Recovered` bindings, one per
        // category, instead of leaving dangling IDs that a later scan would turn
        // back into a binding with the deleted name.
        let affected = snapshots.filter { $0.record.bindingID == binding.id }
        if !affected.isEmpty {
            for storeRef in stores {
                guard storeRef.isOnline else { continue }
                _ = try? CatalogStore.updateCatalog(
                    for: URL(fileURLWithPath: storeRef.path),
                    storeID: storeRef.id
                ) { catalog in
                    var changed = false
                    for index in catalog.snapshots.indices where catalog.snapshots[index].bindingID == binding.id {
                        catalog.snapshots[index].bindingID = nil
                        catalog.snapshots[index].bindingName = binding.name
                        catalog.snapshots[index].updatedAt = Date()
                        changed = true
                    }
                    if changed { catalog.revision += 1 }
                }
            }
            snapshots = snapshots.map { envelope in
                guard envelope.record.bindingID == binding.id else { return envelope }
                var record = envelope.record
                record.bindingID = nil
                record.bindingName = binding.name
                return SnapshotEnvelope(
                    storeID: envelope.storeID,
                    storeName: envelope.storeName,
                    storePath: envelope.storePath,
                    storeOnline: envelope.storeOnline,
                    record: record,
                    exists: envelope.exists
                )
            }
        }

        bindings.removeAll { $0.id == binding.id }
        persist(message: affected.isEmpty ? "Deleted \(binding.name)" : "Deleted \(binding.name); its backups are now unmanaged")
        hydrateBindings()
        ActivityLog.shared.log(
            .bindingDeleted,
            level: .major,
            title: "Deleted binding \(binding.name)",
            summary: affected.isEmpty ? "No snapshots were attached" : "\(affected.count) snapshot\(affected.count == 1 ? "" : "s") returned to Unmanaged",
            details: [
                "binding": binding.name,
                "category": binding.category,
                "bindingID": binding.id.uuidString,
                "snapshotIDs": affected.map(\.record.id).joined(separator: ",")
            ]
        )
    }

    func toggleFavorite(_ binding: BackupBinding) {
        guard let index = bindings.firstIndex(where: { $0.id == binding.id }) else { return }
        bindings[index].isFavorite.toggle()
        persist(message: bindings[index].isFavorite ? "Added to Favorites" : "Removed from Favorites")
        ActivityLog.shared.log(
            .bindingFavorite,
            level: .minor,
            title: bindings[index].isFavorite ? "Favorited \(bindings[index].name)" : "Unfavorited \(bindings[index].name)",
            details: ["binding": bindings[index].name]
        )
    }

    func move(_ binding: BackupBinding, to category: String) {
        guard !isParentCategory(category) else {
            showStatus("Choose a subcategory for this binding")
            return
        }
        guard let index = bindings.firstIndex(where: { $0.id == binding.id }) else { return }
        bindings[index].category = category
        bindings[index].tone = categoryColor(category)
        addCategory(category)
        persist(message: "Moved to \(category)")
        relocateSnapshots(bindingID: binding.id, newCategory: category)
        ActivityLog.shared.log(
            .bindingCategory,
            level: .normal,
            title: "Moved binding \(binding.name) to \(category)",
            details: ["binding": binding.name, "category": category, "bindingID": binding.id.uuidString]
        )
    }

    func runBackup(_ binding: BackupBinding, style: FilenameStyle) {
        guard !runningIDs.contains(binding.id) else { return }
        if binding.isGenerator {
            errorMessage = "This is a generator. Drop a file or folder onto its card, or use Backup With… to choose a source."
            return
        }
        guard !binding.sourcePath.isEmpty else {
            errorMessage = "Choose a source first."
            return
        }
        runBackup(binding, sourceURL: URL(fileURLWithPath: binding.sourcePath), style: style)
    }

    func runBackup(_ binding: BackupBinding, sourceURL: URL, style: FilenameStyle) {
        guard !runningIDs.contains(binding.id) else { return }
        guard let store = store(for: binding) else {
            errorMessage = "Choose a store for this binding first."
            return
        }
        guard store.isOnline else {
            errorMessage = "\(store.name) is offline. Connect it and try again."
            return
        }
        let sourceExists = FileManager.default.fileExists(atPath: sourceURL.path)
        guard sourceExists else {
            errorMessage = "The source is unavailable: \(sourceURL.path)"
            return
        }

        let wasEmpty = snapshots.contains { $0.record.bindingID == binding.id } == false
        let startedAt = Date()
        runningIDs.insert(binding.id)
        showStatus("Backing up \(binding.name.isEmpty ? sourceURL.lastPathComponent : binding.name)…")
        ActivityLog.shared.log(
            .backupStarted,
            level: .minor,
            title: "Backup started: \(binding.name)",
            summary: sourceURL.path,
            details: [
                "binding": binding.name,
                "source": sourceURL.path,
                "store": store.name,
                "category": binding.category
            ]
        )

        Task {
            do {
                let request = BackupRequest(
                    sourceURL: sourceURL,
                    bindingID: binding.id,
                    bindingName: binding.name,
                    categoryPath: binding.category,
                    filenameFormat: binding.filenameFormat,
                    style: style,
                    store: store,
                    compress: binding.compressBackups,
                    includeGit: binding.includeGitMetadata,
                    respectsGitignore: binding.respectsGitignore,
                    projectDate: binding.projectDate
                )
                let result = try await BackupEngine.run(request)
                let envelope = SnapshotEnvelope(
                    storeID: store.id,
                    storeName: store.name,
                    storePath: store.path,
                    storeOnline: true,
                    record: result.record,
                    exists: true
                )
                snapshots.insert(envelope, at: 0)
                snapshots.sort { $0.record.capturedAt > $1.record.capturedAt }
                if let index = bindings.firstIndex(where: { $0.id == binding.id }) {
                    if binding.archiveAfterFirstBackup && wasEmpty {
                        bindings[index].isArchived = true
                    }
                }
                hydrateBindings()
                runningIDs.remove(binding.id)
                let archived = bindings.first(where: { $0.id == binding.id })?.isArchived == true
                persist(message: archived ? "Backed up and archived \(binding.name)" : "Backed up \(binding.name)")
                let duration = Int(Date().timeIntervalSince(startedAt) * 1000)
                ActivityLog.shared.log(
                    .backupCompleted,
                    level: .major,
                    title: "Backed up \(binding.name)",
                    summary: "\(result.record.id) · \(result.record.packaging.rawValue) · \(result.record.byteCount.map { fileSizeText($0) } ?? "unknown size")",
                    details: [
                        "binding": binding.name,
                        "bindingID": binding.id.uuidString,
                        "snapshotID": result.record.id,
                        "fileName": result.record.renderedName,
                        "path": result.record.absolutePath(storePath: store.path),
                        "category": result.record.categoryPath,
                        "store": store.name,
                        "packaging": result.record.packaging.rawValue,
                        "bytes": result.record.byteCount.map(String.init) ?? "",
                        "source": result.record.sourcePath,
                        "projectDate": result.record.projectDateText ?? "",
                        "durationMs": String(duration),
                        "archived": archived ? "true" : "false"
                    ]
                )
            } catch {
                runningIDs.remove(binding.id)
                errorMessage = "Backup failed: \(error.localizedDescription)"
                statusMessage = ""
                ActivityLog.shared.log(
                    .backupFailed,
                    level: .error,
                    title: "Backup failed: \(binding.name)",
                    summary: error.localizedDescription,
                    details: [
                        "binding": binding.name,
                        "source": sourceURL.path,
                        "store": store.name,
                        "error": error.localizedDescription
                    ]
                )
            }
        }
    }

    func scan() {
        guard !isScanning else { return }
        isScanning = true
        let startedAt = Date()
        showStatus(stores.isEmpty ? "Add a store to begin scanning" : "Scanning stores…")
        Task {
            refreshStorePaths()
            let outcome = await ScanEngine.scan(stores: stores)
            stores = outcome.stores
            scanReport = outcome.report
            snapshots = makeEnvelopes(catalogs: outcome.catalogs, present: outcome.presentPaths)
            unmanagedItems = outcome.unmanagedItems
            externalCollections = outcome.externals
            hydrateBindings()
            isScanning = false
            persist(message: outcome.report.summary)
            let report = outcome.report
            let duration = Int(Date().timeIntervalSince(startedAt) * 1000)
            let changed = report.found > 0 || report.relocated > 0 || report.unmanaged > 0 || report.missing > 0
            let level: ActivityLevel = report.errors.isEmpty ? (changed ? .normal : .minor) : .error
            ActivityLog.shared.log(
                .scan,
                level: level,
                actor: .scan,
                title: "Scanned stores",
                summary: report.summary,
                details: [
                    "onlineStores": String(report.onlineStores),
                    "offlineStores": String(report.offlineStores),
                    "found": String(report.found),
                    "missing": String(report.missing),
                    "relocated": String(report.relocated),
                    "unmanaged": String(report.unmanaged),
                    "errors": report.errors.joined(separator: " | "),
                    "durationMs": String(duration)
                ]
            )
        }
    }

    private func makeEnvelopes(
        catalogs: [UUID: StoreCatalog],
        present: [UUID: Set<String>]
    ) -> [SnapshotEnvelope] {
        var result: [SnapshotEnvelope] = []
        for store in stores {
            let catalog = catalogs[store.id] ?? CatalogStore.cachedCatalog(for: store.id) ?? StoreCatalog(storeID: store.id)
            for record in catalog.snapshots {
                let exists = store.isOnline && (present[store.id]?.contains(record.relativePath) ?? false)
                result.append(
                    SnapshotEnvelope(
                        storeID: store.id,
                        storeName: store.name,
                        storePath: store.path,
                        storeOnline: store.isOnline,
                        record: record,
                        exists: exists
                    )
                )
            }
        }
        return result.sorted { $0.record.capturedAt > $1.record.capturedAt }
    }

    private func hydrateBindings() {
        guard !stores.isEmpty else { return }
        for index in bindings.indices {
            let binding = bindings[index]
            if let store = store(for: binding.storeID) {
                bindings[index].destinationPath = store.path
            } else if binding.storeID != nil {
                bindings[index].destinationPath = ""
            }
            let records = snapshotGroups
                .filter { group in group.copies.contains { $0.record.bindingID == binding.id } }
                .map { group -> BackupRecord in
                    let primary = group.primary
                    return BackupRecord(
                        date: primary.record.capturedAt,
                        snapshotPath: primary.absolutePath,
                        snapshotID: primary.record.id,
                        storeID: primary.storeID,
                        storeName: primary.storeName,
                        categoryPath: primary.record.categoryPath,
                        projectDate: primary.record.projectDate,
                        packaging: primary.record.packaging,
                        sourceName: primary.record.sourceName,
                        legacy: primary.record.legacy,
                        availability: group.availability,
                        copyCount: group.copyCount,
                        byteCount: {
                            let sizes = group.copies.compactMap(\.record.byteCount)
                            return sizes.isEmpty ? nil : sizes.reduce(0, +)
                        }()
                    )
                }
                .sorted { $0.date > $1.date }
            bindings[index].backupRecords = records
            bindings[index].backupDates = records.map(\.date)
            bindings[index].lastSnapshotPath = records.first?.snapshotPath
        }
    }

    func store(for id: UUID?) -> StoreRef? {
        guard let id else { return stores.first }
        return stores.first { $0.id == id }
    }

    func store(for binding: BackupBinding) -> StoreRef? {
        if let id = binding.storeID {
            return stores.first { $0.id == id }
        }
        if let match = stores.first(where: {
            !binding.destinationPath.isEmpty &&
            (binding.destinationPath == $0.path || binding.destinationPath.hasPrefix($0.path + "/"))
        }) {
            return match
        }
        return stores.first
    }

    func addStore(at url: URL) {
        let standardized = url.standardizedFileURL
        if let parent = stores.first(where: { standardized.path.hasPrefix($0.path + "/") }) {
            errorMessage = "\(standardized.lastPathComponent) is inside \(parent.name). Add the store root instead."
            return
        }
        do {
            let marker = try CatalogStore.ensureStore(at: standardized, label: standardized.lastPathComponent)
            if let index = stores.firstIndex(where: { $0.id == marker.storeID }) {
                stores[index].path = standardized.path
                stores[index].label = marker.label
                stores[index].refreshBookmark()
            } else {
                var ref = StoreRef(id: marker.storeID, path: standardized.path, label: marker.label)
                ref.refreshBookmark()
                stores.append(ref)
            }
            persist(message: "Added store \(standardized.lastPathComponent)")
            ActivityLog.shared.log(
                .storeAdded,
                level: .normal,
                title: "Added store \(standardized.lastPathComponent)",
                summary: standardized.path,
                details: ["path": standardized.path, "label": standardized.lastPathComponent]
            )
            scan()
        } catch {
            errorMessage = "Could not add store: \(error.localizedDescription)"
            ActivityLog.shared.log(
                .storeAdded,
                level: .error,
                title: "Could not add store",
                summary: error.localizedDescription,
                details: ["path": standardized.path, "error": error.localizedDescription]
            )
        }
    }

    func removeStore(_ store: StoreRef) {
        let removedSnapshots = snapshots.filter { $0.storeID == store.id }.count
        stores.removeAll { $0.id == store.id }
        snapshots.removeAll { $0.storeID == store.id }
        hydrateBindings()
        persist(message: "Removed store \(store.name)")
        ActivityLog.shared.log(
            .storeRemoved,
            level: .normal,
            title: "Removed store \(store.name)",
            summary: store.path,
            details: ["store": store.name, "storeID": store.id.uuidString, "path": store.path, "snapshots": String(removedSnapshots)]
        )
    }

    func snapshotCount(for storeID: UUID) -> Int {
        snapshots.filter { $0.storeID == storeID }.count
    }

    func count(_ selection: SidebarSelection) -> Int {
        if selection == .backups { return snapshotGroups.count }
        if selection == .unmanaged { return unmanagedItems.count + unboundSnapshotGroups.count }
        if selection == .timeline { return ActivityLog.shared.events.count }
        return bindings.filter { matchesSidebar($0, selection: selection) }.count
    }

    func importUnmanaged(_ item: UnmanagedItem) {
        Task {
            let result = await Task.detached(priority: .utility) { () -> Result<SnapshotRecord, Error> in
                let url = URL(fileURLWithPath: item.absolutePath)
                guard FileManager.default.fileExists(atPath: url.path) else {
                    return .failure(BackupEngineError.missingSource)
                }
                let storeURL = URL(fileURLWithPath: item.storePath)
                let packaging: SnapshotPackaging = url.pathExtension.lowercased() == "zip" ? .zip : .file
                let digests = DigestEngine.digests(for: url, packaging: packaging)
                let date = item.modifiedAt ?? Date()
                let dateText = BackupFilenameFormat.dateText(date, pattern: "yyMMdd", fallback: "yyMMdd")
                let existing = CatalogStore.readCatalog(for: storeURL, storeID: item.storeID)
                let used = Set(existing.snapshots.map(\.id))
                var generated: String?
                for _ in 0..<676 {
                    let candidate = dateText + BackupFilenameFormat.randomLetters(count: 2)
                    if !used.contains(candidate) {
                        generated = candidate
                        break
                    }
                }
                guard let id = generated else {
                    return .failure(BackupEngineError.identifierExhausted)
                }
                let record = SnapshotRecord(
                    id: id,
                    bindingID: nil,
                    bindingName: "Imported",
                    categoryPath: item.categoryPath,
                    capturedAt: date,
                    relativePath: item.relativePath,
                    packaging: packaging,
                    sourceName: url.deletingPathExtension().lastPathComponent,
                    sourcePath: url.path,
                    sourceKind: .file,
                    format: "",
                    renderedName: url.lastPathComponent,
                    byteCount: item.byteCount,
                    contentDigest: digests.content,
                    artifactDigest: digests.artifact,
                    legacy: false,
                    lastSeenAt: Date()
                )
                do {
                    try CatalogStore.updateCatalog(for: storeURL, storeID: item.storeID) { catalog in
                        catalog.snapshots.append(record)
                        catalog.ignoredPaths.removeAll { $0 == item.relativePath }
                        catalog.revision += 1
                    }
                    return .success(record)
                } catch {
                    return .failure(error)
                }
            }.value
            switch result {
            case .success(let record):
                unmanagedItems.removeAll { $0.id == item.id }
                ActivityLog.shared.log(
                    .unmanagedImported,
                    level: .normal,
                    title: "Imported \(item.name)",
                    summary: "\(record.id) · \(item.storeName)",
                    details: [
                        "file": item.relativePath,
                        "snapshotID": record.id,
                        "store": item.storeName,
                        "category": item.categoryPath
                    ]
                )
                scan()
                showStatus("Imported \(item.name)")
            case .failure(let error):
                errorMessage = "Could not import: \(error.localizedDescription)"
                ActivityLog.shared.log(
                    .unmanagedImported,
                    level: .error,
                    title: "Could not import \(item.name)",
                    summary: error.localizedDescription,
                    details: ["file": item.relativePath, "store": item.storeName, "error": error.localizedDescription]
                )
            }
        }
    }

    func ignoreUnmanaged(_ item: UnmanagedItem) {
        let storeURL = URL(fileURLWithPath: item.storePath)
        do {
            try CatalogStore.updateCatalog(for: storeURL, storeID: item.storeID) { catalog in
                if !catalog.ignoredPaths.contains(item.relativePath) {
                    catalog.ignoredPaths.append(item.relativePath)
                }
                catalog.revision += 1
            }
            unmanagedItems.removeAll { $0.id == item.id }
            ActivityLog.shared.log(
                .unmanagedIgnored,
                level: .minor,
                title: "Ignored \(item.name)",
                summary: item.relativePath,
                details: ["file": item.relativePath, "store": item.storeName]
            )
            showStatus("Ignored \(item.name)")
        } catch {
            errorMessage = "Could not ignore: \(error.localizedDescription)"
            ActivityLog.shared.log(
                .unmanagedIgnored,
                level: .error,
                title: "Could not ignore \(item.name)",
                summary: error.localizedDescription,
                details: ["file": item.relativePath, "store": item.storeName, "error": error.localizedDescription]
            )
        }
    }

    func open(_ path: String) {
        guard FileManager.default.fileExists(atPath: path) else {
            errorMessage = "Path unavailable: \(path)"
            return
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    func reveal(_ path: String) {
        guard FileManager.default.fileExists(atPath: path) else {
            errorMessage = "Path unavailable: \(path)"
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func refreshAvailability() { scan() }

    private func showStatus(_ message: String) {
        statusMessage = message
        statusGeneration += 1
        let generation = statusGeneration
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            guard statusGeneration == generation else { return }
            statusMessage = ""
        }
    }

    func verifySnapshots(_ ids: Set<String>) {
        let copies = snapshotGroups
            .filter { ids.contains($0.id) }
            .flatMap(\.copies)
        Task {
            let result = await Task.detached(priority: .utility) { () -> (Int, Int, Int) in
                var verified = 0
                var failed = 0
                var skipped = 0
                for copy in copies {
                    guard copy.availability == .available else {
                        skipped += 1
                        continue
                    }
                    let url = URL(fileURLWithPath: copy.absolutePath)
                    if DigestEngine.matches(copy.record, url: url) {
                        verified += 1
                    } else {
                        failed += 1
                    }
                }
                return (verified, failed, skipped)
            }.value
            if result.1 > 0 {
                errorMessage = "Verification failed for \(result.1) snapshot\(result.1 == 1 ? "" : "s")."
            }
            showStatus("Verified \(result.0) · \(result.1) failed · \(result.2) skipped")
            ActivityLog.shared.log(
                .snapshotVerified,
                level: result.1 > 0 ? .error : .normal,
                title: result.1 > 0 ? "Verification failed" : "Verified snapshots",
                summary: "\(result.0) verified · \(result.1) failed · \(result.2) skipped",
                details: [
                    "snapshotIDs": ids.sorted().joined(separator: ","),
                    "verified": String(result.0),
                    "failed": String(result.1),
                    "skipped": String(result.2)
                ]
            )
        }
    }

    func deleteSnapshots(_ ids: Set<String>) {
        let copies = snapshotGroups
            .filter { ids.contains($0.id) }
            .flatMap(\.copies)
        guard !copies.isEmpty else { return }
        Task {
            let result = await Task.detached(priority: .utility) { () -> (Int, Int, Set<String>, [String]) in
                let manager = FileManager.default
                var deleted = 0
                var skipped = 0
                var deletedIDs: Set<String> = []
                var errors: [String] = []
                for copy in copies {
                    guard copy.storeOnline else {
                        skipped += 1
                        continue
                    }
                    let source = URL(fileURLWithPath: copy.absolutePath)
                    do {
                        if copy.availability == .available {
                            var trashed: NSURL?
                            try manager.trashItem(at: source, resultingItemURL: &trashed)
                        }
                        // A record whose file is already missing still has to be
                        // removed from the catalog, otherwise it can never be
                        // deleted from the UI. Offline stores are handled when
                        // they come back online.
                        try CatalogStore.updateCatalog(
                            for: URL(fileURLWithPath: copy.storePath),
                            storeID: copy.storeID
                        ) { catalog in
                            catalog.snapshots.removeAll { $0.id == copy.record.id }
                            catalog.revision += 1
                        }
                        deletedIDs.insert(copy.record.id)
                        deleted += 1
                    } catch {
                        errors.append(error.localizedDescription)
                    }
                }
                return (deleted, skipped, deletedIDs, errors)
            }.value
            if result.0 > 0 {
                // Remove from the in-memory view immediately. `scan()` is only
                // reconciliation and may be skipped while another scan runs.
                snapshots.removeAll { envelope in
                    result.2.contains(envelope.record.id) && envelope.storeOnline
                }
                hydrateBindings()
                scan()
                showStatus("Deleted \(result.0) snapshot record\(result.0 == 1 ? "" : "s") · \(result.1) offline skipped")
            } else {
                showStatus(result.1 > 0 ? "Nothing deleted · \(result.1) offline" : "Nothing deleted")
            }
            if !result.3.isEmpty {
                errorMessage = result.3[0]
            }
            ActivityLog.shared.log(
                .snapshotDeleted,
                level: result.3.isEmpty ? .major : .error,
                title: "Deleted \(result.0) backup record\(result.0 == 1 ? "" : "s")",
                summary: "Moved to macOS Trash · \(result.1) offline skipped",
                details: [
                    "snapshotIDs": result.2.sorted().joined(separator: ","),
                    "deleted": String(result.0),
                    "skipped": String(result.1),
                    "errors": result.3.joined(separator: " | ")
                ]
            )
        }
    }

    func renamePreviews(_ ids: Set<String>, format: String, style: FilenameStyle) -> [SnapshotRenamePreview] {
        let normalized = BackupFilenameFormat.normalize(format)
        let groups = snapshotGroups.filter { ids.contains($0.id) }
        guard !groups.isEmpty else { return [] }

        var targetCounts: [String: Int] = [:]
        for group in groups {
            let target = Self.proposedRelativePath(for: group.primary.record, format: normalized, style: style)
            targetCounts[target, default: 0] += 1
        }

        return groups.map { group in
            let record = group.primary.record
            let target = Self.proposedRelativePath(for: record, format: normalized, style: style)
            let newName = URL(fileURLWithPath: target).lastPathComponent
            let status: SnapshotRenamePreview.Status
            if target == record.relativePath {
                status = .unchanged
            } else if group.copies.allSatisfy({ $0.availability != .available }) {
                status = .unavailable
            } else if (targetCounts[target] ?? 0) > 1 {
                status = .conflict
            } else if group.copies.contains(where: { copy in
                guard copy.availability == .available else { return false }
                let url = CatalogStore.snapshotURL(storePath: copy.storePath, relativePath: target)
                return FileManager.default.fileExists(atPath: url.path)
            }) {
                status = .conflict
            } else {
                status = .changed
            }
            return SnapshotRenamePreview(
                id: group.id,
                oldName: record.fileName,
                newName: newName,
                status: status
            )
        }
    }

    func renameSnapshots(_ ids: Set<String>, format: String, style: FilenameStyle) {
        let normalized = BackupFilenameFormat.normalize(format)
        let copies = snapshotGroups
            .filter { ids.contains($0.id) }
            .flatMap(\.copies)
            .filter { $0.availability == .available }
        guard !copies.isEmpty else {
            showStatus("No online copies to rename")
            return
        }
        Task {
            let result = await Task.detached(priority: .utility) { () -> (renamed: Int, unchanged: Int, conflicts: Int, errors: [String]) in
                let manager = FileManager.default
                var renamed = 0
                var unchanged = 0
                var conflicts = 0
                var errors: [String] = []
                for copy in copies {
                    var record = copy.record
                    let targetRelative = Self.proposedRelativePath(for: record, format: normalized, style: style)
                    if targetRelative == record.relativePath {
                        unchanged += 1
                        continue
                    }
                    let source = CatalogStore.snapshotURL(storePath: copy.storePath, relativePath: record.relativePath)
                    let target = CatalogStore.snapshotURL(storePath: copy.storePath, relativePath: targetRelative)
                    guard manager.fileExists(atPath: source.path) else {
                        unchanged += 1
                        continue
                    }
                    if manager.fileExists(atPath: target.path) {
                        conflicts += 1
                        continue
                    }
                    do {
                        try manager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                        try manager.moveItem(at: source, to: target)
                        record.relativePath = targetRelative
                        record.renderedName = target.lastPathComponent
                        record.format = normalized
                        record.updatedAt = Date()
                        try CatalogStore.updateCatalog(
                            for: URL(fileURLWithPath: copy.storePath),
                            storeID: copy.storeID
                        ) { catalog in
                            guard let index = catalog.snapshots.firstIndex(where: { $0.id == record.id }) else { return }
                            catalog.snapshots[index] = record
                            catalog.revision += 1
                        }
                        renamed += 1
                    } catch {
                        errors.append(error.localizedDescription)
                    }
                }
                return (renamed, unchanged, conflicts, errors)
            }.value
            if result.renamed > 0 {
                scan()
                var message = "Renamed \(result.renamed)"
                if result.unchanged > 0 { message += " · \(result.unchanged) unchanged" }
                if result.conflicts > 0 { message += " · \(result.conflicts) conflicts" }
                showStatus(message)
            } else if result.conflicts > 0 {
                showStatus("Rename skipped: \(result.conflicts) target name\(result.conflicts == 1 ? "" : "s") already exist")
            } else {
                showStatus("Nothing to rename — the generated names already match")
            }
            if !result.errors.isEmpty {
                errorMessage = result.errors[0]
            }
            ActivityLog.shared.log(
                .snapshotRenamed,
                level: result.renamed > 0 ? .major : .normal,
                title: result.renamed > 0 ? "Renamed \(result.renamed) snapshot\(result.renamed == 1 ? "" : "s")" : "Rename produced no changes",
                summary: "format: \(normalized)",
                details: [
                    "format": normalized,
                    "requested": String(ids.count),
                    "renamed": String(result.renamed),
                    "unchanged": String(result.unchanged),
                    "conflicts": String(result.conflicts),
                    "snapshotIDs": ids.sorted().joined(separator: ","),
                    "errors": result.errors.joined(separator: " | ")
                ]
            )
        }
    }

    private nonisolated static func proposedRelativePath(
        for record: SnapshotRecord,
        format: String,
        style: FilenameStyle
    ) -> String {
        let category = CatalogStore.sanitizedCategoryPath(record.categoryPath)
        let ext = URL(fileURLWithPath: record.renderedName).pathExtension
        let rendered = BackupFilenameFormat.render(
            format,
            bindingName: record.bindingName,
            category: category,
            sourceName: record.sourceName,
            sourceExtension: ext,
            projectDate: record.projectDate,
            backupDate: record.capturedAt,
            style: style,
            randomLetters: String(record.id.suffix(2)),
            identifierOverride: record.id
        )
        var name = rendered.name
        if rendered.identifier != record.id {
            let base = BackupFilenameFormat.sanitize(record.bindingName)
            name = (base.isEmpty ? "Snapshot" : base) + "_" + record.id
        }
        switch record.packaging {
        case .zip:
            if !name.lowercased().hasSuffix(".zip") { name += ".zip" }
        case .file:
            if !ext.isEmpty, !name.lowercased().hasSuffix("." + ext.lowercased()) {
                name += "." + ext
            }
        case .folder:
            break
        }

        // The scanner treats the trailing `<yymmdd><XX>` as identity. A format
        // that prints `{backupDate}{XX}` while the permanent ID carries the
        // project date would otherwise look like a brand-new snapshot, so
        // always finish with the real ID.
        let stem = URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent
        if !stem.hasSuffix(record.id) {
            let suffix = URL(fileURLWithPath: name).pathExtension
            name = stem + "_" + record.id + (suffix.isEmpty ? "" : "." + suffix)
        }
        return category + "/" + name
    }

    /// The core ownership operation: a snapshot is governed by a binding, and
    /// the binding's category determines where the file lives. Moving a
    /// snapshot to a binding therefore rewrites `bindingID`/`bindingName` and
    /// relocates the file into that binding's category folder.
    func assignSnapshots(_ ids: Set<String>, to binding: BackupBinding) {
        let copies = snapshotGroups
            .filter { ids.contains($0.id) }
            .flatMap(\.copies)
            .filter { $0.availability == .available }
        guard !copies.isEmpty else {
            showStatus("No online copies to assign")
            return
        }
        showStatus("Assigning \(copies.count) snapshot\(copies.count == 1 ? "" : "s") to \(binding.name)…")
        Task {
            let result = await Task.detached(priority: .utility) { () -> (assigned: Int, skipped: Int, errors: [String]) in
                let manager = FileManager.default
                let category = CatalogStore.sanitizedCategoryPath(binding.category)
                var assigned = 0
                var skipped = 0
                var errors: [String] = []
                for copy in copies {
                    var record = copy.record
                    let targetRelative = category + "/" + record.fileName
                    let source = CatalogStore.snapshotURL(storePath: copy.storePath, relativePath: record.relativePath)
                    let target = CatalogStore.snapshotURL(storePath: copy.storePath, relativePath: targetRelative)
                    if targetRelative != record.relativePath {
                        guard manager.fileExists(atPath: source.path) else {
                            skipped += 1
                            continue
                        }
                        if manager.fileExists(atPath: target.path) {
                            skipped += 1
                            continue
                        }
                        do {
                            try manager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                            try manager.moveItem(at: source, to: target)
                        } catch {
                            errors.append(error.localizedDescription)
                            continue
                        }
                        record.relativePath = targetRelative
                        record.categoryPath = category
                    }
                    record.bindingID = binding.id
                    record.bindingName = binding.name.isEmpty ? "Untitled" : binding.name
                    record.updatedAt = Date()
                    do {
                        try CatalogStore.updateCatalog(
                            for: URL(fileURLWithPath: copy.storePath),
                            storeID: copy.storeID
                        ) { catalog in
                            guard let index = catalog.snapshots.firstIndex(where: { $0.id == record.id }) else { return }
                            catalog.snapshots[index] = record
                            catalog.revision += 1
                        }
                        assigned += 1
                    } catch {
                        errors.append(error.localizedDescription)
                    }
                }
                return (assigned, skipped, errors)
            }.value
            if result.assigned > 0 {
                scan()
                showStatus("Assigned \(result.assigned) to \(binding.name) · \(result.skipped) skipped")
            } else {
                showStatus("Nothing assigned · \(result.skipped) skipped")
            }
            if let error = result.errors.first {
                errorMessage = error
            }
            ActivityLog.shared.log(
                .snapshotAssigned,
                level: result.errors.isEmpty ? .major : .error,
                title: "Moved \(result.assigned) backup\(result.assigned == 1 ? "" : "s") to \(binding.name)",
                summary: "Owner changed · category \(binding.category)",
                details: [
                    "binding": binding.name,
                    "bindingID": binding.id.uuidString,
                    "category": binding.category,
                    "assigned": String(result.assigned),
                    "skipped": String(result.skipped),
                    "snapshotIDs": ids.sorted().joined(separator: ","),
                    "errors": result.errors.joined(separator: " | ")
                ]
            )
        }
    }

    func moveSnapshots(_ ids: Set<String>, toStore targetStore: StoreRef) {
        guard targetStore.isOnline else {
            errorMessage = "\(targetStore.name) is offline."
            return
        }
        let copies = snapshotGroups
            .filter { ids.contains($0.id) }
            .compactMap { group -> SnapshotEnvelope? in
                let primary = group.primary
                return primary.availability == .available && primary.storeID != targetStore.id ? primary : nil
            }
        guard !copies.isEmpty else {
            showStatus("No online copies to move")
            return
        }
        Task {
            let result = await Task.detached(priority: .utility) { () -> (Int, Int, [String]) in
                let manager = FileManager.default
                var moved = 0
                var skipped = 0
                var errors: [String] = []
                for copy in copies {
                    var record = copy.record
                    let category = CatalogStore.sanitizedCategoryPath(record.categoryPath)
                    let relative = category + "/" + record.fileName
                    let source = CatalogStore.snapshotURL(storePath: copy.storePath, relativePath: record.relativePath)
                    let target = CatalogStore.snapshotURL(storePath: targetStore.path, relativePath: relative)
                    guard manager.fileExists(atPath: source.path) else {
                        skipped += 1
                        continue
                    }
                    if manager.fileExists(atPath: target.path) {
                        skipped += 1
                        continue
                    }
                    do {
                        try manager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                        try manager.moveItem(at: source, to: target)
                        record.relativePath = relative
                        record.categoryPath = category
                        record.lastSeenAt = Date()
                        record.updatedAt = Date()
                        try CatalogStore.updateCatalog(for: URL(fileURLWithPath: targetStore.path), storeID: targetStore.id) { catalog in
                            catalog.snapshots.removeAll { $0.id == record.id }
                            catalog.snapshots.append(record)
                            catalog.revision += 1
                        }
                        try CatalogStore.updateCatalog(for: URL(fileURLWithPath: copy.storePath), storeID: copy.storeID) { catalog in
                            catalog.snapshots.removeAll { $0.id == record.id }
                            catalog.revision += 1
                        }
                        moved += 1
                    } catch {
                        errors.append(error.localizedDescription)
                    }
                }
                return (moved, skipped, errors)
            }.value
            if result.0 > 0 {
                scan()
                showStatus("Moved \(result.0) to \(targetStore.name) · \(result.1) skipped")
            } else {
                showStatus("Nothing moved · \(result.1) skipped")
            }
            if !result.2.isEmpty {
                errorMessage = result.2[0]
            }
            ActivityLog.shared.log(
                .snapshotMovedStore,
                level: result.0 > 0 ? .normal : .minor,
                title: result.0 > 0 ? "Moved \(result.0) backup\(result.0 == 1 ? "" : "s") to \(targetStore.name)" : "No backups moved to \(targetStore.name)",
                summary: "\(result.1) skipped",
                details: [
                    "targetStore": targetStore.name,
                    "targetStoreID": targetStore.id.uuidString,
                    "moved": String(result.0),
                    "skipped": String(result.1),
                    "snapshotIDs": ids.sorted().joined(separator: ","),
                    "errors": result.2.joined(separator: " | ")
                ]
            )
        }
    }

    private struct SnapshotRelocation {
        let storeID: UUID
        let storePath: String
        let record: SnapshotRecord
        let newCategory: String
    }

    private func relocateSnapshots(bindingID: UUID, newCategory: String) {
        let plans = snapshots.compactMap { envelope -> SnapshotRelocation? in
            guard envelope.availability == .available,
                  envelope.record.bindingID == bindingID,
                  envelope.record.categoryPath != newCategory else { return nil }
            return SnapshotRelocation(storeID: envelope.storeID, storePath: envelope.storePath, record: envelope.record, newCategory: newCategory)
        }
        performRelocations(plans)
    }

    private func relocateSnapshots(oldCategory: String, newCategory: String) {
        let plans = snapshots.compactMap { envelope -> SnapshotRelocation? in
            guard envelope.availability == .available else { return nil }
            let current = envelope.record.categoryPath
            guard current == oldCategory || current.hasPrefix(oldCategory + "/") else { return nil }
            let suffix = String(current.dropFirst(oldCategory.count))
            return SnapshotRelocation(
                storeID: envelope.storeID,
                storePath: envelope.storePath,
                record: envelope.record,
                newCategory: newCategory + suffix
            )
        }
        performRelocations(plans)
    }

    private func performRelocations(_ plans: [SnapshotRelocation]) {
        guard !plans.isEmpty else { return }
        Task {
            let result = await Task.detached(priority: .utility) { () -> (Int, Int, [String]) in
                let manager = FileManager.default
                var moved = 0
                var skipped = 0
                var errors: [String] = []
                for plan in plans {
                    let sanitizedCategory = CatalogStore.sanitizedCategoryPath(plan.newCategory)
                    let newRelative = CatalogStore.relativePath(
                        categoryPath: sanitizedCategory,
                        fileName: plan.record.fileName
                    )
                    guard newRelative != plan.record.relativePath else { continue }
                    let source = CatalogStore.snapshotURL(storePath: plan.storePath, relativePath: plan.record.relativePath)
                    let target = CatalogStore.snapshotURL(storePath: plan.storePath, relativePath: newRelative)
                    guard manager.fileExists(atPath: source.path) else {
                        skipped += 1
                        continue
                    }
                    do {
                        try manager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                        if manager.fileExists(atPath: target.path) {
                            skipped += 1
                            continue
                        }
                        try manager.moveItem(at: source, to: target)
                        try CatalogStore.updateCatalog(
                            for: URL(fileURLWithPath: plan.storePath),
                            storeID: plan.storeID
                        ) { catalog in
                            guard let index = catalog.snapshots.firstIndex(where: { $0.id == plan.record.id }) else { return }
                            catalog.snapshots[index].categoryPath = sanitizedCategory
                            catalog.snapshots[index].relativePath = newRelative
                            catalog.snapshots[index].renderedName = target.lastPathComponent
                            catalog.snapshots[index].updatedAt = Date()
                        }
                        moved += 1
                    } catch {
                        errors.append(error.localizedDescription)
                    }
                }
                return (moved, skipped, errors)
            }.value
            if result.0 > 0 {
                showStatus("Moved \(result.0) snapshot\(result.0 == 1 ? "" : "s")")
                scan()
            }
            if !result.2.isEmpty {
                errorMessage = "Some snapshots could not be moved: \(result.2[0])"
            }
        }
    }

    private func bindingDetails(_ binding: BackupBinding) -> [String: String] {
        [
            "name": binding.name,
            "bindingID": binding.id.uuidString,
            "kind": binding.kind.rawValue,
            "category": binding.category,
            "source": binding.sourcePath,
            "store": store(for: binding)?.name ?? "None",
            "storeID": binding.storeID?.uuidString ?? "",
            "compress": binding.compressBackups ? "true" : "false",
            "archiveAfterFirst": binding.archiveAfterFirstBackup ? "true" : "false",
            "gitHistory": binding.includeGitMetadata ? "true" : "false",
            "respectGitignore": binding.respectsGitignore ? "true" : "false",
            "filenameFormat": binding.filenameFormat,
            "creators": BindingCreator.allCases.filter { binding.creators.contains($0) }.map(\.rawValue).joined(separator: ", "),
            "tone": binding.tone.rawValue,
            "coverIcon": binding.iconName ?? "",
            "previewFile": binding.previewFilePath ?? binding.previewImagePath ?? "",
            "showPreviewOnCover": binding.showPreviewOnCover ? "true" : "false",
            "note": binding.note ?? "",
            "favorite": binding.isFavorite ? "true" : "false",
            "archived": binding.isArchived ? "true" : "false"
        ]
    }

    private func bindingChanges(from old: BackupBinding, to new: BackupBinding) -> String {
        var changes: [String] = []
        func add(_ name: String, _ before: String, _ after: String) {
            guard before != after else { return }
            changes.append("\(name): \(before) → \(after)")
        }
        add("name", old.name, new.name)
        add("category", old.category, new.category)
        add("kind", old.kind.rawValue, new.kind.rawValue)
        add("source", old.sourcePath, new.sourcePath)
        add("store", store(for: old)?.name ?? "", store(for: new)?.name ?? "")
        add("compress", old.compressBackups ? "true" : "false", new.compressBackups ? "true" : "false")
        add("archiveAfterFirst", old.archiveAfterFirstBackup ? "true" : "false", new.archiveAfterFirstBackup ? "true" : "false")
        add("gitHistory", old.includeGitMetadata ? "true" : "false", new.includeGitMetadata ? "true" : "false")
        add("respectGitignore", old.respectsGitignore ? "true" : "false", new.respectsGitignore ? "true" : "false")
        add("filenameFormat", old.filenameFormat, new.filenameFormat)
        add("tone", old.tone.rawValue, new.tone.rawValue)
        add("coverIcon", old.iconName ?? "", new.iconName ?? "")
        add("previewFile", old.previewFilePath ?? old.previewImagePath ?? "", new.previewFilePath ?? new.previewImagePath ?? "")
        add("showPreviewOnCover", old.showPreviewOnCover ? "true" : "false", new.showPreviewOnCover ? "true" : "false")
        add("note", old.note ?? "", new.note ?? "")
        let oldCreators = BindingCreator.allCases.filter { old.creators.contains($0) }.map(\.rawValue).joined(separator: ", ")
        let newCreators = BindingCreator.allCases.filter { new.creators.contains($0) }.map(\.rawValue).joined(separator: ", ")
        add("creators", oldCreators, newCreators)
        return changes.isEmpty ? "none" : changes.joined(separator: "; ")
    }

    private func persist(message: String) {
        do {
            // Snapshot records are derived from store catalogs. Keep the
            // binding document to configuration only, so a stale cache can
            // never masquerade as the archive's source of truth.
            let storedBindings = bindings.map { binding -> BackupBinding in
                var copy = binding
                copy.backupRecords = []
                copy.backupDates = []
                copy.lastSnapshotPath = nil
                return copy
            }
            try store.save(BindingDocument(bindings: storedBindings, stores: stores))
            showStatus(message)
        } catch {
            errorMessage = "Could not save bindings: \(error.localizedDescription)"
        }
    }
}
