import SwiftUI

struct EditorView: View {
    @EnvironmentObject var store: NoteStore
    let note: Note

    @State private var text: String = ""

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            TagBarView(note: note)
            Divider()
            if store.isPreview {
                MarkdownPreview(text: text)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TextEditor(text: $text)
                    .font(.system(.body, design: .monospaced))
                    .padding(8)
            }
        }
        .onAppear { text = note.body }
        .onChange(of: text) { _, newValue in
            var updated = note
            updated.body = newValue
            store.update(updated)
        }
        .onDisappear {
            store.deleteEmptyNote(id: note.id)
        }
    }

    private var toolbar: some View {
        HStack {
            Text(note.title)
                .font(.headline)
                .padding(.leading, 12)
            Spacer()
            Picker("", selection: $store.isPreview) {
                Label("Edit", systemImage: "pencil").tag(false)
                Label("Preview", systemImage: "eye").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(width: 140)
            .padding(.trailing, 8)
        }
        .frame(height: 36)
        .background(.bar)
    }
}

struct TagBarView: View {
    @EnvironmentObject var store: NoteStore
    let note: Note

    @State private var newTag = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(note.tags, id: \.self) { tag in
                    HStack(spacing: 3) {
                        Text("#\(tag)").font(.caption)
                        Button {
                            removeTag(tag)
                        } label: {
                            Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.15))
                    .clipShape(Capsule())
                }

                TextField("Add tag…", text: $newTag)
                    .font(.caption)
                    .frame(width: 80)
                    .focused($inputFocused)
                    .onSubmit { commitTag() }
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
        }
        .frame(height: 30)
        .background(.bar)
    }

    private func commitTag() {
        let tag = newTag.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
        guard !tag.isEmpty, !note.tags.contains(tag) else { newTag = ""; return }
        var updated = note
        updated.tags.append(tag)
        store.update(updated)
        newTag = ""
    }

    private func removeTag(_ tag: String) {
        var updated = note
        updated.tags.removeAll { $0 == tag }
        store.update(updated)
    }
}
