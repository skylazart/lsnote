import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: NoteStore

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            if let id = store.selectedID,
               let note = store.notes.first(where: { $0.id == id }) {
                EditorView(note: note)
                    .id(id)
            } else {
                Text("No note selected")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 700, minHeight: 450)
    }
}
