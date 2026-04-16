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

    static func insertTable(in textView: NSTextView?) {
        guard let tv = textView else { return }
        let table = "\n| Header 1 | Header 2 | Header 3 |\n| --- | --- | --- |\n| Cell | Cell | Cell |\n"
        let range = tv.selectedRange()
        if tv.shouldChangeText(in: range, replacementString: table) {
            tv.replaceCharacters(in: range, with: table)
            tv.didChangeText()
        }
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
