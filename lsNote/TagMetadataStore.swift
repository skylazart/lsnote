import Foundation

/// Per-tag metadata, kept apart from notes.json so the note schema stays untouched.
/// Entries for tags no longer on any note are kept, so re-adding a tag restores its pin and color.
struct TagMetadata: Codable, Equatable {
    /// Pinned tags in user-defined order.
    var pinned: [String] = []
    /// Explicit colors; descendants inherit a parent's color unless they have their own.
    var colors: [String: TagColor] = [:]
    /// Parent tags whose children are shown in the sidebar.
    var expanded: Set<String> = []

    init() {}

    // Every field is optional and unknown color names are skipped, so an older or
    // hand-edited file still loads what it can.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pinned   = (try? c.decode([String].self, forKey: .pinned)) ?? []
        expanded = (try? c.decode(Set<String>.self, forKey: .expanded)) ?? []
        let rawColors = (try? c.decode([String: String].self, forKey: .colors)) ?? [:]
        colors = rawColors.compactMapValues(TagColor.init(rawValue:))
    }
}

@MainActor
final class TagMetadataStore: ObservableObject {
    @Published private(set) var metadata: TagMetadata

    private let url: URL

    nonisolated static let defaultURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("lsNote", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("tags.json")
    }()

    init(url: URL = TagMetadataStore.defaultURL) {
        self.url = url
        self.metadata = Self.load(from: url)
    }

    // MARK: Pins

    func isPinned(_ tag: String) -> Bool {
        metadata.pinned.contains(TagPath.normalize(tag))
    }

    func togglePin(_ tag: String) {
        let tag = TagPath.normalize(tag)
        if let i = metadata.pinned.firstIndex(of: tag) {
            metadata.pinned.remove(at: i)
        } else {
            metadata.pinned.append(tag)
        }
        save()
    }

    /// Reorders pins after a drag in the sidebar. `visible` is the pinned list as shown,
    /// which can be a subset while a filter hides some pins; hidden pins keep their slots.
    func movePinned(visible: [String], fromOffsets source: IndexSet, toOffset destination: Int) {
        // Same semantics as SwiftUI's `move(fromOffsets:toOffset:)`, kept Foundation-only.
        let moving = source.map { visible[$0] }
        var reordered = visible.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        reordered.insert(contentsOf: moving, at: destination - source.count(in: 0..<destination))
        let visibleSet = Set(visible)
        var queue = reordered.makeIterator()
        metadata.pinned = metadata.pinned.map { visibleSet.contains($0) ? (queue.next() ?? $0) : $0 }
        save()
    }

    // MARK: Colors

    /// The tag's own color, or the nearest ancestor's.
    func color(for tag: String) -> TagColor? {
        let tag = TagPath.normalize(tag)
        for path in [tag] + TagPath.ancestors(of: tag).reversed() {
            if let color = metadata.colors[path] { return color }
        }
        return nil
    }

    func explicitColor(for tag: String) -> TagColor? {
        metadata.colors[TagPath.normalize(tag)]
    }

    func setColor(_ color: TagColor?, for tag: String) {
        metadata.colors[TagPath.normalize(tag)] = color
        save()
    }

    // MARK: Expansion

    func isExpanded(_ tag: String) -> Bool {
        metadata.expanded.contains(TagPath.normalize(tag))
    }

    func setExpanded(_ tag: String, _ expanded: Bool) {
        let tag = TagPath.normalize(tag)
        guard metadata.expanded.contains(tag) != expanded else { return }
        if expanded { metadata.expanded.insert(tag) } else { metadata.expanded.remove(tag) }
        save()
    }

    // MARK: Persistence

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(metadata) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Missing file → defaults. Unreadable file → defaults, after moving it to
    /// `tags.json.corrupt` so the next save doesn't destroy it.
    static func load(from url: URL) -> TagMetadata {
        guard let data = try? Data(contentsOf: url) else { return TagMetadata() }
        if let metadata = try? JSONDecoder().decode(TagMetadata.self, from: data) { return metadata }
        let backup = url.appendingPathExtension("corrupt")
        try? FileManager.default.removeItem(at: backup)
        try? FileManager.default.moveItem(at: url, to: backup)
        return TagMetadata()
    }
}
