import Foundation

struct BindingStore {
    let fileURL: URL

    init(fileManager: FileManager = .default) {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        fileURL = base.appendingPathComponent("Bindery", isDirectory: true).appendingPathComponent("bindings.json")
    }

    init(fileURL: URL) { self.fileURL = fileURL }

    func load() throws -> BindingDocument {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            return try decoder.decode(BindingDocument.self, from: Data(contentsOf: fileURL))
        }
        let imported = importLegacyBindings()
        let document = BindingDocument(bindings: imported)
        if !imported.isEmpty { try save(document) }
        return document
    }

    func save(_ document: BindingDocument) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(document).write(to: fileURL, options: .atomic)
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }

    private func importLegacyBindings() -> [BackupBinding] {
        let legacyURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BackupHarbor", isDirectory: true).appendingPathComponent("config.json")
        guard let data = try? Data(contentsOf: legacyURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        let localRoot = root["localRoot"] as? String ?? ""
        let cloudRoot = root["cloudRoot"] as? String ?? ""
        let projects = root["projects"] as? [[String: Any]] ?? []
        return projects.compactMap { project in
            guard let name = project["name"] as? String else { return nil }
            let sourcePath = project["sourcePath"] as? String ?? ""
            let location = project["location"] as? String ?? "本地"
            let baseRoot = location == "云端" ? cloudRoot : localRoot
            let directDestination = project["destinationPath"] as? String ?? ""
            let destinationFolder = project["destinationFolder"] as? String ?? ""
            let destinationPath: String
            if !directDestination.isEmpty { destinationPath = directDestination }
            else if destinationFolder.hasPrefix("/") { destinationPath = destinationFolder }
            else if !destinationFolder.isEmpty { destinationPath = URL(fileURLWithPath: baseRoot).appendingPathComponent(destinationFolder).path }
            else { destinationPath = baseRoot }
            let prefix = project["prefix"] as? String ?? ""
            let category = normalizedCategory(prefix)
            let lastBackup = parseLegacyDate(project["lastBackup"])
            return BackupBinding(
                id: UUID(uuidString: project["id"] as? String ?? "") ?? UUID(),
                name: name,
                sourcePath: sourcePath,
                destinationPath: destinationPath,
                kind: (project["sourceMode"] as? String) == "文件" ? .file : .folder,
                category: category,
                tone: tone(for: name),
                isFavorite: false,
                createdAt: lastBackup ?? Date(),
                backupDates: lastBackup.map { [$0] } ?? [],
                lastSnapshotPath: nil
            )
        }
    }

    private func normalizedCategory(_ prefix: String) -> String {
        guard !prefix.isEmpty else { return "Uncategorized" }
        let trimmed = prefix.hasPrefix("bk") ? String(prefix.dropFirst(2)) : prefix
        return trimmed.isEmpty ? "Uncategorized" : trimmed
    }

    private func tone(for name: String) -> CardTone {
        let palette: [CardTone] = [.orange, .cyan, .slate, .green, .blue, .purple, .pink]
        let index = name.unicodeScalars.reduce(0) { ($0 + Int($1.value)) % palette.count }
        return palette[index]
    }

    private func parseLegacyDate(_ value: Any?) -> Date? {
        guard let text = value as? String else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
}
