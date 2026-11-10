import SwiftUI
import WebKit

/// Renders GitHub-flavored Markdown using a lightweight inline HTML renderer.
struct MarkdownPreview: NSViewRepresentable {
    let text: String
    var note: Note? = nil
    var fontFamily: String = "-apple-system"
    var fontSize: Double = 14
    var customCSS: String? = nil

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// Bundled mermaid.js (see lsNote/Vendor/README.md). nil if the resource is missing,
    /// in which case mermaid blocks render as ordinary code blocks.
    static let mermaidSource: String? = Bundle.main.url(forResource: "mermaid.min", withExtension: "js")
        .flatMap { try? String(contentsOf: $0, encoding: .utf8) }

    /// Scrolls to the heading for `[Section](#section)` links (ids come from `HeadingAnchor`).
    /// Handled in the page: it's loaded from a string (about:blank), and a script started from the
    /// navigation delegate while WebKit decides on the click never runs.
    private static let anchorLinkScript = """
    document.addEventListener('click', event => {
      const link = event.target.closest && event.target.closest('a[href^="#"]');
      if (!link) return;
      event.preventDefault();
      let id = link.getAttribute('href').slice(1);
      try { id = decodeURIComponent(id); } catch (_) {}
      document.getElementById(id)?.scrollIntoView({ behavior: 'smooth', block: 'start' });
    });
    """

    /// Preview-only setup; HTML export never loads these scripts.
    static func makeConfiguration() -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.userContentController.addUserScript(
            WKUserScript(source: anchorLinkScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        return config
    }

    func makeNSView(context: Context) -> WKWebView {
        let view = WKWebView(frame: .zero, configuration: Self.makeConfiguration())
        view.navigationDelegate = context.coordinator
        view.setValue(false, forKey: "drawsBackground")
        return view
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.needsMermaid = Self.mermaidSource != nil && Self.containsMermaid(text)
        webView.loadHTMLString(html(for: text, noteID: note?.id), baseURL: nil)
    }

    private static func isMermaidFence(_ line: String) -> Bool {
        line.hasPrefix("```") && line.dropFirst(3).trimmingCharacters(in: .whitespaces).lowercased() == "mermaid"
    }

    static func containsMermaid(_ markdown: String) -> Bool {
        markdown.components(separatedBy: "\n").contains(where: isMermaidFence)
    }

    // MARK: - Minimal GFM renderer

    /// A single JS expression that initializes mermaid and renders every `pre.mermaid` on the page.
    /// Its value is a promise that resolves when all are done; a diagram with a syntax error
    /// becomes mermaid's error graphic instead of rejecting. `theme` is itself a JS expression.
    static func mermaidRunScript(theme: String) -> String {
        """
        (mermaid.initialize({ startOnLoad: false, securityLevel: 'strict', theme: \(theme) }),
         mermaid.run({ querySelector: '.mermaid', suppressErrors: true }))\(mermaidLabelContrastFix)
        """
    }

    /// Runs after rendering. A diagram that sets its own node fills (`classDef x fill:#e9f2fc`)
    /// without a text color gets the theme's label color, which in the dark theme is light text
    /// on the author's light fill. Any node label whose contrast with its node's fill is below
    /// 3:1 is switched to whichever of near-black or near-white reads better; labels that are
    /// already legible, including ones with an explicit `color`, are left alone.
    private static let mermaidLabelContrastFix = """
    .then(() => {
      const rgb = c => (c.match(/[\\d.]+/g) || []).map(Number);
      const lum = c => {
        const [r, g, b] = rgb(c).map(v => (v /= 255) <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4));
        return 0.2126 * r + 0.7152 * g + 0.0722 * b;
      };
      const contrast = (a, b) => { const x = lum(a), y = lum(b); return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05); };
      const dark = 'rgb(28, 28, 30)', light = 'rgb(242, 242, 247)';
      document.querySelectorAll('.mermaid svg g.node').forEach(node => {
        const shape = node.querySelector('rect, polygon, circle, ellipse, path');
        const fill = shape ? getComputedStyle(shape).fill : '';
        const parts = rgb(fill);
        if (parts.length < 3 || parts[3] < 0.5) return;
        node.querySelectorAll('.nodeLabel, .nodeLabel *, text, tspan').forEach(label => {
          const prop = label instanceof SVGElement ? 'fill' : 'color';
          if (contrast(getComputedStyle(label)[prop], fill) >= 3) return;
          label.style.setProperty(prop, contrast(dark, fill) > contrast(light, fill) ? dark : light, 'important');
        });
      });
    })
    """

    /// Extra rules for an exported file: unlike the preview it has no window behind it, so it needs
    /// its own page background, and diagrams (always rendered with the light theme) get a light card.
    private static let standaloneCSS = """
    <style>
      body { background: #fff; max-width: 860px; margin: 0 auto; padding: 24px; }
      figure img { height: auto; }
      @media (prefers-color-scheme: dark) {
        body { background: #1c1c1e; }
        pre.mermaid { background: #fff; border-radius: 0 0 6px 6px; }
      }
    </style>
    """

    /// The full HTML page. With `standaloneTitle` the page is meant to be saved to a file
    /// (HTML export): it gets a `<title>` and the standalone styles.
    func html(for markdown: String, noteID: UUID?, standaloneTitle: String? = nil) -> String {
        let codeFontSize = max(fontSize - 1, 8)
        let standaloneHead = standaloneTitle.map {
            "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n"
                + "<title>\(escape($0))</title>\n" + Self.standaloneCSS
        } ?? ""
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
          body { font-family: "\(fontFamily)", -apple-system, sans-serif; font-size: \(fontSize)px;
                 padding: 16px; color: #1c1c1e; background: transparent; }
          pre  { background: #f5f5f5; border-radius: 0 0 6px 6px; padding: 12px;
                 overflow-x: auto; margin: 0; }
          code { font-family: "SF Mono", Menlo, monospace; font-size: \(codeFontSize)px; }
          p > code { background: #f0f0f0; padding: 2px 4px; border-radius: 4px; }
          blockquote { border-left: 3px solid #ccc; margin: 0; padding-left: 12px;
                       color: #555; }
          hr { border: none; border-top: 1px solid #ddd; }
          table { border-collapse: collapse; width: 100%; }
          th, td { border: 1px solid #ddd; padding: 6px 10px; }
          th { background: #f5f5f5; }
          details { border: 1px solid #ddd; border-radius: 6px; margin: 8px 0; }
          summary { font-family: "SF Mono", Menlo, monospace; font-size: \(max(codeFontSize - 1, 8))px;
                    padding: 6px 10px; cursor: pointer; user-select: none;
                    background: #ececec; border-radius: 6px; list-style: none; }
          details[open] summary { border-radius: 6px 6px 0 0; }
          summary::-webkit-details-marker { display: none; }
          summary::before { content: "▶ "; font-size: 10px; }
          details[open] summary::before { content: "▼ "; }
          figure { margin: 12px 0; }
          figure img { display: block; border-radius: 6px; }
          figcaption { font-size: 12px; color: #888; margin-top: 4px; }
          /* Hidden until mermaid.js replaces the source with an SVG (sets data-processed). */
          pre.mermaid { background: transparent; text-align: center; }
          pre.mermaid:not([data-processed]) { visibility: hidden; }
          .math { font-family: "Times New Roman", Cambria, Georgia, serif; font-style: italic; }
          @media (prefers-color-scheme: dark) {
            body { color: #f2f2f7; }
            pre, p > code { background: #2c2c2e; }
            blockquote { color: #aaa; border-color: #555; }
            th { background: #2c2c2e; }
            th, td { border-color: #444; }
            details { border-color: #444; }
            summary { background: #3a3a3c; }
            figcaption { color: #888; }
          }
        </style>
        \(standaloneHead)
        \(customCSS.map { "<style>\n\($0)\n</style>" } ?? "")
        </head>
        <body>\(renderMarkdown(markdown, noteID: noteID))</body>
        </html>
        """
    }

    private func renderMarkdown(_ md: String, noteID: UUID?) -> String {
        var lines = md.components(separatedBy: "\n")
        var html = ""
        var anchors = HeadingAnchor.Slugger()
        var i = 0

        while i < lines.count {
            let line = lines[i]

            // Fenced code block
            if line.hasPrefix("```") {
                let lang = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var code = ""
                i += 1
                while i < lines.count && !lines[i].hasPrefix("```") {
                    code += escape(lines[i]) + "\n"
                    i += 1
                }
                let label = lang.isEmpty ? "code" : lang
                if Self.mermaidSource != nil, Self.isMermaidFence(line) {
                    // mermaid.js decodes the escaped source from the element and swaps in an SVG.
                    html += "<details open><summary>\(label)</summary><pre class=\"mermaid\">\(code)</pre></details>\n"
                } else {
                    html += "<details open><summary>\(label)</summary><pre><code>\(code)</code></pre></details>\n"
                }
                i += 1
                continue
            }

            // Headings
            if let m = line.range(of: "^(#{1,6}) (.+)$", options: .regularExpression) {
                let hashes = line[line.startIndex..<line.firstIndex(of: " ")!].count
                let text = inline(String(line.dropFirst(hashes + 1)), noteID: noteID)
                // The id only holds letters, digits, `-` and `_`, so it needs no escaping.
                let id = anchors.slug(for: HeadingAnchor.plainText(fromHTML: text))
                html += "<h\(hashes) id=\"\(id)\">\(text)</h\(hashes)>\n"
                i += 1; continue
            }

            // HR
            if line.matches("^(---+|\\*\\*\\*+|___+)$") {
                html += "<hr>\n"; i += 1; continue
            }

            // Blockquote
            if line.hasPrefix("> ") {
                html += "<blockquote>\(inline(String(line.dropFirst(2)), noteID: noteID))</blockquote>\n"
                i += 1; continue
            }

            // Unordered list
            if line.matches("^[\\-\\*\\+] .+") {
                html += "<ul>\n"
                while i < lines.count && lines[i].matches("^[\\-\\*\\+] .+") {
                    html += "<li>\(inline(String(lines[i].dropFirst(2)), noteID: noteID))</li>\n"
                    i += 1
                }
                html += "</ul>\n"; continue
            }

            // Ordered list
            if line.matches("^\\d+\\. .+") {
                html += "<ol>\n"
                while i < lines.count && lines[i].matches("^\\d+\\. .+") {
                    let text = lines[i].components(separatedBy: ". ").dropFirst().joined(separator: ". ")
                    html += "<li>\(inline(text, noteID: noteID))</li>\n"
                    i += 1
                }
                html += "</ol>\n"; continue
            }

            // Table (GFM)
            if i + 1 < lines.count && lines[i + 1].matches("^[\\|\\- :]+$") {
                let headers = lines[i].split(separator: "|", omittingEmptySubsequences: true)
                    .map { inline(String($0).trimmingCharacters(in: .whitespaces), noteID: noteID) }
                html += "<table><thead><tr>" + headers.map { "<th>\($0)</th>" }.joined() + "</tr></thead><tbody>\n"
                i += 2
                while i < lines.count && lines[i].contains("|") {
                    let cells = lines[i].split(separator: "|", omittingEmptySubsequences: true)
                        .map { inline(String($0).trimmingCharacters(in: .whitespaces), noteID: noteID) }
                    html += "<tr>" + cells.map { "<td>\($0)</td>" }.joined() + "</tr>\n"
                    i += 1
                }
                html += "</tbody></table>\n"; continue
            }

            // Blank line
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                html += "<br>\n"; i += 1; continue
            }

            // Paragraph
            html += "<p>\(inline(line, noteID: noteID))</p>\n"
            i += 1
        }
        return html
    }

    // LaTeX-style command -> Unicode symbol, used inside $...$ math spans.
    private static let mathSymbols: [String: String] = [
        // Greek letters
        "alpha": "α", "beta": "β", "gamma": "γ", "rho": "ρ",
        // Binary operators
        "times": "×", "div": "÷", "pm": "±", "mp": "∓",
        // Relation operators
        "leq": "≤", "geq": "≥", "equiv": "≡", "sim": "∼", "simeq": "≃", "approx": "≈", "propto": "∝",
        // Arrow symbols
        "leftarrow": "←", "rightarrow": "→", "leftrightarrow": "↔",
        "leftharpoonup": "↼", "leftharpoondown": "↽", "rightharpoonup": "⇀", "rightharpoondown": "⇁",
        // Other symbols
        "infty": "∞", "pi": "π", "sum": "∑", "prod": "∏", "coprod": "∐", "int": "∫", "oint": "∮",
        "cos": "cos", "ln": "ln",
    ]

    private func renderMathCommands(_ s: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"\\([a-zA-Z]+)"#) else { return s }
        var t = s
        let ns = t as NSString
        let matches = regex.matches(in: t, range: NSRange(t.startIndex..., in: t))
        for match in matches.reversed() {
            let name = ns.substring(with: match.range(at: 1))
            guard let symbol = Self.mathSymbols[name], let range = Range(match.range, in: t) else { continue }
            t.replaceSubrange(range, with: symbol)
        }
        return t
    }

    // Inline formatting
    private func inline(_ s: String, noteID: UUID?) -> String {
        var t = s
        // Inline math: $\command$
        if let regex = try? NSRegularExpression(pattern: #"\$(?!\s)([^\$\n]+?)(?<!\s)\$(?!\d)"#) {
            let ns = t as NSString
            let matches = regex.matches(in: t, range: NSRange(t.startIndex..., in: t))
            for match in matches.reversed() {
                let content = ns.substring(with: match.range(at: 1))
                let rendered = renderMathCommands(content)
                guard let range = Range(match.range, in: t) else { continue }
                t.replaceSubrange(range, with: "<span class=\"math\">\(rendered)</span>")
            }
        }
        // Attachment images: ![title](attachment:filename.png 400x300)
        // dimensions optional: 400x300, 400x, x300, or omitted
        if let noteID {
            let pattern = #"!\[([^\]]*)\]\(attachment:([^\s\)]+)(?:\s+(\d*)x(\d*))?\)"#
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let ns = t as NSString
                let matches = regex.matches(in: t, range: NSRange(t.startIndex..., in: t))
                for match in matches.reversed() {
                    let title    = match.range(at: 1).location != NSNotFound ? ns.substring(with: match.range(at: 1)) : ""
                    let filename = match.range(at: 2).location != NSNotFound ? ns.substring(with: match.range(at: 2)) : ""
                    let wStr     = match.range(at: 3).location != NSNotFound ? ns.substring(with: match.range(at: 3)) : ""
                    let hStr     = match.range(at: 4).location != NSNotFound ? ns.substring(with: match.range(at: 4)) : ""

                    guard let img = ImageStore.load(filename: filename, noteID: noteID),
                          let tiff = img.tiffRepresentation,
                          let rep = NSBitmapImageRep(data: tiff),
                          let png = rep.representation(using: .png, properties: [:]) else { continue }

                    let b64 = png.base64EncodedString()
                    var style = "border-radius:6px;max-width:100%;"
                    if !wStr.isEmpty { style += "width:\(wStr)px;" }
                    if !hStr.isEmpty { style += "height:\(hStr)px;" }

                    let imgTag = "<img src='data:image/png;base64,\(b64)' alt='\(title)' style='\(style)'>"
                    let html = title.isEmpty
                        ? "<figure>\(imgTag)</figure>"
                        : "<figure>\(imgTag)<figcaption>\(title)</figcaption></figure>"

                    if let swiftRange = Range(match.range, in: t) {
                        t.replaceSubrange(swiftRange, with: html)
                    }
                }
            }
        }
        // Bold+italic
        t = t.replacingOccurrences(of: #"\*\*\*(.+?)\*\*\*"#, with: "<strong><em>$1</em></strong>", options: .regularExpression)
        // Bold
        t = t.replacingOccurrences(of: #"\*\*(.+?)\*\*"#, with: "<strong>$1</strong>", options: .regularExpression)
        // Underscore emphasis never opens or closes inside a word (GFM), so
        // identifiers like DIAMETER_UNABLE_TO_DELIVER keep their underscores.
        t = t.replacingOccurrences(of: #"(?<![\p{L}\p{N}_])__(?![\s_])(.+?)(?<![\s_])__(?![\p{L}\p{N}_])"#, with: "<strong>$1</strong>", options: .regularExpression)
        // Italic
        t = t.replacingOccurrences(of: #"\*(.+?)\*"#, with: "<em>$1</em>", options: .regularExpression)
        t = t.replacingOccurrences(of: #"(?<![\p{L}\p{N}_])_(?![\s_])(.+?)(?<![\s_])_(?![\p{L}\p{N}_])"#, with: "<em>$1</em>", options: .regularExpression)
        // Strikethrough
        t = t.replacingOccurrences(of: #"~~(.+?)~~"#, with: "<del>$1</del>", options: .regularExpression)
        // Inline code
        t = t.replacingOccurrences(of: #"`(.+?)`"#, with: "<code>$1</code>", options: .regularExpression)
        // Links
        t = t.replacingOccurrences(of: #"\[(.+?)\]\((.+?)\)"#, with: "<a href=\"$2\">$1</a>", options: .regularExpression)
        // Standard images
        t = t.replacingOccurrences(of: #"!\[(.+?)\]\((.+?)\)"#, with: "<img alt=\"$1\" src=\"$2\">", options: .regularExpression)
        return t
    }

    private func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        /// Set per render; the library is only evaluated on pages that contain a diagram.
        var needsMermaid = false

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard needsMermaid, let source = MarkdownPreview.mermaidSource else { return }
            let run = MarkdownPreview.mermaidRunScript(
                theme: "matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'default'")
            // Trailing `void 0`: the last value (a Promise) can't be bridged back to Swift.
            webView.evaluateJavaScript(source + "\n;" + run + ";\nvoid 0;")
        }

        func webView(_ webView: WKWebView,
                     decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard action.navigationType == .linkActivated,
                  let url = action.request.url else {
                decisionHandler(.allow); return
            }
            decisionHandler(.cancel)
            // In-page `#section` links are scrolled by `anchorLinkScript`; never offer to open them.
            if url.scheme == "about" { return }
            let alert = NSAlert()
            alert.messageText = "Open External Link?"
            alert.informativeText = url.absoluteString
            alert.addButton(withTitle: "Open")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(url)
            }
        }
    }
}

private extension String {
    func matches(_ pattern: String) -> Bool {
        range(of: pattern, options: .regularExpression) != nil
    }
}
