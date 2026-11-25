import AppKit
import PDFKit
import QuickLookUI
import SwiftUI
import UniformTypeIdentifiers

struct FilePreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal) ?? QLPreviewView()
        view.autostarts = true
        view.shouldCloseWithWindow = false
        view.previewItem = url as NSURL
        return view
    }

    func updateNSView(_ view: QLPreviewView, context: Context) {
        view.previewItem = url as NSURL
        view.refreshPreviewItem()
    }
}

struct PDFFilePreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView(frame: .zero)
        view.autoScales = false
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.displaysPageBreaks = false
        view.pageShadowsEnabled = false
        view.pageBreakMargins = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        view.backgroundColor = .clear
        view.wantsLayer = true
        view.layer?.cornerRadius = 12
        view.layer?.masksToBounds = true
        view.document = PDFDocument(url: url)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url {
            view.document = PDFDocument(url: url)
        }
        DispatchQueue.main.async {
            configureScroll(view)
            fitWidth(view)
        }
    }

    private func configureScroll(_ view: PDFView) {
        guard let scroll = findScrollView(in: view) else { return }
        scroll.hasHorizontalScroller = false
        scroll.horizontalScrollElasticity = .none
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        scroll.automaticallyAdjustsContentInsets = false
    }

    private func findScrollView(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView { return scroll }
        for subview in view.subviews {
            if let scroll = findScrollView(in: subview) { return scroll }
        }
        return nil
    }

    private func fitWidth(_ view: PDFView) {
        guard view.bounds.width > 10,
              let page = view.document?.page(at: 0) else { return }
        let pageWidth = page.bounds(for: .mediaBox).width
        guard pageWidth > 1 else { return }
        view.scaleFactor = view.bounds.width / pageWidth
    }
}

struct TextFilePreview: View {
    let url: URL
    @State private var text: String?
    @State private var message: String?

    var body: some View {
        Group {
            if let text {
                ScrollView([.vertical, .horizontal]) {
                    Text(text)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Color.primary.opacity(0.82))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(14)
                }
                .background(Color.appElevated.opacity(0.55))
            } else {
                Text(message ?? "Loading…")
                    .font(.bindery(12))
                    .foregroundStyle(Color.primary.opacity(0.45))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: url) {
            load()
        }
    }

    private func load() {
        text = nil
        message = nil
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
        guard size <= 1_500_000 else {
            message = "Text preview limited to 1.5 MB"
            return
        }
        guard let data = try? Data(contentsOf: url) else {
            message = "Could not read file"
            return
        }
        if let value = String(data: data, encoding: .utf8) {
            text = value
        } else if let value = String(data: data, encoding: .isoLatin1) {
            text = value
        } else {
            message = "Unsupported text encoding"
        }
    }
}

struct PreviewOpenFileButton: View {
    let path: String

    var body: some View {
        Button {
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        } label: {
            Image(systemName: "arrow.up.forward.app")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.82))
                .frame(width: 30, height: 30)
                .background(.ultraThinMaterial, in: Circle())
                .overlay {
                    Circle().strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .help("Open File")
        .padding(10)
    }
}

struct FilePreviewFrame: View {
    let path: String

    private var fileType: UTType? {
        UTType(filenameExtension: URL(fileURLWithPath: path).pathExtension)
    }

    var body: some View {
        Group {
            if FileManager.default.fileExists(atPath: path) {
                let url = URL(fileURLWithPath: path)
                if fileType?.conforms(to: .pdf) == true {
                    PDFFilePreview(url: url)
                } else if fileType?.conforms(to: .text) == true
                            || fileType?.conforms(to: .sourceCode) == true
                            || ["json", "xml", "yaml", "yml", "md", "markdown", "csv", "tsv", "log", "swift", "py", "js", "ts", "html", "css", "sh", "zsh", "c", "h", "cpp", "rs", "go", "java", "kt", "rb", "php"].contains(url.pathExtension.lowercased()) {
                    TextFilePreview(url: url)
                } else {
                    FilePreview(url: url)
                }
            } else {
                Color.primary.opacity(0.05)
            }
        }
        .frame(height: 300)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
        }
        .overlay(alignment: .topTrailing) {
            PreviewOpenFileButton(path: path)
        }
    }
}
