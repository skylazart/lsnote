import Foundation

struct Note: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String   // date-based, e.g. "Wednesday, March 25 2026"
    var body: String
    var tags: [String]
    var createdAt: Date

    var isEmpty: Bool { body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    init(date: Date = .now) {
        self.id = UUID()
        self.createdAt = date
        self.body = ""
        self.tags = []

        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d yyyy"
        let datePart = f.string(from: date)

        let t = DateFormatter()
        t.dateFormat = "h:mm a"
        self.title = "\(datePart) · \(t.string(from: date))"
    }
}
