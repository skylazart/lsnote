import AppKit
import WebKit

/// Exports a note as one self-contained HTML file: the same page the preview shows, with
/// attachment images embedded as data URIs and Mermaid diagrams pre-rendered to inline SVG,
/// so the file needs no JavaScript, no sibling files and no network.
@MainActor
enum HTMLExport {
    enum Failure: LocalizedError {
        case renderingFailed

        var errorDescription: String? { "The diagrams in this note could not be rendered." }
    }

    static func document(for note: Note, settings: AppSettings = .shared) async throws -> String {
        let preview = MarkdownPreview(text: note.body, note: note,
                                      fontFamily: settings.cssFontFamily, fontSize: settings.fontSize,
                                      customCSS: settings.customCSS)
        let html = preview.html(for: note.body, noteID: note.id, standaloneTitle: note.title)
        guard let mermaid = MarkdownPreview.mermaidSource, MarkdownPreview.containsMermaid(note.body) else {
            return html
        }
        return try await DiagramRenderer().render(html, mermaidSource: mermaid)
    }
}

/// Loads a page in an off-screen web view, lets mermaid.js replace each `pre.mermaid` with an SVG,
/// and returns the resulting DOM as HTML. The library is evaluated, never added to the page.
@MainActor
private final class DiagramRenderer: NSObject, WKNavigationDelegate {
    // Sized like a typical window: mermaid measures text in the live layout.
    private let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
    private var loading: CheckedContinuation<Void, Error>?

    func render(_ html: String, mermaidSource: String) async throws -> String {
        webView.navigationDelegate = self
        try await withCheckedThrowingContinuation { continuation in
            loading = continuation
            webView.loadHTMLString(html, baseURL: nil)
        }
        // Trailing `void 0`: the library's last value can't be bridged back to Swift.
        // Completion-handler form: the async overload traps on a nil result.
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            webView.evaluateJavaScript(mermaidSource + "\nvoid 0;") { _, error in
                continuation.resume(with: error.map { .failure($0) } ?? .success(()))
            }
        }
        // Always the light theme: the SVG's colors are baked in, whatever scheme the reader uses.
        let script = """
        await \(MarkdownPreview.mermaidRunScript(theme: "'default'"));
        return document.documentElement.outerHTML;
        """
        let result = try await webView.callAsyncJavaScript(script, arguments: [:], in: nil, contentWorld: .page)
        guard let page = result as? String else { throw HTMLExport.Failure.renderingFailed }
        return "<!DOCTYPE html>\n" + page + "\n"
    }

    private func finishLoading(_ result: Result<Void, Error>) {
        loading?.resume(with: result)
        loading = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finishLoading(.success(()))
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finishLoading(.failure(error))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        finishLoading(.failure(error))
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        finishLoading(.failure(HTMLExport.Failure.renderingFailed))
    }
}
