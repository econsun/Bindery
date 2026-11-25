import Foundation

struct StoreScanResult {
    var store: StoreRef
    var catalog: StoreCatalog
    var online: Bool
    var presentPaths: Set<String>
    var missing: Int
    var relocated: Int
    var unmanaged: Int
    var unmanagedItems: [UnmanagedItem]
    var externals: [ExternalCollection]
    var recovered: Int
    var errors: [String]
}

struct ScanOutcome {
    var stores: [StoreRef]
    var catalogs: [UUID: StoreCatalog]
    var presentPaths: [UUID: Set<String>]
    var unmanagedItems: [UnmanagedItem]
    var externals: [ExternalCollection]
    var report: ScanReport
}

enum ScanEngine {
    static func scan(stores: [StoreRef]) async -> ScanOutcome {
        let startedAt = Date()
        var updatedStores: [StoreRef] = []
        var catalogs: [UUID: StoreCatalog] = [:]
        var presentPaths: [UUID: Set<String>] = [:]
        var report = ScanReport(startedAt: startedAt)
        var unmanagedItems: [UnmanagedItem] = []
        var externals: [ExternalCollection] = []

        // Read every configured store first so a snapshot moved between stores
        // can be adopted with its original binding/date metadata instead of
        // being rediscovered as an anonymous "Recovered" record.
        var knownRecords: [String: SnapshotRecord] = [:]
        for store in stores {
            let catalog: StoreCatalog
            if let path = store.reachablePath {
                let url = URL(fileURLWithPath: path)
                _ = try? CatalogStore.ensureStore(at: url, label: store.label, preferredID: store.id)
                catalog = CatalogStore.readCatalog(for: url, storeID: store.id)
            } else {
                catalog = CatalogStore.cachedCatalog(for: store.id) ?? StoreCatalog(storeID: store.id)
            }
            for record in catalog.snapshots {
                knownRecords[record.id] = record
            }
        }

        for var store in stores {
            let result = scanOne(store, knownRecords: knownRecords)
            store = result.store
            updatedStores.append(store)
            catalogs[store.id] = result.catalog
            presentPaths[store.id] = result.presentPaths
            if result.online {
                report.onlineStores += 1
            } else {
                report.offlineStores += 1
            }
            report.found += result.presentPaths.count
            report.missing += result.missing
            report.relocated += result.relocated
            report.unmanaged += result.unmanagedItems.count
            unmanagedItems.append(contentsOf: result.unmanagedItems)
            externals.append(contentsOf: result.externals)
            report.errors.append(contentsOf: result.errors)
        }

        report.finishedAt = Date()
        return ScanOutcome(
            stores: updatedStores,
            catalogs: catalogs,
            presentPaths: presentPaths,
            unmanagedItems: unmanagedItems,
            externals: externals,
            report: report
        )
    }

    private static func scanOne(_ store: StoreRef, knownRecords: [String: SnapshotRecord]) -> StoreScanResult {
        var store = store
        store.refreshBookmark()
        var result = StoreScanResult(
            store: store,
            catalog: StoreCatalog(storeID: store.id),
            online: false,
            presentPaths: [],
            missing: 0,
            relocated: 0,
            unmanaged: 0,
            unmanagedItems: [],
            externals: [],
            recovered: 0,
            errors: []
        )

        let manager = FileManager.default
        guard !store.path.isEmpty,
              manager.fileExists(atPath: store.path) else {
            result.catalog = CatalogStore.cachedCatalog(for: store.id) ?? StoreCatalog(storeID: store.id)
            result.externals = result.catalog.externals
            return result
        }

        let storeURL = URL(fileURLWithPath: store.path)
        do {
            let marker = try CatalogStore.ensureStore(at: storeURL, label: store.label, preferredID: store.id)
            if store.id != marker.storeID {
                // The marker is the physical identity. A copied store keeps the
                // same ID; a replaced folder gets a fresh marker and is adopted.
                store.id = marker.storeID
            }
            if store.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                store.label = marker.label
            }
        } catch {
            result.errors.append("Could not open \(store.name): \(error.localizedDescription)")
            result.catalog = CatalogStore.cachedCatalog(for: store.id) ?? StoreCatalog(storeID: store.id)
            result.externals = result.catalog.externals
            return result
        }

        result.online = true
        store.lastScanAt = Date()
        store.refreshBookmark()
        var catalog = CatalogStore.readCatalog(for: storeURL, storeID: store.id)
        catalog.storeID = store.id

        var filesByID: [String: URL] = [:]
        var filesByRelativePath: [String: URL] = [:]
        var unknownFileURLs: [URL] = []
        var unknownDirectoryURLs: [URL] = []
        var filesBySize: [Int64: [URL]] = [:]
        var matchedUnknownURLs = Set<URL>()
        var unknownFiles = 0
        var seenPaths = Set<String>()
        let knownFolderPaths = Set(
            catalog.snapshots.filter { $0.packaging == .folder }.map(\.relativePath)
        )
        let ignoredPaths = Set(catalog.ignoredPaths)
        var detectedExternals: [ExternalCollection] = []

        if let enumerator = manager.enumerator(
            at: storeURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) {
            for case let url as URL in enumerator {
                let name = url.lastPathComponent
                if CatalogStore.isIgnored(name) {
                    if let values = try? url.resourceValues(forKeys: [.isDirectoryKey]), values.isDirectory == true {
                        enumerator.skipDescendants()
                    }
                    continue
                }
                let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey])
                if values?.isDirectory == true, name.lowercased().contains(".kopia") {
                    let relative = relativePath(of: url, in: storeURL)
                    let existing = catalog.externals.first { $0.relativePath == relative }
                    detectedExternals.append(
                        ExternalCollection(
                            storeID: store.id,
                            relativePath: relative,
                            kind: "kopia",
                            label: name,
                            lastSeenAt: existing?.lastSeenAt ?? Date()
                        )
                    )
                    enumerator.skipDescendants()
                    continue
                }
                let relative = relativePath(of: url, in: storeURL)
                if ignoredPaths.contains(relative) {
                    if values?.isDirectory == true { enumerator.skipDescendants() }
                    continue
                }
                if values?.isDirectory == true {
                    let id = BackupFilenameFormat.extractIdentifier(from: name)
                    if knownFolderPaths.contains(relative) {
                        seenPaths.insert(relative)
                        if let id { filesByID[id] = url }
                        enumerator.skipDescendants()
                    } else if let id {
                        // A folder snapshot that was renamed by hand: its
                        // identifier is enough to relocate it, and its contents
                        // must not be mistaken for loose files.
                        filesByID[id] = url
                        enumerator.skipDescendants()
                    } else {
                        unknownDirectoryURLs.append(url)
                    }
                    continue
                }
                guard values?.isRegularFile == true else { continue }
                filesByRelativePath[relative] = url
                if let id = BackupFilenameFormat.extractIdentifier(from: name) {
                    filesByID[id] = url
                } else {
                    unknownFiles += 1
                    unknownFileURLs.append(url)
                    if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                        filesBySize[Int64(size), default: []].append(url)
                    }
                }
            }
        }

        var changed = false
        for index in catalog.snapshots.indices {
            var record = catalog.snapshots[index]
            let expected = record.relativePath

            // Imported Backup Harbor archives sometimes encoded a content date
            // (for example a content/publication date) where Bindery expects the backup
            // date. Re-file that date as the project date and use the archive
            // file's own timestamp for `capturedAt`, once.
            if let migrated = repairedLegacyDates(record, fileURL: filesByRelativePath[expected] ?? filesByID[record.id]) {
                record = migrated
                catalog.snapshots[index] = record
                changed = true
            }

            if filesByRelativePath[expected] != nil || seenPaths.contains(expected) {
                seenPaths.insert(expected)
                if record.lastSeenAt == nil {
                    record.lastSeenAt = Date()
                    catalog.snapshots[index] = record
                    changed = true
                }
                continue
            }

            if let url = filesByID[record.id] {
                let relative = relativePath(of: url, in: storeURL)
                record.relativePath = relative
                record.categoryPath = categoryPath(for: relative)
                record.renderedName = url.lastPathComponent
                record.lastSeenAt = Date()
                catalog.snapshots[index] = record
                seenPaths.insert(relative)
                result.relocated += 1
                changed = true
            } else if let url = digestMatch(
                record,
                unknownFiles: unknownFileURLs,
                filesBySize: filesBySize,
                unknownDirectories: unknownDirectoryURLs,
                matched: &matchedUnknownURLs
            ) {
                let relative = relativePath(of: url, in: storeURL)
                record.relativePath = relative
                record.categoryPath = categoryPath(for: relative)
                record.renderedName = url.lastPathComponent
                record.lastSeenAt = Date()
                catalog.snapshots[index] = record
                seenPaths.insert(relative)
                result.relocated += 1
                changed = true
            } else {
                result.missing += 1
            }
        }

        unknownFiles = max(0, unknownFiles - matchedUnknownURLs.filter {
            (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }.count)

        let knownIDs = Set(catalog.snapshots.map(\.id))
        for (id, url) in filesByID where !knownIDs.contains(id) {
            let relative = relativePath(of: url, in: storeURL)
            // A record whose filename suffix does not equal its permanent ID
            // (for example a content-dated legacy archive) may still be this
            // exact file. `seenPaths` is authoritative: never recover a file
            // that already belongs to a known snapshot.
            guard !relative.isEmpty, !seenPaths.contains(relative) else { continue }
            let rawCategory = (relative as NSString).deletingLastPathComponent
            let category = rawCategory == "." ? "" : rawCategory
            let date = identifierDate(id) ?? (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            let packaging: SnapshotPackaging = isDirectory
                ? .folder
                : (url.pathExtension.lowercased() == "zip" ? .zip : .file)
            let record: SnapshotRecord
            if var known = knownRecords[id] {
                known.relativePath = relative
                known.categoryPath = category.isEmpty ? "Uncategorized" : category
                known.renderedName = url.lastPathComponent
                known.byteCount = CatalogStore.fileSize(at: url)
                known.lastSeenAt = Date()
                known.updatedAt = Date()
                record = known
            } else {
                record = SnapshotRecord(
                    id: id,
                    bindingID: nil,
                    bindingName: "Recovered",
                    categoryPath: category.isEmpty ? "Uncategorized" : category,
                    capturedAt: date,
                    relativePath: relative,
                    packaging: packaging,
                    sourceName: url.deletingPathExtension().lastPathComponent,
                    sourcePath: "",
                    sourceKind: isDirectory ? .folder : .file,
                    format: BackupFilenameFormat.defaultFormat,
                    renderedName: url.lastPathComponent,
                    byteCount: CatalogStore.fileSize(at: url),
                    legacy: true,
                    lastSeenAt: Date()
                )
            }
            catalog.snapshots.append(record)
            seenPaths.insert(relative)
            result.recovered += 1
            changed = true
        }

        let knownSnapshotPaths = Set(catalog.snapshots.map(\.relativePath))
        let unmanagedItems = unknownFileURLs.compactMap { url -> UnmanagedItem? in
            guard !matchedUnknownURLs.contains(url) else { return nil }
            let relative = relativePath(of: url, in: storeURL)
            guard !knownSnapshotPaths.contains(relative) else { return nil }
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            return UnmanagedItem(
                storeID: store.id,
                storeName: store.name,
                storePath: store.path,
                relativePath: relative,
                isDirectory: false,
                byteCount: values?.fileSize.flatMap { Int64($0) },
                modifiedAt: values?.contentModificationDate
            )
        }
        if catalog.externals != detectedExternals {
            catalog.externals = detectedExternals
            changed = true
        }
        result.unmanaged = unmanagedItems.count
        result.unmanagedItems = unmanagedItems
        result.externals = detectedExternals
        result.presentPaths = seenPaths
        result.store = store

        if changed || catalog.revision == 0 {
            do {
                catalog = try CatalogStore.mergeCatalog(catalog, for: storeURL, storeID: store.id)
            } catch {
                result.errors.append("Could not save catalog: \(error.localizedDescription)")
            }
        } else {
            try? CatalogStore.cacheCatalog(catalog)
        }
        result.catalog = catalog
        return result
    }

    private static func digestMatch(
        _ record: SnapshotRecord,
        unknownFiles: [URL],
        filesBySize: [Int64: [URL]],
        unknownDirectories: [URL],
        matched: inout Set<URL>
    ) -> URL? {
        guard record.contentDigest != nil || record.artifactDigest != nil else { return nil }
        if record.packaging == .folder {
            guard record.contentDigest != nil else { return nil }
            for url in unknownDirectories where !matched.contains(url) {
                if DigestEngine.matches(record, url: url) {
                    matched.insert(url)
                    return url
                }
            }
            return nil
        }
        guard let bytes = record.byteCount, let candidates = filesBySize[bytes] else { return nil }
        for url in candidates where !matched.contains(url) {
            if DigestEngine.matches(record, url: url) {
                matched.insert(url)
                return url
            }
        }
        return nil
    }

    /// One-time metadata repair for old archives such as
    /// `bkMedia_Project_260823BTTG_Title.zip`.
    ///
    /// The catalog originally treated the date embedded in that old filename
    /// as `capturedAt`, which made every content date look like a backup
    /// date. Keep the permanent ID and the file untouched, but move the date
    /// into `projectDate` and take the backup date from the file's own
    /// creation/modification timestamp.
    private static func repairedLegacyDates(_ record: SnapshotRecord, fileURL: URL?) -> SnapshotRecord? {
        guard record.legacy,
              record.projectDate == nil,
              let fileURL,
              let projectDate = BackupFilenameFormat.legacySourceProjectDate(fromSourcePath: record.sourcePath) else {
            return nil
        }
        var updated = record
        updated.projectDate = projectDate
        updated.projectDateText = BackupFilenameFormat.dateText(
            projectDate,
            pattern: "yyMMdd",
            fallback: "yyMMdd"
        )
        if let fileDate = archiveFileDate(fileURL),
           fileDate >= projectDate.addingTimeInterval(-86_400) {
            updated.capturedAt = fileDate
        }
        updated.updatedAt = Date()
        return updated
    }

    /// The earliest timestamp the archive carries is the closest available
    /// approximation of when it was created. Copies can preserve the original
    /// modification date while resetting the creation date.
    private static func archiveFileDate(_ url: URL) -> Date? {
        let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        let dates = [values?.creationDate, values?.contentModificationDate].compactMap { $0 }
        return dates.min()
    }

    private static func categoryPath(for relativePath: String) -> String {
        let raw = (relativePath as NSString).deletingLastPathComponent
        let category = raw == "." ? "" : raw
        return category.isEmpty ? "Uncategorized" : CatalogStore.sanitizedCategoryPath(category)
    }

    private static func relativePath(of url: URL, in storeURL: URL) -> String {
        let prefix = storeURL.standardizedFileURL.path.hasSuffix("/") ? storeURL.standardizedFileURL.path : storeURL.standardizedFileURL.path + "/"
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(prefix) else { return url.lastPathComponent }
        return String(path.dropFirst(prefix.count))
    }

    private static func identifierDate(_ id: String) -> Date? {
        guard id.count >= 6, let date = Int(id.prefix(6)) else { return nil }
        let text = String(date)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyMMdd"
        return formatter.date(from: text)
    }
}
