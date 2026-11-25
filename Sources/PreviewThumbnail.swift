import AppKit
import PDFKit
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

actor PreviewThumbnailStore {
    static let shared = PreviewThumbnailStore()

    private var cache: [String: NSImage] = [:]
    private var inFlight: [String: Task<NSImage?, Never>] = [:]

    func thumbnail(for url: URL) async -> NSImage? {
        let key = url.path
        if let cached = cache[key] { return cached }
        if let task = inFlight[key] { return await task.value }

        let task = Task<NSImage?, Never> {
            if let image = NSImage(contentsOf: url) {
                return image
            }
            if let image = await quickLookThumbnail(url) {
                return image
            }
            if let image = pdfThumbnail(url) {
                return image
            }
            if let image = textThumbnail(url) {
                return image
            }
            return nil
        }
        inFlight[key] = task
        let image = await task.value
        inFlight[key] = nil
        if let image { cache[key] = image }
        return image
    }

    private func quickLookThumbnail(_ url: URL) async -> NSImage? {
        await withCheckedContinuation { continuation in
            let request = QLThumbnailGenerator.Request(
                fileAt: url,
                size: CGSize(width: 600, height: 700),
                scale: 1,
                representationTypes: .thumbnail
            )
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
                continuation.resume(returning: representation?.nsImage)
            }
        }
    }

    private func pdfThumbnail(_ url: URL) -> NSImage? {
        guard url.pathExtension.lowercased() == "pdf",
              let document = PDFDocument(url: url),
              let page = document.page(at: 0) else { return nil }
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0 else { return nil }
        let size = CGSize(width: 600, height: 600 * bounds.height / bounds.width)
        return page.thumbnail(of: size, for: .mediaBox)
    }

    private func textThumbnail(_ url: URL) -> NSImage? {
        let type = UTType(filenameExtension: url.pathExtension)
        let isText = type?.conforms(to: .text) == true
            || type?.conforms(to: .sourceCode) == true
            || ["json", "xml", "yaml", "yml", "md", "markdown", "csv", "tsv", "log", "swift", "py", "js", "ts", "css", "sh", "zsh", "c", "h", "cpp", "rs", "go", "java", "kt", "rb", "php"].contains(url.pathExtension.lowercased())
        guard isText,
              let data = try? Data(contentsOf: url),
              data.count <= 800_000 else { return nil }
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return nil }

        let size = NSSize(width: 600, height: 700)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor(calibratedWhite: 0.995, alpha: 1).setFill()
        NSRect(origin: .zero, size: size).fill()
        let snippet = text.split(separator: "\n", omittingEmptySubsequences: false)
            .prefix(45)
            .joined(separator: "\n")
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 16, weight: .regular),
            .foregroundColor: NSColor(calibratedWhite: 0.20, alpha: 1),
            .paragraphStyle: paragraph
        ]
        (snippet as NSString).draw(
            in: NSRect(x: 28, y: 28, width: size.width - 56, height: size.height - 56),
            withAttributes: attributes
        )
        image.unlockFocus()
        return image
    }
}

struct FileCoverThumbnail: View {
    let url: URL
    let direct: NSImage?

    @State private var image: NSImage?

    var body: some View {
        GeometryReader { geometry in
            Group {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.clear
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
            .clipped()
        }
        .task(id: url) {
            if let direct {
                image = direct
            } else {
                image = await PreviewThumbnailStore.shared.thumbnail(for: url)
            }
        }
    }
}
