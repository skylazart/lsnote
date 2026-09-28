import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var store: NoteStore

    var body: some View {
        let notes = store.filteredNotes
        VStack(spacing: 0) {
            QueryField()

            Divider()

            List(selection: $store.selectedID) {
                Section(store.query.isEmpty ? "Notes" : "Notes · \(notes.count) found") {
                    ForEach(notes) { note in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(note.title)
                            if !note.tags.isEmpty {
                                NoteTagLabels(tags: note.tags)
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
    }
}

/// A note's tags in the list; clicking one makes it the query's tag filter.
private struct NoteTagLabels: View {
    @EnvironmentObject var store: NoteStore
    let tags: [String]

    var body: some View {
        FlowLayout(spacing: 4) {
            ForEach(tags, id: \.self) { tag in
                Text("#\(tag)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .onTapGesture { store.showTag(tag) }
                    .help("Show notes tagged #\(tag)")
            }
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
