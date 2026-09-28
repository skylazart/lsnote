import Foundation

/// Builds a note with the given tags/body; `minutesAgo` sets `modifiedAt` deterministically.
func makeNote(_ tags: [String], title: String = "", body: String = "", minutesAgo: Double = 0) -> Note {
    let date = Date(timeIntervalSinceReferenceDate: 1_000_000 - minutesAgo * 60)
    var note = Note(date: date)
    note.title = title
    note.body = body
    note.tags = tags
    return note
}
