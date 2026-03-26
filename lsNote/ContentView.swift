import SwiftUI

enum SidebarSelection: Hashable {
    case notes
    case todo
}

struct ContentView: View {
    @EnvironmentObject var store: NoteStore
    @State private var sidebarSelection: SidebarSelection = .notes

    var body: some View {
        NavigationSplitView {
            List(selection: $sidebarSelection) {
                NavigationLink(value: SidebarSelection.notes) {
                    Label("Notes", systemImage: "note.text")
                }
                NavigationLink(value: SidebarSelection.todo) {
                    Label("TODO", systemImage: "checklist")
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("lsNote")
        } content: {
            switch sidebarSelection {
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
