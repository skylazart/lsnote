import Foundation

@MainActor
class NoteStore: ObservableObject {
    @Published var notes: [Note] = []
    @Published var selectedID: UUID?
    @Published var isPreview: Bool = false
    /// Tag → notes index, maintained incrementally by every mutation below.
    @Published private(set) var tagIndex = TagIndex()

    private let saveURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("lsNote", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("notes.json")
    }()

    init() { load() }

    var allTags: [String] {
        tagIndex.exactTags
    }

    var selectedNote: Note? {
        get { notes.first { $0.id == selectedID } }
    }

    func createNote() {
        let note = Note()
        notes.insert(note, at: 0)
        tagIndex.upsert(note)
        selectedID = note.id
        save()
    }

    func update(_ note: Note) {
        guard let idx = notes.firstIndex(where: { $0.id == note.id }) else { return }
        var note = note
        let old = notes[idx]
        if note.body != old.body || note.title != old.title || note.tags != old.tags {
            note.modifiedAt = .now
        }
        notes[idx] = note
        tagIndex.upsert(note)
        save()
    }

    func deleteEmptyNote(id: UUID) {
        guard let note = notes.first(where: { $0.id == id }), note.isEmpty else { return }
        ImageStore.deleteAll(noteID: id)
        notes.removeAll { $0.id == id }
        tagIndex.remove(noteID: id)
        if selectedID == id { selectedID = notes.first?.id }
        save()
    }

    func importNote(from url: URL) {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return }
        var note = Note()
        note.title = url.deletingPathExtension().lastPathComponent
        note.body = content
        notes.insert(note, at: 0)
        tagIndex.upsert(note)
        selectedID = note.id
        save()
    }

    func delete(id: UUID) {
        ImageStore.deleteAll(noteID: id)
        notes.removeAll { $0.id == id }
        tagIndex.remove(noteID: id)
        if selectedID == id { selectedID = notes.first?.id }
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(notes) else { return }
        try? data.write(to: saveURL)
    }

    private func load() {
        guard let data = try? Data(contentsOf: saveURL),
              let decoded = try? JSONDecoder().decode([Note].self, from: data) else { return }
        notes = decoded
        tagIndex = TagIndex(notes: decoded)
        selectedID = notes.first?.id
    }
}
