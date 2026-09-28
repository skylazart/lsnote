import Foundation

/// One tag condition of a query. Tags are normalized paths; each matches its whole subtree.
enum TagClause: Hashable {
    /// Note has at least one of these tags (`#ocs|#pulse`).
    case anyOf([String])
    /// Note has none of this tag's subtree (`-#todo`).
    case excluding(String)

    var tags: [String] {
        switch self {
        case .anyOf(let tags):    return tags
        case .excluding(let tag): return [tag]
        }
    }

    var isExclusion: Bool {
        if case .excluding = self { return true }
        return false
    }

    /// Query-syntax form, e.g. `#ocs|#pulse` or `-#todo`.
    var text: String {
        switch self {
        case .anyOf(let tags):    return tags.map { "#\($0)" }.joined(separator: "|")
        case .excluding(let tag): return "-#\(tag)"
        }
    }
}

/// Structured sidebar search. All top-level clauses are ANDed:
/// `#surf -#todo quota "rating group"` → tagged surf, not todo, containing both texts.
/// Pure value type: no UI, no storage.
struct SearchQuery: Equatable {
    var tagClauses: [TagClause] = []
    /// Lowercased free-text words, matched against title and body.
    var terms: [String] = []
    /// Lowercased exact phrases (from `"…"`), matched against title and body.
    var phrases: [String] = []

    var includedTagGroups: [[String]] {
        tagClauses.compactMap { if case .anyOf(let tags) = $0 { return tags } else { return nil } }
    }

    var excludedTags: [String] {
        tagClauses.compactMap { if case .excluding(let tag) = $0 { return tag } else { return nil } }
    }

    /// Every tag mentioned by the query, included or excluded.
    var activeTags: Set<String> { Set(tagClauses.flatMap(\.tags)) }

    var hasText: Bool { !terms.isEmpty || !phrases.isEmpty }
    var isEmpty: Bool { tagClauses.isEmpty && !hasText }

    // MARK: Parsing

    static func parse(_ string: String) -> SearchQuery {
        var query = SearchQuery()
        for token in tokenize(string) {
            switch token.kind {
            case .tags(let clauses): clauses.forEach { query.append($0) }
            case .term(let term):    query.terms.append(term)
            case .phrase(let text):  query.phrases.append(text)
            case .ignored:           break
            }
        }
        return query
    }

    struct Token: Equatable {
        enum Kind: Equatable {
            case tags([TagClause])
            case term(String)
            case phrase(String)
            case ignored
        }
        let raw: String
        let kind: Kind
        /// Followed by whitespace, i.e. the user has finished typing it.
        let isTerminated: Bool
    }

    /// Splits on whitespace; a token starting with `"` runs to the closing quote
    /// (or the end of input when unclosed).
    static func tokenize(_ string: String) -> [Token] {
        var tokens: [Token] = []
        let chars = Array(string)
        var i = 0
        while i < chars.count {
            if chars[i].isWhitespace { i += 1; continue }
            let start = i
            if chars[i] == "\"" {
                i += 1
                while i < chars.count, chars[i] != "\"" { i += 1 }
                let inner = String(chars[(start + 1)..<i]).trimmingCharacters(in: .whitespaces).lowercased()
                if i < chars.count { i += 1 } // closing quote
                let raw = String(chars[start..<i])
                tokens.append(Token(raw: raw,
                                    kind: inner.isEmpty ? .ignored : .phrase(inner),
                                    isTerminated: i < chars.count))
            } else {
                while i < chars.count, !chars[i].isWhitespace { i += 1 }
                let raw = String(chars[start..<i])
                tokens.append(Token(raw: raw, kind: classify(raw), isTerminated: i < chars.count))
            }
        }
        return tokens
    }

    private static func classify(_ word: String) -> Token.Kind {
        if word.hasPrefix("-#") {
            let tags = tagList(word.dropFirst(2))
            return tags.isEmpty ? .ignored : .tags(tags.map { .excluding($0) })
        }
        if word.hasPrefix("#") {
            let tags = tagList(word.dropFirst())
            return tags.isEmpty ? .ignored : .tags([.anyOf(tags)])
        }
        if word == "-" { return .ignored }
        return .term(word.lowercased())
    }

    /// `ocs|#pulse|#` → `["ocs", "pulse"]`. Parts starting with `-` are dropped:
    /// a negation inside an OR group has no meaning here.
    private static func tagList(_ text: Substring) -> [String] {
        var seen = Set<String>()
        return text.split(separator: "|").compactMap { part in
            let stripped = part.drop { $0 == "#" }
            guard !stripped.hasPrefix("-") else { return nil }
            let tag = TagPath.normalize(String(stripped))
            guard !tag.isEmpty, seen.insert(tag).inserted else { return nil }
            return tag
        }
    }

    // MARK: Editing

    /// Appends a clause unless it is already present.
    mutating func append(_ clause: TagClause) {
        guard !tagClauses.contains(clause) else { return }
        tagClauses.append(clause)
    }

    /// Replaces the tag filter with a single tag and keeps the free text
    /// (clicking a tag in the note list or note header).
    mutating func replaceTags(with tag: String) {
        tagClauses = [.anyOf([TagPath.normalize(tag)])]
    }

    /// Removes the tag from every clause it appears in; OR groups shrink, emptied clauses go away.
    mutating func remove(tag: String) {
        let tag = TagPath.normalize(tag)
        tagClauses = tagClauses.compactMap { clause in
            switch clause {
            case .excluding(let t): return t == tag ? nil : clause
            case .anyOf(let tags):
                let rest = tags.filter { $0 != tag }
                return rest.isEmpty ? nil : .anyOf(rest)
            }
        }
    }

    /// Sidebar click: an active tag is removed, any other tag is ANDed in.
    mutating func toggle(tag: String) {
        let tag = TagPath.normalize(tag)
        if activeTags.contains(tag) {
            remove(tag: tag)
        } else {
            append(.anyOf([tag]))
        }
    }

    /// Adds `-#tag`, dropping any inclusion of the same tag.
    mutating func exclude(tag: String) {
        let tag = TagPath.normalize(tag)
        remove(tag: tag)
        append(.excluding(tag))
    }

    /// Replaces the free-text part with the terms and phrases of `string`
    /// (tag tokens in it are ignored; those become clauses via `extractTags`).
    mutating func setText(_ string: String) {
        let parsed = SearchQuery.parse(string)
        terms = parsed.terms
        phrases = parsed.phrases
    }

    // MARK: Evaluation

    /// Tag clauses are resolved with set operations on the index first; text matching
    /// then runs only over the remaining candidates. Preserves the order of `notes`.
    func evaluate(_ notes: [Note], index: TagIndex) -> [Note] {
        guard !isEmpty else { return notes }

        var candidates: Set<UUID>? = nil
        for group in includedTagGroups {
            let ids = group.reduce(into: Set<UUID>()) { $0.formUnion(index.noteIDs(inSubtree: $1)) }
            candidates = candidates.map { $0.intersection(ids) } ?? ids
        }
        let excluded = excludedTags.reduce(into: Set<UUID>()) { $0.formUnion(index.noteIDs(inSubtree: $1)) }
        let needles = terms + phrases

        return notes.filter { note in
            if let candidates, !candidates.contains(note.id) { return false }
            if excluded.contains(note.id) { return false }
            return needles.allSatisfy { needle in
                note.title.range(of: needle, options: .caseInsensitive) != nil
                    || note.body.range(of: needle, options: .caseInsensitive) != nil
            }
        }
    }
}

// MARK: - Search field text helpers

extension SearchQuery {
    /// Pulls tag tokens out of the field text so they can become chips.
    /// Only tokens followed by whitespace are taken, unless `includeTrailing` is set (Return).
    /// Returns nil when there is nothing to extract, so the caller leaves the text untouched.
    static func extractTags(from text: String, includeTrailing: Bool = false) -> (clauses: [TagClause], remaining: String)? {
        var clauses: [TagClause] = []
        var kept: [String] = []
        for token in tokenize(text) {
            if case .tags(let found) = token.kind, token.isTerminated || includeTrailing {
                clauses.append(contentsOf: found)
            } else {
                kept.append(token.raw)
            }
        }
        guard !clauses.isEmpty else { return nil }
        var remaining = kept.joined(separator: " ")
        if !remaining.isEmpty, text.last?.isWhitespace == true { remaining += " " }
        return (clauses, remaining)
    }

    struct CompletionContext: Equatable {
        /// What the user typed after the `#`, lowercased.
        let prefix: String
        let isExclusion: Bool
    }

    /// The tag being typed at the end of the text (`#su`, `-#to`, `#ocs|#pu`), if any.
    static func completionContext(in text: String) -> CompletionContext? {
        guard let last = text.last, !last.isWhitespace else { return nil }
        guard text.filter({ $0 == "\"" }).count % 2 == 0 else { return nil } // inside a phrase
        let word = text.split(whereSeparator: \.isWhitespace).last.map(String.init) ?? ""
        let isExclusion = word.hasPrefix("-#")
        guard isExclusion || word.hasPrefix("#") else { return nil }
        let part = word.split(separator: "|", omittingEmptySubsequences: false).last ?? ""
        let prefix = part.drop { $0 == "#" || $0 == "-" }
        return CompletionContext(prefix: prefix.lowercased().replacingOccurrences(of: " ", with: "-"),
                                 isExclusion: isExclusion)
    }

    /// Replaces the tag being typed with `tag` and terminates the token, so a following
    /// `extractTags` turns it into a chip.
    static func applyingCompletion(_ tag: String, to text: String) -> String {
        guard completionContext(in: text) != nil else { return text }
        var head = text
        while let c = head.last, c != "|", !c.isWhitespace { head.removeLast() }
        if head.last == "|" {
            return head + "#" + tag + " "
        }
        let word = text[head.endIndex...]
        return head + (word.hasPrefix("-#") ? "-#" : "#") + tag + " "
    }
}

// MARK: - Autocomplete ranking

struct TagSuggestion: Equatable {
    let path: String
    let count: Int
}

enum TagSuggester {
    /// Ranks tags for `prefix`: full-path prefix, then path-segment prefix (`diam` → `ocs/diameter`),
    /// then subsequence ("fuzzy") matches; ties broken by usage count, then name.
    static func rank(_ prefix: String, counts: [String: Int], excluding: Set<String> = [], limit: Int = 8) -> [TagSuggestion] {
        let p = prefix.lowercased()
        let scored: [(tier: Int, suggestion: TagSuggestion)] = counts.compactMap { path, count in
            guard !excluding.contains(path) else { return nil }
            let tier: Int
            if p.isEmpty || path.hasPrefix(p) {
                tier = 0
            } else if segmentSuffixes(of: path).contains(where: { $0.hasPrefix(p) }) {
                tier = 1
            } else if isSubsequence(p, of: path) {
                tier = 2
            } else {
                return nil
            }
            return (tier, TagSuggestion(path: path, count: count))
        }
        return scored.sorted { a, b in
            if a.tier != b.tier { return a.tier < b.tier }
            if a.suggestion.count != b.suggestion.count { return a.suggestion.count > b.suggestion.count }
            return a.suggestion.path < b.suggestion.path
        }
        .prefix(limit)
        .map(\.suggestion)
    }

    /// `ocs/diameter/ccr` → `["diameter/ccr", "ccr"]`.
    private static func segmentSuffixes(of path: String) -> [String] {
        let segments = TagPath.segments(of: path)
        return (1..<max(segments.count, 1)).map { segments[$0...].joined(separator: "/") }
    }

    private static func isSubsequence(_ needle: String, of haystack: String) -> Bool {
        var it = haystack.makeIterator()
        return needle.allSatisfy { c in
            while let h = it.next() { if h == c { return true } }
            return false
        }
    }
}
