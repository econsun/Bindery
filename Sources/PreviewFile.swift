import AppKit
import Foundation
import UniformTypeIdentifiers

func effectivePreviewFile(for binding: BackupBinding) -> URL? {
    if let path = binding.previewFilePath, !path.isEmpty,
       FileManager.default.fileExists(atPath: path) {
        return URL(fileURLWithPath: path)
    }
    if let path = binding.previewImagePath, !path.isEmpty,
       FileManager.default.fileExists(atPath: path) {
        return URL(fileURLWithPath: path)
    }
    if let index = htmlIndexURL(for: binding) { return index }
    if binding.kind == .file, binding.sourceExists {
        return URL(fileURLWithPath: binding.sourcePath)
    }
    return nil
}

func isHTMLPreview(_ url: URL) -> Bool {
    ["html", "htm"].contains(url.pathExtension.lowercased())
}

func previewImage(for binding: BackupBinding) -> NSImage? {
    guard let url = effectivePreviewFile(for: binding) else { return nil }
    let type = UTType(filenameExtension: url.pathExtension)
    guard type?.conforms(to: .image) == true else { return nil }
    if let legacy = binding.previewImagePath, url.path == legacy {
        return PreviewImageStore.image(at: legacy)
    }
    return NSImage(contentsOf: url)
}
