import Foundation

/// Tag path helpers. A tag is a single string; `/` separates hierarchy levels
/// (`ocs/diameter`), so the hierarchy is derived and never stored.
enum TagPath {
    static let separator: Character = "/"

    /// Lowercases, turns spaces into hyphens and drops empty segments,
    /// so `" OCS//Diameter/ "` becomes `ocs/diameter`.
    static func normalize(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .split(separator: separator, omittingEmptySubsequences: true)
            .joined(separator: String(separator))
    }

    /// `ocs/diameter/ccr` → `["ocs", "ocs/diameter"]`.
    static func ancestors(of path: String) -> [String] {
        let segments = path.split(separator: separator)
        guard segments.count > 1 else { return [] }
        return (1..<segments.count).map { segments[0..<$0].joined(separator: String(separator)) }
    }

    static func parent(of path: String) -> String? {
        ancestors(of: path).last
    }

    static func name(of path: String) -> String {
        path.split(separator: separator).last.map(String.init) ?? path
    }

    static func segments(of path: String) -> [String] {
        path.split(separator: separator).map(String.init)
    }

    /// True when `path` is `ancestor` itself or lives in its subtree.
    static func isInSubtree(_ path: String, of ancestor: String) -> Bool {
        path == ancestor || path.hasPrefix(ancestor + String(separator))
    }
}

/// Count of notes carrying a tag (or any descendant), restricted to some result set.
struct TagFacet: Equatable {
    let path: String
    let count: Int
}

/// One node of the derived tag hierarchy, ready for display.
struct TagNode: Identifiable, Equatable {
    var id: String { path }
    let path: String
    let count: Int
    let lastUsed: Date?
    var children: [TagNode]

    var name: String { TagPath.name(of: path) }
}

enum TagSortMode: String, CaseIterable, Identifiable {
    case frequency, recent, alphabetical
    var id: String { rawValue }

    var title: String {
        switch self {
        case .frequency:    return "Frequency"
        case .recent:       return "Recently Used"
        case .alphabetical: return "Alphabetical"
        }
    }
}

/// In-memory tag → notes index, independent of the UI. Built once from all notes and
/// kept current with `upsert` / `remove` so it is never rebuilt on a keystroke.
struct TagIndex: Equatable {
    /// Exact tag → notes carrying exactly that tag.
    private(set) var notesByTag: [String: Set<UUID>] = [:]
    /// Note → its normalized tags; used to diff on update.
    private(set) var tagsByNote: [UUID: Set<String>] = [:]
    /// Note → last modification, for "recently used" ordering.
    private(set) var modifiedByNote: [UUID: Date] = [:]

    init() {}

    init(notes: [Note]) {
        for note in notes { upsert(note) }
    }

    // MARK: Mutation

    mutating func upsert(_ note: Note) {
        modifiedByNote[note.id] = note.modifiedAt
        let newTags = Set(note.tags.map(TagPath.normalize).filter { !$0.isEmpty })
        let oldTags = tagsByNote[note.id] ?? []
        guard newTags != oldTags || tagsByNote[note.id] == nil else { return }

        for tag in oldTags.subtracting(newTags) {
            notesByTag[tag]?.remove(note.id)
            if notesByTag[tag]?.isEmpty == true { notesByTag[tag] = nil }
        }
        for tag in newTags.subtracting(oldTags) {
            notesByTag[tag, default: []].insert(note.id)
        }
        tagsByNote[note.id] = newTags
    }

    mutating func remove(noteID: UUID) {
        modifiedByNote[noteID] = nil
        guard let tags = tagsByNote.removeValue(forKey: noteID) else { return }
        for tag in tags {
            notesByTag[tag]?.remove(noteID)
            if notesByTag[tag]?.isEmpty == true { notesByTag[tag] = nil }
        }
    }

    // MARK: Queries

    /// Tags used directly on at least one note.
    var exactTags: [String] { notesByTag.keys.sorted() }

    /// Every node in the hierarchy: exact tags plus their implicit parents.
    var allPaths: Set<String> {
        var paths = Set(notesByTag.keys)
        for tag in notesByTag.keys { paths.formUnion(TagPath.ancestors(of: tag)) }
        return paths
    }

    /// Notes tagged `tag` or any descendant of it.
    func noteIDs(inSubtree tag: String) -> Set<UUID> {
        let tag = TagPath.normalize(tag)
        var ids = Set<UUID>()
        for (path, notes) in notesByTag where TagPath.isInSubtree(path, of: tag) {
            ids.formUnion(notes)
        }
        return ids
    }

    /// Distinct notes in the tag's subtree (a note tagged `ocs` and `ocs/diameter` counts once for `ocs`).
    func usageCount(_ tag: String) -> Int {
        noteIDs(inSubtree: tag).count
    }

    /// Latest `modifiedAt` among notes in the tag's subtree.
    func lastUsed(_ tag: String) -> Date? {
        noteIDs(inSubtree: tag).compactMap { modifiedByNote[$0] }.max()
    }

    /// Subtree counts for every hierarchy node, over all notes.
    var globalCounts: [String: Int] {
        subtreeCounts(restrictedTo: nil)
    }

    /// Counts restricted to `resultIDs`. Zero-count tags are dropped unless listed in `keeping`
    /// (tags that are part of the active query stay visible even with no matches).
    func facets(for resultIDs: Set<UUID>, keeping active: Set<String> = []) -> [TagFacet] {
        let counts = subtreeCounts(restrictedTo: resultIDs)
        var facets = counts.filter { $0.value > 0 }.map { TagFacet(path: $0.key, count: $0.value) }
        for tag in active.map(TagPath.normalize) where (counts[tag] ?? 0) == 0 {
            facets.append(TagFacet(path: tag, count: 0))
        }
        return facets.sorted { $0.path < $1.path }
    }

    private func subtreeCounts(restrictedTo resultIDs: Set<UUID>?) -> [String: Int] {
        // Collect distinct notes per node by walking each exact tag up to its root.
        var members: [String: Set<UUID>] = [:]
        for (tag, notes) in notesByTag {
            let scoped = resultIDs.map { notes.intersection($0) } ?? notes
            for path in [tag] + TagPath.ancestors(of: tag) {
                members[path, default: []].formUnion(scoped)
            }
        }
        return members.mapValues(\.count)
    }

    // MARK: Hierarchy

    /// Builds the tree for the given node counts. Ancestors of any listed path are
    /// added (with their own count, or 0) so every node has a parent to hang from.
    func tree(counts: [String: Int], sortedBy mode: TagSortMode) -> [TagNode] {
        var paths = Set(counts.keys)
        for path in counts.keys { paths.formUnion(TagPath.ancestors(of: path)) }

        var childrenOf: [String: [String]] = [:]
        var roots: [String] = []
        for path in paths {
            if let parent = TagPath.parent(of: path) {
                childrenOf[parent, default: []].append(path)
            } else {
                roots.append(path)
            }
        }

        func build(_ path: String) -> TagNode {
            TagNode(path: path,
                    count: counts[path] ?? 0,
                    lastUsed: lastUsed(path),
                    children: TagIndex.sorted((childrenOf[path] ?? []).map(build), by: mode))
        }
        return TagIndex.sorted(roots.map(build), by: mode)
    }

    static func sorted(_ nodes: [TagNode], by mode: TagSortMode) -> [TagNode] {
        nodes.sorted { a, b in
            switch mode {
            case .frequency:
                if a.count != b.count { return a.count > b.count }
            case .recent:
                let da = a.lastUsed ?? .distantPast, db = b.lastUsed ?? .distantPast
                if da != db { return da > db }
            case .alphabetical:
                break
            }
            return a.path < b.path
        }
    }
}
