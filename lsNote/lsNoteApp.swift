import SwiftUI
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    weak var store: NoteStore? {
        didSet {
            guard let store, !pendingURLs.isEmpty else { return }
            let urls = pendingURLs
            pendingURLs = []
            Task { @MainActor in
                for url in urls { store.importNote(from: url) }
            }
        }
    }
    private var pendingURLs: [URL] = []

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let store else {
            pendingURLs.append(contentsOf: urls)
            return
        }
        Task { @MainActor in
            for url in urls { store.importNote(from: url) }
        }
    }
}

@main
struct lsNoteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var store = NoteStore()

    init() {
        UserDefaults.standard.set(0.3, forKey: "NSInitialToolTipDelay")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .onAppear { appDelegate.store = store }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Note") {
                    store.createNote()
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            CommandGroup(replacing: .textEditing) {
                Button("Search") {
                    NotificationCenter.default.post(name: .focusSearch, object: nil)
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])
            }
            CommandGroup(after: .toolbar) {
                Button("Increase Font Size") {
                    AppSettings.shared.increaseFontSize()
                }
                .keyboardShortcut("+", modifiers: .command)
                Button("Decrease Font Size") {
                    AppSettings.shared.decreaseFontSize()
                }
                .keyboardShortcut("-", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
        }
    }
}
