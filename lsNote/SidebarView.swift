import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var store: NoteStore
    @State private var query = ""

    private var filtered: [Note] {
        guard !query.isEmpty else { return store.notes }
        let q = query.lowercased()
        return store.notes.filter {
            $0.title.lowercased().contains(q) || $0.body.lowercased().contains(q)
        }
    }

    var body: some View {
        List(selection: $store.selectedID) {
            ForEach(filtered) { note in
                Text(note.title)
                    .tag(note.id)
                    .contextMenu {
                        Button("Delete", role: .destructive) {
                            store.delete(id: note.id)
                        }
                    }
            }
        }
        .searchable(text: $query, placement: .sidebar, prompt: "Search notes")
        .navigationTitle("Notes")
        .toolbar {
            ToolbarItem {
                Button(action: store.createNote) {
                    Label("New Note", systemImage: "square.and.pencil")
                }
            }
        }
    }
}
