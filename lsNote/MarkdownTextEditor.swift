import SwiftUI
import AppKit

struct MarkdownTextEditor: NSViewRepresentable {
    @Binding var text: String
    var onTextViewReady: (NSTextView) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let tv = scrollView.documentView as! NSTextView
        tv.delegate = context.coordinator
        tv.isRichText = false
        tv.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.allowsUndo = true
        DispatchQueue.main.async { onTextViewReady(tv) }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let tv = scrollView.documentView as! NSTextView
        if tv.string != text {
            let sel = tv.selectedRange()
            tv.string = text
            tv.setSelectedRange(sel)
        }
    }

    // MARK: - Formatting helpers

    static func wrapSelection(in textView: NSTextView?, with marker: String) {
        guard let tv = textView else { return }
        let range = tv.selectedRange()
        let selected = (tv.string as NSString).substring(with: range)
        let replacement = "\(marker)\(selected)\(marker)"
        if tv.shouldChangeText(in: range, replacementString: replacement) {
            tv.replaceCharacters(in: range, with: replacement)
            tv.didChangeText()
            if range.length == 0 {
                tv.setSelectedRange(NSRange(location: range.location + marker.count, length: 0))
            }
        }
    }

    static func insertText(in textView: NSTextView?, text: String) {
        guard let tv = textView else { return }
        let range = tv.selectedRange()
        if tv.shouldChangeText(in: range, replacementString: text) {
            tv.replaceCharacters(in: range, with: text)
            tv.didChangeText()
        }
    }

    static func insertCodeBlock(in textView: NSTextView?) {
        guard let tv = textView else { return }
        let range = tv.selectedRange()
        let selected = (tv.string as NSString).substring(with: range)
        let replacement = "```\n\(selected)\n```"
        if tv.shouldChangeText(in: range, replacementString: replacement) {
            tv.replaceCharacters(in: range, with: replacement)
            tv.didChangeText()
            if range.length == 0 {
                tv.setSelectedRange(NSRange(location: range.location + 4, length: 0))
            }
        }
    }

    static func insertLink(in textView: NSTextView?) {
        guard let tv = textView else { return }
        let range = tv.selectedRange()
        let selected = (tv.string as NSString).substring(with: range)
        let replacement = "[\(selected)](url)"
        if tv.shouldChangeText(in: range, replacementString: replacement) {
            tv.replaceCharacters(in: range, with: replacement)
            tv.didChangeText()
            // Select "url" placeholder
            let urlStart = range.location + 1 + selected.count + 2
            tv.setSelectedRange(NSRange(location: urlStart, length: 3))
        }
    }

    static func insertTable(in textView: NSTextView?) {
        guard let tv = textView else { return }
        let table = "\n| Header 1 | Header 2 | Header 3 |\n| --- | --- | --- |\n| Cell | Cell | Cell |\n"
        let range = tv.selectedRange()
        if tv.shouldChangeText(in: range, replacementString: table) {
            tv.replaceCharacters(in: range, with: table)
            tv.didChangeText()
        }
    }

    // MARK: - Find helpers

    /// Highlights all occurrences of `query` and scrolls to the `matchIndex`-th one (0-based).
    /// Returns the total number of matches.
    @discardableResult
    static func findAndHighlight(in textView: NSTextView?, query: String, matchIndex: Int) -> Int {
        guard let tv = textView else { return 0 }
        let layoutManager = tv.layoutManager!
        let fullRange = NSRange(location: 0, length: (tv.string as NSString).length)

        // Clear previous highlights
        layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: fullRange)

        guard !query.isEmpty else { return 0 }

        var ranges: [NSRange] = []
        let nsString = tv.string as NSString
        var searchRange = NSRange(location: 0, length: nsString.length)
        while searchRange.location < nsString.length {
            let found = nsString.range(of: query,
                                       options: [.caseInsensitive],
                                       range: searchRange)
            guard found.location != NSNotFound else { break }
            ranges.append(found)
            searchRange = NSRange(location: found.location + found.length,
                                  length: nsString.length - found.location - found.length)
        }

        for (i, r) in ranges.enumerated() {
            let color: NSColor = i == matchIndex ? .systemOrange : NSColor.systemYellow.withAlphaComponent(0.5)
            layoutManager.addTemporaryAttribute(.backgroundColor, value: color, forCharacterRange: r)
        }

        if !ranges.isEmpty {
            let idx = ((matchIndex % ranges.count) + ranges.count) % ranges.count
            tv.scrollRangeToVisible(ranges[idx])
            tv.setSelectedRange(ranges[idx])
        }

        return ranges.count
    }

    static func clearHighlights(in textView: NSTextView?) {
        guard let tv = textView else { return }
        let fullRange = NSRange(location: 0, length: (tv.string as NSString).length)
        tv.layoutManager?.removeTemporaryAttribute(.backgroundColor, forCharacterRange: fullRange)
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownTextEditor
        init(_ parent: MarkdownTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
        }
    }
}
