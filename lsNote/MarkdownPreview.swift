import SwiftUI
import WebKit

/// Renders GitHub-flavored Markdown using a lightweight inline HTML renderer.
struct MarkdownPreview: NSViewRepresentable {
    let text: String
    var note: Note? = nil

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let view = WKWebView(frame: .zero, configuration: config)
        view.setValue(false, forKey: "drawsBackground")
        return view
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(html(for: text, attachments: note?.attachments ?? [], noteID: note?.id),
                               baseURL: nil)
    }

    // MARK: - Minimal GFM renderer

    private func html(for markdown: String, attachments: [String], noteID: UUID?) -> String {
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
          body { font-family: -apple-system, sans-serif; font-size: 14px;
                 padding: 16px; color: #1c1c1e; background: transparent; }
          pre  { background: #f5f5f5; border-radius: 0 0 6px 6px; padding: 12px;
                 overflow-x: auto; margin: 0; }
          code { font-family: "SF Mono", Menlo, monospace; font-size: 13px; }
          p > code { background: #f0f0f0; padding: 2px 4px; border-radius: 4px; }
          blockquote { border-left: 3px solid #ccc; margin: 0; padding-left: 12px;
                       color: #555; }
          hr { border: none; border-top: 1px solid #ddd; }
          table { border-collapse: collapse; width: 100%; }
          th, td { border: 1px solid #ddd; padding: 6px 10px; }
          th { background: #f5f5f5; }
          details { border: 1px solid #ddd; border-radius: 6px; margin: 8px 0; }
          summary { font-family: "SF Mono", Menlo, monospace; font-size: 12px;
                    padding: 6px 10px; cursor: pointer; user-select: none;
                    background: #ececec; border-radius: 6px; list-style: none; }
          details[open] summary { border-radius: 6px 6px 0 0; }
          summary::-webkit-details-marker { display: none; }
          summary::before { content: "▶ "; font-size: 10px; }
          details[open] summary::before { content: "▼ "; }
          figure { margin: 12px 0; }
          figure img { display: block; border-radius: 6px; }
          figcaption { font-size: 12px; color: #888; margin-top: 4px; }
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
        </head>
        <body>\(renderMarkdown(markdown, noteID: noteID))</body>
        </html>
        """
    }

    private func renderMarkdown(_ md: String, noteID: UUID?) -> String {
        var lines = md.components(separatedBy: "\n")
        var html = ""
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
                html += "<details open><summary>\(label)</summary><pre><code>\(code)</code></pre></details>\n"
                i += 1
                continue
            }

            // Headings
            if let m = line.range(of: "^(#{1,6}) (.+)$", options: .regularExpression) {
                let hashes = line[line.startIndex..<line.firstIndex(of: " ")!].count
                let text = inline(String(line.dropFirst(hashes + 1)), noteID: noteID)
                html += "<h\(hashes)>\(text)</h\(hashes)>\n"
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

    // Inline formatting
    private func inline(_ s: String, noteID: UUID?) -> String {
        var t = s
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
        t = t.replacingOccurrences(of: #"__(.+?)__"#, with: "<strong>$1</strong>", options: .regularExpression)
        // Italic
        t = t.replacingOccurrences(of: #"\*(.+?)\*"#, with: "<em>$1</em>", options: .regularExpression)
        t = t.replacingOccurrences(of: #"_(.+?)_"#, with: "<em>$1</em>", options: .regularExpression)
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
}

private extension String {
    func matches(_ pattern: String) -> Bool {
        range(of: pattern, options: .regularExpression) != nil
    }
}
