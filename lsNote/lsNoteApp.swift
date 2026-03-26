import SwiftUI

@main
struct lsNoteApp: App {
    @StateObject private var store = NoteStore()

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
        }
    }
}
