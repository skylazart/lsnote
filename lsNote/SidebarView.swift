import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var store: NoteStore
    @State private var query = ""
    @State private var selectedTag: String? = nil
    @FocusState private var searchFocused: Bool

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
        VStack(spacing: 0) {
            // Search field
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search", text: $query)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(7)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            List(selection: $store.selectedID) {
                if !store.allTags.isEmpty {
                    Section("Tags") {
                        FlowLayout(spacing: 6) {
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
                        .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
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
        }
        .navigationTitle("Notes")
        .toolbar {
            ToolbarItem {
                Button(action: store.createNote) {
                    Label("New Note", systemImage: "square.and.pencil")
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusSearch)) { _ in
            searchFocused = true
        }
    }
}

extension Notification.Name {
    static let focusSearch = Notification.Name("focusSearch")
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(subviews: subviews, width: proposal.width ?? 0).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(subviews: subviews, width: bounds.width)
        for (i, pos) in result.positions.enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + pos.x, y: bounds.minY + pos.y), proposal: .unspecified)
        }
    }

    private func layout(subviews: Subviews, width: CGFloat) -> (size: CGSize, positions: [CGPoint]) {
        var positions: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x)
        }
        return (CGSize(width: maxX, height: y + rowHeight), positions)
    }
}
