import Foundation

struct Note: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String   // date-based, e.g. "Wednesday, March 25 2026"
    var body: String
    var createdAt: Date

    var isEmpty: Bool { body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    init(date: Date = .now) {
        self.id = UUID()
        self.createdAt = date
        self.body = ""

        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d yyyy"
        self.title = f.string(from: date)
    }
}
