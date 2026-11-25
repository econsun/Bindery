import AppKit
import Combine
import SwiftUI
import WebKit

final class WebPreviewController: ObservableObject {
    weak var webView: WKWebView?

    func scrollBy(panelDX: CGFloat, panelDY: CGFloat) {
        guard let webView else { return }
        let zoom = max(0.1, webView.pageZoom)
        let dx = Int((-panelDX / zoom).rounded())
        let dy = Int((-panelDY / zoom).rounded())
        webView.evaluateJavaScript("window.scrollBy(\(dx), \(dy));", completionHandler: nil)
    }
}

struct WebPreview: NSViewRepresentable {
    let url: URL
    let zoomLevel: CGFloat
    @ObservedObject var controller: WebPreviewController

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 570, height: 210))
        webView.navigationDelegate = context.coordinator
        controller.webView = webView
        webView.pageZoom = zoomLevel
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        controller.webView = webView
        webView.pageZoom = zoomLevel
        if context.coordinator.url != url {
            context.coordinator.url = url
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var url: URL

        init(url: URL) {
            self.url = url
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let script = """
            (function () {
                var meta = document.querySelector('meta[name="viewport"]');
                if (!meta) {
                    meta = document.createElement('meta');
                    meta.name = 'viewport';
                    document.head.appendChild(meta);
                }
                meta.setAttribute('content', 'width=1200, initial-scale=0.475, minimum-scale=0.2, maximum-scale=2');
            })();
            """
            webView.evaluateJavaScript(script, completionHandler: nil)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            print("WEBPREVIEW didFail", error)
        }
    }
}
