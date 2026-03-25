import SwiftUI

struct EditorView: View {
    @EnvironmentObject var store: NoteStore
    let note: Note

    @State private var text: String = ""
    @State private var isPreview = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if isPreview {
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
            Picker("", selection: $isPreview) {
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
