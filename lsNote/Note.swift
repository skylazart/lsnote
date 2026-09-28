import Foundation

struct Note: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var body: String
    var tags: [String]
    var attachments: [String]
    var createdAt: Date
    /// Last content change (title, body or tags). Older notes lack the key and fall back to `createdAt`.
    var modifiedAt: Date
    var isLocked: Bool

    var isEmpty: Bool { body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id          = try c.decode(UUID.self,   forKey: .id)
        title       = try c.decode(String.self, forKey: .title)
        body        = try c.decode(String.self, forKey: .body)
        tags        = try c.decode([String].self, forKey: .tags)
        attachments = (try? c.decode([String].self, forKey: .attachments)) ?? []
        createdAt   = try c.decode(Date.self,   forKey: .createdAt)
        modifiedAt  = (try? c.decode(Date.self, forKey: .modifiedAt)) ?? createdAt
        isLocked    = (try? c.decode(Bool.self, forKey: .isLocked)) ?? false
    }

    init(date: Date = .now) {
        self.id = UUID()
        self.createdAt = date
        self.modifiedAt = date
        self.body = ""
        self.tags = []
        self.attachments = []
        self.isLocked = false

        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d yyyy"
        let datePart = f.string(from: date)

        let t = DateFormatter()
        t.dateFormat = "h:mm a"
        self.title = "\(datePart) · \(t.string(from: date))"
    }
}
