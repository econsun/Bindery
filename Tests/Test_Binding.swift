import Foundation

@main
struct BinderyTests {
    static func main() async throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("BinderyTests-\(UUID().uuidString)", isDirectory: true)
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }

        // MARK: Naming

        let binding = BackupBinding(
            name: "Project",
            kind: .generator,
            category: "Notes/Macro",
            filenameFormat: BackupFilenameFormat.defaultFormat
        )
        let style = FilenameStyle(dateFormat: "yyMMdd", projectDateFormat: "yyMMdd", timeFormat: "HHmmss")
        let projectDate = Calendar(identifier: .gregorian).date(
            from: DateComponents(year: 2026, month: 3, day: 12, hour: 12)
        )
        let backupDate = Calendar(identifier: .gregorian).date(
            from: DateComponents(year: 2026, month: 7, day: 23, hour: 16, minute: 2)
        )!

        let named = BackupFilenameFormat.render(
            binding.filenameFormat,
            bindingName: binding.name,
            category: binding.category,
            sourceName: "260312 Report.pdf",
            sourceExtension: "pdf",
            projectDate: projectDate,
            backupDate: backupDate,
            style: style,
            randomLetters: "AB"
        )
        precondition(named.name == "Project_260312_260723AB", "unexpected name: \(named.name)")
        precondition(named.identifier == "260723AB")
        precondition(named.projectDateText == "260312")

        let noProject = BackupFilenameFormat.render(
            binding.filenameFormat,
            bindingName: binding.name,
            category: binding.category,
            sourceName: "Loose File.pdf",
            sourceExtension: "pdf",
            projectDate: nil,
            backupDate: backupDate,
            style: style,
            randomLetters: "CD"
        )
        precondition(noProject.name == "Project_260723CD", "unexpected name: \(noProject.name)")
        precondition(!noProject.name.contains("__"))

        let fixedID = BackupFilenameFormat.render(
            binding.filenameFormat,
            bindingName: binding.name,
            category: binding.category,
            sourceName: "260312 Report.pdf",
            sourceExtension: "pdf",
            projectDate: projectDate,
            backupDate: backupDate,
            style: style,
            identifierOverride: "260823XI"
        )
        precondition(fixedID.name == "Project_260312_260723XI", "unexpected fixed-id name: \(fixedID.name)")
        precondition(fixedID.identifier == "260823XI")

        let legacyContentSource = "/tmp/bkMedia_Project_260823BTTG_Title.zip"
        let legacyContentDate = BackupFilenameFormat.legacySourceProjectDate(fromSourcePath: legacyContentSource)
        precondition(legacyContentDate != nil)
        precondition(
            Calendar(identifier: .gregorian).dateComponents([.month, .day], from: legacyContentDate!).day == 23
        )
        precondition(
            BackupFilenameFormat.legacySourceProjectDate(
                fromSourcePath: "/tmp/bkTalk_WorldEcon_BLP1995_261116CDWT.zip"
            ) == nil
        )

        precondition(BackupFilenameFormat.parseProjectDate(from: "260312 Report.pdf") != nil)
        precondition(BackupFilenameFormat.parseProjectDate(from: "26 03 12 Report") != nil)
        precondition(BackupFilenameFormat.parseProjectDate(from: "26-03-12 Report") != nil)
        precondition(BackupFilenameFormat.parseProjectDate(from: "Report 260312") == nil)
        precondition(BackupFilenameFormat.extractIdentifier(from: "Project_260312_260723AB.zip") == "260723AB")

        // MARK: Engine + catalog

        let storeRoot = root.appendingPathComponent("Store", isDirectory: true)
        try manager.createDirectory(at: storeRoot, withIntermediateDirectories: true)
        let marker = try CatalogStore.ensureStore(at: storeRoot, label: "Test Store")
        let store = StoreRef(id: marker.storeID, path: storeRoot.path, label: "Test Store")
        defer { try? manager.removeItem(at: CatalogStore.cacheURL(for: store.id)) }
        let source = root.appendingPathComponent("260312 Report.txt")
        try Data("bindery".utf8).write(to: source)

        let request = BackupRequest(
            sourceURL: source,
            bindingID: binding.id,
            bindingName: binding.name,
            categoryPath: "Notes/Macro",
            filenameFormat: binding.filenameFormat,
            style: style,
            store: store,
            compress: false,
            includeGit: false,
            respectsGitignore: false,
            projectDate: nil,
            now: backupDate
        )
        let result = try await BackupEngine.run(request)
        precondition(manager.fileExists(atPath: result.snapshotURL.path))
        precondition(result.snapshotURL.path.contains("/Notes/Macro/"))
        precondition(result.record.id.count == 8)
        precondition(result.record.projectDate != nil)
        precondition(result.record.contentDigest != nil)

        let catalog = CatalogStore.readCatalog(for: storeRoot, storeID: store.id)
        precondition(catalog.snapshots.count == 1)
        precondition(catalog.snapshots[0].id == result.record.id)
        precondition(FileManager.default.fileExists(atPath: result.record.absolutePath(storePath: storeRoot.path)))

        let second = try await BackupEngine.run(request)
        precondition(second.record.id != result.record.id)
        let catalog2 = CatalogStore.readCatalog(for: storeRoot, storeID: store.id)
        precondition(catalog2.snapshots.count == 2)
        precondition(Set(catalog2.snapshots.map(\.id)).count == 2)

        // A single file is copied as-is even when the binding asks for ZIP.
        let compressedFileRequest = BackupRequest(
            sourceURL: source,
            bindingID: binding.id,
            bindingName: "FileProject",
            categoryPath: "Notes/Macro",
            filenameFormat: binding.filenameFormat,
            style: style,
            store: store,
            compress: true,
            includeGit: true,
            respectsGitignore: true,
            projectDate: nil,
            now: backupDate.addingTimeInterval(120)
        )
        let compressedFile = try await BackupEngine.run(compressedFileRequest)
        precondition(compressedFile.record.packaging == .file)
        precondition(compressedFile.snapshotURL.pathExtension == "txt")
        precondition(compressedFile.record.renderedName.hasSuffix(".txt"))

        // MARK: Folder snapshot

        let folder = root.appendingPathComponent("260404 Folder", isDirectory: true)
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("folder".utf8).write(to: folder.appendingPathComponent("note.md"))
        let folderRequest = BackupRequest(
            sourceURL: folder,
            bindingID: binding.id,
            bindingName: "Folder",
            categoryPath: "Notes",
            filenameFormat: binding.filenameFormat,
            style: style,
            store: store,
            compress: false,
            includeGit: false,
            respectsGitignore: false,
            projectDate: nil,
            now: backupDate
        )
        let folderResult = try await BackupEngine.run(folderRequest)
        precondition(manager.fileExists(atPath: folderResult.snapshotURL.appendingPathComponent("note.md").path))
        precondition(folderResult.record.packaging == SnapshotPackaging.folder)
        precondition(folderResult.record.contentDigest != nil)

        // MARK: Category follows a moved folder

        let initialScan = await ScanEngine.scan(stores: [store])
        let folderRecord = initialScan.catalogs[store.id]!.snapshots.first { $0.packaging == .folder }!
        let oldFolderURL = URL(fileURLWithPath: folderRecord.absolutePath(storePath: storeRoot.path))
        let newFolderURL = storeRoot.appendingPathComponent("Research/Moved/", isDirectory: true)
            .appendingPathComponent(oldFolderURL.lastPathComponent, isDirectory: true)
        try manager.createDirectory(at: newFolderURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try manager.moveItem(at: oldFolderURL, to: newFolderURL)
        let categoryScan = await ScanEngine.scan(stores: [store])
        let movedFolder = categoryScan.catalogs[store.id]!.snapshots.first { $0.id == folderRecord.id }
        precondition(movedFolder?.categoryPath == "Research/Moved")

        // MARK: External systems

        let kopia = storeRoot.appendingPathComponent("Backup.kopia", isDirectory: true)
        try manager.createDirectory(at: kopia, withIntermediateDirectories: true)
        try Data("blob".utf8).write(to: kopia.appendingPathComponent("kopia.repository"))
        let externalScan = await ScanEngine.scan(stores: [store])
        precondition(externalScan.externals.count == 1)
        precondition(externalScan.unmanagedItems.isEmpty)
        try manager.removeItem(at: kopia)

        // MARK: Unmanaged files

        let strayFolder = storeRoot.appendingPathComponent("Stray", isDirectory: true)
        try manager.createDirectory(at: strayFolder, withIntermediateDirectories: true)
        try Data("stray".utf8).write(to: strayFolder.appendingPathComponent("loose.txt"))
        let unmanagedScan = await ScanEngine.scan(stores: [store])
        precondition(unmanagedScan.unmanagedItems.count == 1)
        precondition(unmanagedScan.unmanagedItems[0].name == "loose.txt")
        try manager.removeItem(at: strayFolder)

        // MARK: Offline cache

        let catalog3 = CatalogStore.readCatalog(for: storeRoot, storeID: store.id)
        try CatalogStore.cacheCatalog(catalog3)
        let cached = CatalogStore.cachedCatalog(for: store.id)
        precondition(cached?.snapshots.count == 4)

        // MARK: Scan and relocation

        let scanOutcome = await ScanEngine.scan(stores: [store])
        precondition(scanOutcome.report.onlineStores == 1)
        precondition(scanOutcome.catalogs[store.id]?.snapshots.count == 4)
        precondition(scanOutcome.report.missing == 0)

        let digestRecord = scanOutcome.catalogs[store.id]!.snapshots.first { $0.id == second.record.id }!
        precondition(digestRecord.artifactDigest != nil)
        let digestURL = digestRecord.absolutePath(storePath: storeRoot.path)
        let digestMovedURL = URL(fileURLWithPath: digestURL).deletingLastPathComponent()
            .appendingPathComponent("renamed-without-id.txt")
        try manager.moveItem(at: URL(fileURLWithPath: digestURL), to: digestMovedURL)
        let digestOutcome = await ScanEngine.scan(stores: [store])
        precondition(digestOutcome.report.relocated == 1)
        precondition(digestOutcome.catalogs[store.id]!.snapshots.contains {
            $0.id == digestRecord.id && $0.relativePath.hasSuffix("renamed-without-id.txt")
        })

        let original = scanOutcome.catalogs[store.id]!.snapshots.first {
            $0.packaging != .folder && manager.fileExists(atPath: $0.absolutePath(storePath: storeRoot.path))
        }!
        let originalURL = original.absolutePath(storePath: storeRoot.path)
        let movedURL = URL(fileURLWithPath: originalURL).deletingLastPathComponent()
            .appendingPathComponent("moved-" + URL(fileURLWithPath: originalURL).lastPathComponent)
        try manager.moveItem(at: URL(fileURLWithPath: originalURL), to: movedURL)
        let relocated = await ScanEngine.scan(stores: [store])
        precondition(relocated.report.relocated == 1)
        let relocatedRecord = relocated.catalogs[store.id]!.snapshots.first { $0.id == original.id }
        precondition(relocatedRecord?.relativePath.hasSuffix(movedURL.lastPathComponent) == true)

        var offlineStore = store
        offlineStore.path = root.appendingPathComponent("OfflineStore").path
        let offlineOutcome = await ScanEngine.scan(stores: [offlineStore])
        precondition(offlineOutcome.report.offlineStores == 1)
        precondition(offlineOutcome.catalogs[store.id]?.snapshots.count == 4)

        // MARK: Legacy content dates

        let legacyRoot = root.appendingPathComponent("LegacyStore", isDirectory: true)
        try manager.createDirectory(
            at: legacyRoot.appendingPathComponent("Media/Images", isDirectory: true),
            withIntermediateDirectories: true
        )
        let legacyMarker = try CatalogStore.ensureStore(at: legacyRoot, label: "Legacy Store")
        let legacyStore = StoreRef(id: legacyMarker.storeID, path: legacyRoot.path, label: "Legacy Store")
        defer { try? manager.removeItem(at: CatalogStore.cacheURL(for: legacyStore.id)) }
        let legacyFile = legacyRoot.appendingPathComponent("Media/Images/Project_Title_260823XI.zip")
        try Data("see-dict".utf8).write(to: legacyFile)
        let projectDay = Calendar(identifier: .gregorian).date(
            from: DateComponents(year: 2026, month: 8, day: 23, hour: 12)
        )!
        let archiveDay = Calendar(identifier: .gregorian).date(
            from: DateComponents(year: 2026, month: 9, day: 2, hour: 9, minute: 34)
        )!
        try manager.setAttributes([.modificationDate: archiveDay], ofItemAtPath: legacyFile.path)
        let legacyRecord = SnapshotRecord(
            id: "260823XI",
            bindingID: nil,
            bindingName: "Project_Title",
            categoryPath: "Media/Images",
            capturedAt: projectDay,
            relativePath: "Media/Images/Project_Title_260823XI.zip",
            packaging: .zip,
            sourceName: "Project_Title",
            sourcePath: "bkMedia_Project_260823BTTG_Title.zip",
            sourceKind: .file,
            format: BackupFilenameFormat.defaultFormat,
            renderedName: legacyFile.lastPathComponent,
            byteCount: 8,
            legacy: true
        )
        try CatalogStore.updateCatalog(for: legacyRoot, storeID: legacyStore.id) { catalog in
            catalog.snapshots = [legacyRecord]
            catalog.revision += 1
        }
        let legacyScan = await ScanEngine.scan(stores: [legacyStore])
        let repaired = legacyScan.catalogs[legacyStore.id]!.snapshots.first { $0.id == "260823XI" }!
        precondition(repaired.projectDate != nil)
        precondition(
            Calendar.current.isDate(repaired.capturedAt, inSameDayAs: archiveDay),
            "backup date was not recovered from the archive file: \(repaired.capturedAt)"
        )
        precondition(
            Calendar.current.isDate(repaired.projectDate!, inSameDayAs: projectDay),
            "project date was not preserved"
        )

        // MARK: Legacy document

        let legacyURL = root.appendingPathComponent("bindings.json")
        let legacyJSON = """
        {
          "version": 1,
          "bindings": [
            {
              "id": "11111111-1111-1111-1111-111111111111",
              "name": "Legacy",
              "sourcePath": "\(source.path)",
              "destinationPath": "\(storeRoot.path)",
              "kind": "Folder",
              "category": "Old"
            }
          ]
        }
        """
        try Data(legacyJSON.utf8).write(to: legacyURL)
        let legacyBindingStore = BindingStore(fileURL: legacyURL)
        let legacyDocument = try legacyBindingStore.load()
        precondition(legacyDocument.version == 1)
        precondition(legacyDocument.bindings.count == 1)
        precondition(legacyDocument.bindings[0].storeID == nil)
        precondition(legacyDocument.stores.isEmpty)
        precondition(legacyDocument.bindings[0].backupHistory.isEmpty)

        // MARK: Sorting

        var older = BackupBinding(name: "Older")
        older.backupDates = [backupDate.addingTimeInterval(-86_400)]
        var newer = BackupBinding(name: "Newer")
        newer.backupDates = [backupDate]
        let byLastBackup = sortedBindings([older, newer], by: .lastBackup, ascending: false)
        precondition(byLastBackup.first?.name == "Newer")

        // MARK: Generator status

        let generator = BackupBinding(
            name: "Generator",
            destinationPath: storeRoot.path,
            storeID: store.id,
            kind: .generator,
            category: "Files"
        )
        precondition(!generator.needsInput)
        precondition(backupStatusText(for: generator).contains("Drop"))
        var offline = generator
        offline.destinationPath = root.appendingPathComponent("Missing").path
        precondition(backupStatusText(for: offline).contains("offline"))

        print("BinderyTests passed")
    }
}
