import SwiftUI

@main
struct lsNoteApp: App {
    @StateObject private var store = NoteStore()

    init() {
        UserDefaults.standard.set(0.3, forKey: "NSInitialToolTipDelay")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
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
