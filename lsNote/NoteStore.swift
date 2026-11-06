import Foundation

@MainActor
class NoteStore: ObservableObject {
    @Published var notes: [Note] = []
    @Published var selectedID: UUID?
    @Published var isPreview: Bool = false
    /// Tag → notes index, maintained incrementally by every mutation below.
    @Published private(set) var tagIndex = TagIndex()
    /// Sidebar search; drives the note list and the tag list's counts.
    @Published var query = SearchQuery()
    @Published var sidebarSelection: SidebarSelection = .notes
    /// Bumped by `clearQuery()` so the search field also drops its uncommitted text.
    @Published private(set) var queryClearCount = 0

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

    var filteredNotes: [Note] {
        query.evaluate(notes, index: tagIndex)
    }

    /// Clicking a tag in the note list or a note header: that tag replaces the tag filter.
    func showTag(_ tag: String) {
        query.replaceTags(with: tag)
        sidebarSelection = .notes
    }

    /// Clicking a tag in the sidebar tag list: add it to the query, or remove it if active.
    func toggleTagFilter(_ tag: String) {
        query.toggle(tag: tag)
        sidebarSelection = .notes
    }

    func clearQuery() {
        query = SearchQuery()
        queryClearCount += 1
    }

    func excludeTag(_ tag: String) {
        query.exclude(tag: tag)
        sidebarSelection = .notes
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

    /// Applies `change` to the current stored note. Views pass a closure rather than a whole
    /// `Note` so a copy captured in an earlier render can't overwrite newer edits.
    /// Saving is debounced: this runs on every keystroke.
    func update(_ id: UUID, _ change: (inout Note) -> Void) {
        guard let idx = notes.firstIndex(where: { $0.id == id }) else { return }
        let old = notes[idx]
        var note = old
        change(&note)
        guard note != old else { return }
        if note.body != old.body || note.title != old.title || note.tags != old.tags {
            note.modifiedAt = .now
        }
        notes[idx] = note
        tagIndex.upsert(note)
        scheduleSave()
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

    /// Writes notes.json now, replacing any pending debounced save. Call before anything
    /// reads the file (backup) and on quit.
    func save() {
        pendingSave?.cancel()
        pendingSave = nil
        guard let data = try? JSONEncoder().encode(notes) else { return }
        try? data.write(to: saveURL, options: .atomic)
    }

    private var pendingSave: Task<Void, Never>?

    private func scheduleSave() {
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(750))
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: saveURL),
              let decoded = try? JSONDecoder().decode([Note].self, from: data) else { return }
        notes = decoded
        tagIndex = TagIndex(notes: decoded)
        selectedID = notes.first?.id
    }
}
