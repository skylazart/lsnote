import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct EditorView: View {
    @EnvironmentObject var store: NoteStore
    @ObservedObject private var settings = AppSettings.shared
    let note: Note

    @State private var text: String = ""
    @State private var textView: NSTextView? = nil
    @State private var showFind = false
    @State private var findQuery = ""
    @State private var matchIndex = 0
    @State private var matchCount = 0
    @State private var multiCursorStatus: String? = nil

    private var isLocked: Bool { note.isLocked }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            TagBarView(note: note)
            Divider()
            if showFind {
                FindBarView(
                    query: $findQuery,
                    matchIndex: $matchIndex,
                    matchCount: matchCount,
                    onNext: { stepMatch(by: 1) },
                    onPrev: { stepMatch(by: -1) },
                    onClose: { closeFindBar() }
                )
                Divider()
            }
            if isLocked {
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill").font(.caption)
                    Text("Locked for editing").font(.caption)
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(Color.yellow.opacity(0.15))
                Divider()
            }
            if store.isPreview {
                MarkdownPreview(text: text, note: note)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                MarkdownTextEditor(text: $text,
                                   isLocked: isLocked,
                                   font: settings.font,
                                   columnInsertAtLineEnd: settings.columnInsertAtLineEnd,
                                   onMultiCursorStatus: { multiCursorStatus = $0 }) { tv in
                    textView = tv
                }
                .padding(8)
                .overlay(alignment: .bottomTrailing) {
                    if let status = multiCursorStatus {
                        Text(status)
                            .font(.caption)
                            .monospacedDigit()
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.regularMaterial, in: Capsule())
                            .padding(12)
                            .allowsHitTesting(false)
                    }
                }
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
        .onChange(of: findQuery) { _, _ in
            matchIndex = 0
            runFind()
        }
        .onDisappear {
            store.deleteEmptyNote(id: note.id)
        }
        .background(findShortcutCapture)
    }

    // Invisible view that captures ⌘F without conflicting with the sidebar search
    private var findShortcutCapture: some View {
        Button("") { openFindBar() }
            .keyboardShortcut("f", modifiers: .command)
            .frame(width: 0, height: 0)
            .opacity(0)
    }

    private func openFindBar() {
        showFind = true
    }

    private func closeFindBar() {
        showFind = false
        findQuery = ""
        matchCount = 0
        MarkdownTextEditor.clearHighlights(in: textView)
    }

    private func runFind() {
        matchCount = MarkdownTextEditor.findAndHighlight(in: textView, query: findQuery, matchIndex: matchIndex)
    }

    private func stepMatch(by delta: Int) {
        guard matchCount > 0 else { return }
        matchIndex = ((matchIndex + delta) % matchCount + matchCount) % matchCount
        runFind()
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
                    openFindBar()
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .help("Find in Note (⌘F)")

                Button {
                    var updated = note
                    updated.isLocked.toggle()
                    store.update(updated)
                } label: {
                    Image(systemName: isLocked ? "lock.fill" : "lock.open")
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .help(isLocked ? "Unlock Editing" : "Lock Editing")

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
                    MarkdownTextEditor.insertCodeBlock(in: textView)
                } label: {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .help("Code Block (⌘')")
                .keyboardShortcut("'", modifiers: .command)

                Button {
                    openFilePicker()
                } label: {
                    Image(systemName: "photo.badge.plus")
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .help("Attach Image")

                Button {
                    MarkdownTextEditor.insertTable(in: textView)
                } label: {
                    Image(systemName: "tablecells")
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .help("Insert Table")

                Button {
                    MarkdownTextEditor.insertLink(in: textView)
                } label: {
                    Image(systemName: "link")
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .help("Insert Link (⌘L)")
                .keyboardShortcut("l", modifiers: .command)

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

struct FindBarView: View {
    @Binding var query: String
    @Binding var matchIndex: Int
    let matchCount: Int
    let onNext: () -> Void
    let onPrev: () -> Void
    let onClose: () -> Void

    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Find in note…", text: $query)
                .textFieldStyle(.plain)
                .focused($focused)
                .onSubmit { onNext() }
                .frame(minWidth: 160)
            if matchCount > 0 {
                Text("\(matchIndex + 1)/\(matchCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            } else if !query.isEmpty {
                Text("No results")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button(action: onPrev) { Image(systemName: "chevron.up") }
                .buttonStyle(.plain).help("Previous match")
            Button(action: onNext) { Image(systemName: "chevron.down") }
                .buttonStyle(.plain).help("Next match")
            Button(action: onClose) { Image(systemName: "xmark") }
                .buttonStyle(.plain).help("Close (Esc)")
                .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.bar)
        .onAppear { focused = true }
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
