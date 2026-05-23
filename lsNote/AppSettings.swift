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

    var font: NSFont {
        NSFont(name: fontName, size: fontSize) ?? .monospacedSystemFont(ofSize: fontSize, weight: .regular)
    }

    func increaseFontSize() { fontSize = min(fontSize + 1, 72) }
    func decreaseFontSize() { fontSize = max(fontSize - 1, 8) }
}
