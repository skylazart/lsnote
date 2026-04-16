import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct EditorView: View {
    @EnvironmentObject var store: NoteStore
    let note: Note

    @State private var text: String = ""
    @State private var textView: NSTextView? = nil

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            TagBarView(note: note)
            Divider()
            if store.isPreview {
                MarkdownPreview(text: text, note: note)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                MarkdownTextEditor(text: $text) { tv in
                    textView = tv
                }
                .padding(8)
            }
            if !note.attachments.isEmpty {
                Divider()
                AttachmentsView(note: note) { filename in
                    insertAttachmentSyntax(filename)
                }
            }
        }
        .onAppear { text = note.body }
        .onChange(of: note.body) { _, newValue in
            if text != newValue { text = newValue }
        }
        .onChange(of: text) { _, newValue in
            var updated = note
            updated.body = newValue
            store.update(updated)
        }
        .onDisappear {
            store.deleteEmptyNote(id: note.id)
        }
    }

    private func insertAttachmentSyntax(_ filename: String) {
        let snippet = "![](attachment:\(filename))"
        MarkdownTextEditor.insertText(in: textView, text: snippet)
    }

    private func attachImage(_ image: NSImage) {
        guard let filename = ImageStore.save(image, noteID: note.id) else { return }
        var updated = note
        updated.attachments.append(filename)
        store.update(updated)
    }

    private func pasteImage() {
        let pb = NSPasteboard.general
        guard let image = NSImage(pasteboard: pb) else { return }
        attachImage(image)
    }

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .gif, .tiff, .bmp, .heic]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let image = NSImage(contentsOf: url) {
                attachImage(image)
            }
        }
    }

    private var toolbar: some View {
        HStack {
            Text(note.title)
                .font(.headline)
                .padding(.leading, 12)
            Spacer()

            if !store.isPreview {
                Button {
                    MarkdownTextEditor.wrapSelection(in: textView, with: "**")
                } label: {
                    Image(systemName: "bold")
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .help("Bold (⌘B)")
                .keyboardShortcut("b", modifiers: .command)

                Button {
                    MarkdownTextEditor.wrapSelection(in: textView, with: "_")
                } label: {
                    Image(systemName: "italic")
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .help("Italic (⌘I)")
                .keyboardShortcut("i", modifiers: .command)

                Button {
                    MarkdownTextEditor.insertTable(in: textView)
                } label: {
                    Image(systemName: "tablecells")
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .help("Insert Table")

                Button {
                    openFilePicker()
                } label: {
                    Image(systemName: "photo.badge.plus")
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .help("Attach Image")

                Divider().frame(height: 16).padding(.horizontal, 4)
            }

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

struct AttachmentsView: View {
    @EnvironmentObject var store: NoteStore
    let note: Note
    var onInsert: ((String) -> Void)? = nil

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(note.attachments, id: \.self) { filename in
                    AttachmentThumbnail(filename: filename, noteID: note.id,
                                        onInsert: { onInsert?(filename) },
                                        onDelete: { removeAttachment(filename) })
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .frame(height: 80)
        .background(.bar)
    }

    private func removeAttachment(_ filename: String) {
        ImageStore.delete(filename: filename, noteID: note.id)
        var updated = note
        updated.attachments.removeAll { $0 == filename }
        store.update(updated)
    }
}

struct AttachmentThumbnail: View {
    let filename: String
    let noteID: UUID
    let onInsert: () -> Void
    let onDelete: () -> Void

    @State private var image: NSImage? = nil
    @State private var hovered = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let img = image {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 60, height: 60)
                    .clipped()
                    .cornerRadius(6)
                    .onTapGesture { onInsert() }
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 60, height: 60)
                    .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
            }
            if hovered {
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white, .black)
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .offset(x: 6, y: -6)
            }
        }
        .onHover { hovered = $0 }
        .onAppear { image = ImageStore.load(filename: filename, noteID: noteID) }
    }
}
