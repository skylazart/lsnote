import SwiftUI

enum SidebarSelection: Hashable {
    case notes
    case todo
}

struct ContentView: View {
    @EnvironmentObject var store: NoteStore

    var body: some View {
        NavigationSplitView {
            List(selection: $store.sidebarSelection) {
                NavigationLink(value: SidebarSelection.notes) {
                    Label("Notes", systemImage: "note.text")
                }
                NavigationLink(value: SidebarSelection.todo) {
                    Label("TODO", systemImage: "checklist")
                }
                TagListView()
            }
            .listStyle(.sidebar)
            .navigationTitle("lsNote")
            .navigationSplitViewColumnWidth(min: 170, ideal: 210)
        } content: {
            switch store.sidebarSelection {
            case .notes: SidebarView()
            case .todo:  TodoView()
            }
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
        .frame(minWidth: 800, minHeight: 450)
    }
}
