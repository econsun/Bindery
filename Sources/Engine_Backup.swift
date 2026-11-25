import Foundation

enum BackupEngineError: LocalizedError {
    case missingSource
    case invalidDestination
    case destinationInsideSource
    case sourceInsideStore
    case compressionFailed
    case copyFailed
    case identifierExhausted

    var errorDescription: String? {
        switch self {
        case .missingSource: return "The source is unavailable"
        case .invalidDestination: return "The store is unavailable"
        case .destinationInsideSource: return "The store cannot be inside the source folder"
        case .sourceInsideStore: return "The source cannot be inside the backup store"
        case .compressionFailed: return "The snapshot could not be compressed"
        case .copyFailed: return "The snapshot could not be copied"
        case .identifierExhausted: return "No free snapshot ID is left for this day"
        }
    }
}

struct BackupRequest {
    let sourceURL: URL
    let bindingID: UUID?
    let bindingName: String
    let categoryPath: String
    let filenameFormat: String
    let style: FilenameStyle
    let store: StoreRef
    let compress: Bool
    let includeGit: Bool
    let respectsGitignore: Bool
    let projectDate: Date?
    let now: Date

    init(
        sourceURL: URL,
        bindingID: UUID?,
        bindingName: String,
        categoryPath: String,
        filenameFormat: String,
        style: FilenameStyle,
        store: StoreRef,
        compress: Bool,
        includeGit: Bool,
        respectsGitignore: Bool,
        projectDate: Date? = nil,
        now: Date = Date()
    ) {
        self.sourceURL = sourceURL
        self.bindingID = bindingID
        self.bindingName = bindingName
        self.categoryPath = categoryPath
        self.filenameFormat = filenameFormat
        self.style = style
        self.store = store
        self.compress = compress
        self.includeGit = includeGit
        self.respectsGitignore = respectsGitignore
        self.projectDate = projectDate
        self.now = now
    }
}

struct BackupResult: Equatable {
    let record: SnapshotRecord
    let snapshotURL: URL
}

enum BackupEngine {
    static func run(_ request: BackupRequest) async throws -> BackupResult {
        try await Task.detached(priority: .userInitiated) {
            try BackupGate.withLock { try perform(request) }
        }.value
    }

    private static func perform(_ request: BackupRequest) throws -> BackupResult {
        let manager = FileManager.default
        let source = request.sourceURL.standardizedFileURL
        let storeURL = URL(fileURLWithPath: request.store.path).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: source.path, isDirectory: &isDirectory) else {
            throw BackupEngineError.missingSource
        }
        guard manager.fileExists(atPath: storeURL.path, isDirectory: nil) else {
            throw BackupEngineError.invalidDestination
        }

        let sourceIsDirectory = isDirectory.boolValue
        let sourceKind: SnapshotSourceKind = sourceIsDirectory ? .folder : .file
        // Global rule: only folders can be compressed. A single file is copied
        // as-is even if an older binding still has `compressBackups` enabled.
        let shouldCompress = request.compress && sourceIsDirectory
        if sourceIsDirectory && storeURL.path.hasPrefix(source.path + "/") {
            throw BackupEngineError.destinationInsideSource
        }
        if source.path.hasPrefix(storeURL.path + "/") {
            throw BackupEngineError.sourceInsideStore
        }

        let marker = try CatalogStore.ensureStore(at: storeURL, label: request.store.name, preferredID: request.store.id)
        let catalog = CatalogStore.readCatalog(for: storeURL, storeID: marker.storeID)
        let existingIDs = Set(catalog.snapshots.map(\.id))
        let categoryPath = CatalogStore.sanitizedCategoryPath(request.categoryPath)
        let categoryURL = CatalogStore.categoryURL(for: storeURL, categoryPath: categoryPath)
        try manager.createDirectory(at: categoryURL, withIntermediateDirectories: true)

        let projectDate = request.projectDate ?? BackupFilenameFormat.parseProjectDate(from: source.lastPathComponent)
        let sourceName = source.lastPathComponent
        let sourceExtension = source.pathExtension

        var rendered: RenderedFilename?
        var targetName: String?
        var selectedID: String?
        for _ in 0..<676 {
            let letters = BackupFilenameFormat.randomLetters(count: 2)
            let candidate = BackupFilenameFormat.render(
                request.filenameFormat,
                bindingName: request.bindingName,
                category: categoryPath,
                sourceName: sourceName,
                sourceExtension: sourceExtension,
                projectDate: projectDate,
                backupDate: request.now,
                style: request.style,
                randomLetters: letters
            )
            let name = fileName(
                stem: candidate.name,
                sourceExtension: sourceExtension,
                isDirectory: sourceIsDirectory,
                compress: shouldCompress
            )
            let proposed = categoryURL.appendingPathComponent(name)
            if existingIDs.contains(candidate.identifier) || manager.fileExists(atPath: proposed.path) {
                continue
            }
            rendered = candidate
            targetName = name
            selectedID = candidate.identifier
            break
        }

        guard let rendered, let targetName, let selectedID else {
            throw BackupEngineError.identifierExhausted
        }

        let target = categoryURL.appendingPathComponent(targetName)
        let stagingRoot = CatalogStore.metadataDirectory(for: storeURL).appendingPathComponent("tmp", isDirectory: true)
        try manager.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
        let staging = stagingRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try manager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: staging) }

        let matcher: GitIgnoreMatcher? = request.respectsGitignore && sourceIsDirectory
            ? GitIgnoreMatcher(gitignoreURL: source.appendingPathComponent(".gitignore"))
            : nil

        let packaging: SnapshotPackaging
        if shouldCompress {
            let stagedName = sourceIsDirectory
                ? rendered.name
                : fileName(stem: rendered.name, sourceExtension: sourceExtension, isDirectory: false, compress: false)
            let staged = staging.appendingPathComponent(stagedName, isDirectory: sourceIsDirectory)
            if sourceIsDirectory {
                try manager.createDirectory(at: staged, withIntermediateDirectories: true)
                try copyContents(
                    from: source,
                    to: staged,
                    relative: "",
                    includeGit: request.includeGit,
                    matcher: matcher
                )
            } else {
                try manager.copyItem(at: source, to: staged)
            }
            let zipName = fileName(stem: rendered.name, sourceExtension: sourceExtension, isDirectory: sourceIsDirectory, compress: true)
            let zipURL = categoryURL.appendingPathComponent(zipName)
            try zipItem(staged, to: zipURL)
            packaging = .zip
        } else if sourceIsDirectory {
            try manager.createDirectory(at: target, withIntermediateDirectories: true)
            try copyContents(
                from: source,
                to: target,
                relative: "",
                includeGit: request.includeGit,
                matcher: matcher
            )
            packaging = .folder
        } else {
            try manager.copyItem(at: source, to: target)
            packaging = .file
        }

        let finalURL = shouldCompress
            ? categoryURL.appendingPathComponent(fileName(stem: rendered.name, sourceExtension: sourceExtension, isDirectory: sourceIsDirectory, compress: true))
            : target
        let relativePath = CatalogStore.sanitizedCategoryPath(categoryPath) + "/" + finalURL.lastPathComponent
        let digests = DigestEngine.digests(for: finalURL, packaging: packaging)
        let record = SnapshotRecord(
            id: selectedID,
            bindingID: request.bindingID,
            bindingName: request.bindingName.isEmpty ? source.deletingPathExtension().lastPathComponent : request.bindingName,
            categoryPath: categoryPath,
            capturedAt: request.now,
            projectDate: projectDate,
            projectDateText: rendered.projectDateText,
            relativePath: relativePath,
            packaging: packaging,
            sourceName: sourceName,
            sourcePath: source.path,
            sourceKind: sourceKind,
            format: BackupFilenameFormat.normalize(request.filenameFormat),
            renderedName: finalURL.lastPathComponent,
            byteCount: byteCount(at: finalURL),
            contentDigest: digests.content,
            artifactDigest: digests.artifact,
            legacy: false,
            lastSeenAt: request.now,
            updatedAt: request.now
        )

        try CatalogStore.updateCatalog(for: storeURL, storeID: marker.storeID) { catalog in
            catalog.snapshots.removeAll { $0.id == record.id }
            catalog.snapshots.append(record)
            catalog.revision += 1
        }

        return BackupResult(record: record, snapshotURL: finalURL)
    }

    // MARK: - Naming

    private static func fileName(
        stem: String,
        sourceExtension: String,
        isDirectory: Bool,
        compress: Bool
    ) -> String {
        if compress { return stem + ".zip" }
        if isDirectory { return stem }
        let ext = sourceExtension
        guard !ext.isEmpty else { return stem }
        if stem.lowercased().hasSuffix("." + ext.lowercased()) { return stem }
        return stem + "." + ext
    }

    // MARK: - Copy

    private static func copyContents(
        from source: URL,
        to destination: URL,
        relative: String,
        includeGit: Bool,
        matcher: GitIgnoreMatcher?
    ) throws {
        let manager = FileManager.default
        let children = try manager.contentsOfDirectory(
            at: source,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        )
        for child in children {
            let name = child.lastPathComponent
            if name == ".DS_Store" { continue }
            if name == ".git" && !includeGit { continue }
            if name == ".bindery" { continue }
            let relativePath = relative.isEmpty ? name : relative + "/" + name
            let values = try child.resourceValues(forKeys: [.isDirectoryKey])
            let isFolder = values.isDirectory == true
            if matcher?.isIgnored(relativePath, isDirectory: isFolder) == true { continue }
            let target = destination.appendingPathComponent(name, isDirectory: isFolder)
            if isFolder {
                try manager.createDirectory(at: target, withIntermediateDirectories: true)
                try copyContents(
                    from: child,
                    to: target,
                    relative: relativePath,
                    includeGit: includeGit,
                    matcher: matcher
                )
            } else {
                try manager.copyItem(at: child, to: target)
            }
        }
    }

    private static func zipItem(_ source: URL, to destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", source.path, destination.path]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw BackupEngineError.compressionFailed }
    }

    private static func byteCount(at url: URL) -> Int64? {
        let manager = FileManager.default
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return nil }
        if !isDirectory.boolValue {
            return (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { Int64($0) }
        }
        guard let enumerator = manager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true else { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }
}

/// Serialises the short window in which an identifier is chosen and the
/// artifact is registered, so two runs cannot pick the same ID.
private enum BackupGate {
    static let lock = NSLock()

    static func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}

struct GitIgnoreMatcher {
    private let rules: [Rule]

    init(gitignoreURL: URL) {
        guard let text = try? String(contentsOf: gitignoreURL, encoding: .utf8) else {
            rules = []
            return
        }
        rules = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .compactMap { Rule.make(from: String($0)) }
    }

    func isIgnored(_ relativePath: String, isDirectory: Bool) -> Bool {
        var ignored = false
        let range = NSRange(relativePath.startIndex..<relativePath.endIndex, in: relativePath)
        for rule in rules {
            if rule.regex.firstMatch(in: relativePath, options: [], range: range) != nil {
                ignored = !rule.negated
            }
        }
        return ignored
    }

    private struct Rule {
        let regex: NSRegularExpression
        let negated: Bool

        static func make(from rawLine: String) -> Rule? {
            var line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#") else { return nil }
            var negated = false
            if line.hasPrefix("!") {
                negated = true
                line.removeFirst()
            }
            if line.hasPrefix("\\#") { line.removeFirst() }
            if line.hasSuffix("/") { line.removeLast() }
            if line.isEmpty { return nil }

            let anchored = line.hasPrefix("/")
            if anchored { line.removeFirst() }
            let hasSlash = line.contains("/")
            let glob = regexGlob(line)
            let pattern: String
            if anchored || hasSlash {
                pattern = "^" + glob + "(/.*)?$"
            } else {
                pattern = "(^|.*/)" + glob + "(/.*)?$"
            }
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
            return Rule(regex: regex, negated: negated)
        }

        private static func regexGlob(_ glob: String) -> String {
            var result = ""
            let characters = Array(glob)
            var index = 0
            while index < characters.count {
                let character = characters[index]
                switch character {
                case "*":
                    if index + 1 < characters.count, characters[index + 1] == "*" {
                        result += ".*"
                        index += 2
                        continue
                    }
                    result += "[^/]*"
                case "?":
                    result += "[^/]"
                default:
                    result += NSRegularExpression.escapedPattern(for: String(character))
                }
                index += 1
            }
            return result
        }
    }
}
