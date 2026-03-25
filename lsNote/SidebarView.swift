import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var store: NoteStore
    @State private var query = ""
    @State private var selectedTag: String? = nil

    private var filtered: [Note] {
        store.notes.filter { note in
            let matchesTag = selectedTag == nil || note.tags.contains(selectedTag!)
            guard matchesTag else { return false }
            guard !query.isEmpty else { return true }
            let q = query.lowercased()
            return note.title.lowercased().contains(q)
                || note.body.lowercased().contains(q)
                || note.tags.contains(where: { $0.lowercased().contains(q) })
        }
    }

    var body: some View {
        List(selection: $store.selectedID) {
            if !store.allTags.isEmpty {
                Section("Tags") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(store.allTags, id: \.self) { tag in
                                Text("#\(tag)")
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(selectedTag == tag ? Color.accentColor : Color.secondary.opacity(0.15))
                                    .foregroundStyle(selectedTag == tag ? .white : .primary)
                                    .clipShape(Capsule())
                                    .onTapGesture {
                                        selectedTag = selectedTag == tag ? nil : tag
                                    }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
                }
            }

            Section("Notes") {
                ForEach(filtered) { note in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(note.title)
                        if !note.tags.isEmpty {
                            Text(note.tags.map { "#\($0)" }.joined(separator: " "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tag(note.id)
                    .contextMenu {
                        Button("Delete", role: .destructive) {
                            store.delete(id: note.id)
                        }
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
