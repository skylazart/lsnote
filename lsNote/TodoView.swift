import SwiftUI

private struct TodoItem: Identifiable {
    let id: Int          // line index in note body
    let text: String
    let done: Bool
}

private func parseTodos(_ body: String) -> [TodoItem] {
    body.components(separatedBy: "\n")
        .enumerated()
        .compactMap { (i, line) in
            if line.hasPrefix("- [ ] ") { return TodoItem(id: i, text: String(line.dropFirst(6)), done: false) }
            if line.hasPrefix("- [x] ") || line.hasPrefix("- [X] ") { return TodoItem(id: i, text: String(line.dropFirst(6)), done: true) }
            return nil
        }
}

struct TodoView: View {
    @EnvironmentObject var store: NoteStore

    private var todoNotes: [Note] {
        store.notes.filter { $0.tags.contains("todo") }
    }

    private var allItems: [(id: String, note: Note, item: TodoItem)] {
        todoNotes.flatMap { note in
            parseTodos(note.body).map { (id: "\(note.id)-\($0.id)", note: note, item: $0) }
        }
    }

    var body: some View {
        let pending = allItems.filter { !$0.item.done }
        let done    = allItems.filter {  $0.item.done }

        List {
            if !pending.isEmpty {
                Section("Pending") {
                    ForEach(pending, id: \.id) { pair in
                        row(pair.note, pair.item)
                    }
                }
            }
            if !done.isEmpty {
                Section("Done") {
                    ForEach(done, id: \.id) { pair in
                        row(pair.note, pair.item)
                    }
                }
            }
            if allItems.isEmpty {
                Text("No TODO items found.\nAdd the #todo tag to a note and write items as:\n- [ ] task")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }
        }
        .navigationTitle("TODO")
    }

    private func row(_ note: Note, _ item: TodoItem) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(item.done ? .green : .secondary)
                .onTapGesture { toggle(note: note, lineIndex: item.id, done: item.done) }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.text)
                    .strikethrough(item.done)
                    .foregroundStyle(item.done ? .secondary : .primary)
                Text(note.title)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { store.selectedID = note.id }
    }

    private func toggle(note: Note, lineIndex: Int, done: Bool) {
        var lines = note.body.components(separatedBy: "\n")
        guard lineIndex < lines.count else { return }
        if done {
            lines[lineIndex] = lines[lineIndex].replacingOccurrences(of: "- [x] ", with: "- [ ] ", range: lines[lineIndex].startIndex..<lines[lineIndex].index(lines[lineIndex].startIndex, offsetBy: 6))
            lines[lineIndex] = lines[lineIndex].replacingOccurrences(of: "- [X] ", with: "- [ ] ", range: lines[lineIndex].startIndex..<lines[lineIndex].index(lines[lineIndex].startIndex, offsetBy: 6))
        } else {
            lines[lineIndex] = lines[lineIndex].replacingOccurrences(of: "- [ ] ", with: "- [X] ", range: lines[lineIndex].startIndex..<lines[lineIndex].index(lines[lineIndex].startIndex, offsetBy: 6))
        }
        var updated = note
        updated.body = lines.joined(separator: "\n")
        store.update(updated)
    }
}
