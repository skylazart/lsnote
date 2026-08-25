import SwiftUI
import AppKit

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @AppStorage("editorFontName") var fontName: String = NSFont.monospacedSystemFont(ofSize: 0, weight: .regular).fontName {
        didSet { objectWillChange.send() }
    }
    @AppStorage("editorFontSize") var fontSize: Double = Double(NSFont.systemFontSize) {
        didSet { objectWillChange.send() }
    }
    /// Column editing: when a line is shorter than the target column,
    /// insert at the end of that line instead of skipping it.
    @AppStorage("columnInsertAtLineEnd") var columnInsertAtLineEnd: Bool = false {
        didSet { objectWillChange.send() }
    }
    /// Path to a user-chosen .css file whose rules are appended to the Markdown preview's
    /// stylesheet, letting custom rules override the built-in ones via cascade order.
    @AppStorage("customPreviewCSSPath") var customCSSPath: String = "" {
        didSet { objectWillChange.send() }
    }

    var font: NSFont {
        NSFont(name: fontName, size: fontSize) ?? .monospacedSystemFont(ofSize: fontSize, weight: .regular)
    }

    /// CSS-usable family name (e.g. "Menlo" rather than the PostScript name "Menlo-Regular"),
    /// for use in the Markdown preview's WKWebView, which can't resolve PostScript names reliably.
    var cssFontFamily: String {
        font.familyName ?? fontName
    }

    var customCSS: String? {
        guard !customCSSPath.isEmpty else { return nil }
        return try? String(contentsOf: URL(fileURLWithPath: customCSSPath), encoding: .utf8)
    }

    func increaseFontSize() { fontSize = min(fontSize + 1, 72) }
    func decreaseFontSize() { fontSize = max(fontSize - 1, 8) }
}
