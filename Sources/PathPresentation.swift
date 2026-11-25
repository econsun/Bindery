import Foundation

enum PathSpace {
    case cloud
    case local
    case external
    case none

    var label: String {
        switch self {
        case .cloud: return "Cloud"
        case .local: return "Local"
        case .external: return "External"
        case .none: return "Not set"
        }
    }

    var symbol: String {
        switch self {
        case .cloud: return "icloud"
        case .local: return "internaldrive"
        case .external: return "externaldrive"
        case .none: return "questionmark.folder"
        }
    }
}

struct PathPresentation {
    let path: String
    let space: PathSpace
    let provider: String
    let short: String
    let exists: Bool

    var display: String {
        space == .none ? "Not set" : "\(provider) · \(short)"
    }
}

func presentPath(_ raw: String) -> PathPresentation {
    let path = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !path.isEmpty else {
        return PathPresentation(path: "", space: .none, provider: "Not set", short: "Not set", exists: false)
    }

    let fileExists = FileManager.default.fileExists(atPath: path)
    let lower = path.lowercased()
    var space: PathSpace = .local
    var provider = "Local"
    var relative = (path as NSString).abbreviatingWithTildeInPath

    if lower.contains("com~apple~clouddocs") {
        space = .cloud
        provider = "iCloud"
        if let range = path.range(of: "com~apple~CloudDocs/", options: .caseInsensitive) {
            relative = String(path[range.upperBound...])
        }
    } else if lower.contains("cloudstorage") {
        space = .cloud
        if let range = path.range(of: "CloudStorage/", options: .caseInsensitive) {
            let remainder = String(path[range.upperBound...])
            let parts = remainder.split(separator: "/").map(String.init)
            provider = parts.first ?? "Cloud"
            relative = parts.dropFirst().joined(separator: "/")
        } else {
            provider = "Cloud"
        }
    } else if lower.contains("dropbox") {
        space = .cloud
        provider = "Dropbox"
    } else if lower.contains("onedrive") {
        space = .cloud
        provider = "OneDrive"
    } else if lower.contains("google drive") || lower.contains("googledrive") {
        space = .cloud
        provider = "Google Drive"
    } else if lower.hasPrefix("/volumes/") {
        space = .external
        provider = "External"
    }

    let components = relative.split(separator: "/").map(String.init).filter { !$0.isEmpty }
    let tail = components.suffix(2).joined(separator: "/")
    let short: String
    if space == .cloud {
        // Cloud paths are long by construction; the last two components are
        // enough to identify the folder and keep labels on one line.
        short = components.count > 2 ? "…/" + tail : relative
    } else if relative.count <= 52 {
        short = relative
    } else if !tail.isEmpty {
        short = "…/" + tail
    } else {
        short = String(relative.suffix(48))
    }

    return PathPresentation(path: path, space: space, provider: provider, short: short, exists: fileExists)
}

func htmlIndexURL(for binding: BackupBinding) -> URL? {
    guard !binding.sourcePath.isEmpty else { return nil }
    let source = URL(fileURLWithPath: binding.sourcePath)
    if !binding.kind.isFolderLike {
        let ext = source.pathExtension.lowercased()
        return ["html", "htm"].contains(ext) ? source : nil
    }
    guard FileManager.default.fileExists(atPath: source.path) else { return nil }
    guard let contents = try? FileManager.default.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) else {
        return nil
    }
    return contents.first { item in
        ["index.html", "index.htm"].contains(item.lastPathComponent.lowercased())
    }
}

