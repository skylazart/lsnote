import Foundation

@MainActor
class NoteStore: ObservableObject {
    @Published var notes: [Note] = []
    @Published var selectedID: UUID?

    private let saveURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("lsNote", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("notes.json")
    }()

    init() { load() }

    var selectedNote: Note? {
        get { notes.first { $0.id == selectedID } }
    }

    func createNote() {
        let today = Calendar.current.startOfDay(for: .now)
        if let existing = notes.first(where: { Calendar.current.startOfDay(for: $0.createdAt) == today }) {
            selectedID = existing.id
            return
        }
        let note = Note()
        notes.insert(note, at: 0)
        selectedID = note.id
        save()
    }

    func update(_ note: Note) {
        guard let idx = notes.firstIndex(where: { $0.id == note.id }) else { return }
        notes[idx] = note
        save()
    }

    func deleteEmptyNote(id: UUID) {
        guard let note = notes.first(where: { $0.id == id }), note.isEmpty else { return }
        notes.removeAll { $0.id == id }
        if selectedID == id { selectedID = notes.first?.id }
        save()
    }

    func delete(id: UUID) {
        notes.removeAll { $0.id == id }
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
        selectedID = notes.first?.id
    }
}
