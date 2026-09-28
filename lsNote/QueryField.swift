import SwiftUI

/// Sidebar search field: tag clauses of `store.query` render as removable chips, followed by a
/// text field for free text. Typing `#` or `-#` opens tag suggestions; accepting one (or finishing
/// a tag token with a space) turns it into a chip. Free text is applied after a short debounce.
struct QueryField: View {
    @EnvironmentObject var store: NoteStore
    @EnvironmentObject var tagMetadata: TagMetadataStore

    @State private var text = ""
    @FocusState private var focused: Bool
    @State private var highlightedIndex: Int? = nil
    @State private var suggestionsDismissed = false
    @State private var backspaceMonitor: Any?

    private static let debounce: Duration = .milliseconds(150)

    private var context: SearchQuery.CompletionContext? {
        SearchQuery.completionContext(in: text)
    }

    private var suggestions: [TagSuggestion] {
        guard focused, !suggestionsDismissed, let context else { return [] }
        return TagSuggester.rank(context.prefix,
                                 counts: store.tagIndex.globalCounts,
                                 excluding: store.query.activeTags)
    }

    var body: some View {
        VStack(spacing: 0) {
            fieldRow
            // Inline rather than an overlay: the AppKit-backed note list below would cover an overlay.
            if !suggestions.isEmpty {
                suggestionList
                    .padding(.horizontal, 6)
                    .padding(.bottom, 6)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .onChange(of: text) { _, newText in
            highlightedIndex = nil
            suggestionsDismissed = false
            if let extracted = SearchQuery.extractTags(from: newText) {
                extracted.clauses.forEach { store.query.append($0) }
                text = extracted.remaining
            }
        }
        .task(id: text) {
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled else { return }
            applyText()
        }
        .onChange(of: store.queryClearCount) { _, _ in text = "" }
        .onReceive(NotificationCenter.default.publisher(for: .focusSearch)) { _ in
            focused = true
        }
        .onAppear(perform: installBackspaceMonitor)
        .onDisappear {
            if let backspaceMonitor { NSEvent.removeMonitor(backspaceMonitor) }
            backspaceMonitor = nil
        }
    }

    /// The field editor swallows Backspace before `onKeyPress` sees it, so watch key events
    /// directly: Backspace in the empty, focused field removes the last chip.
    private func installBackspaceMonitor() {
        guard backspaceMonitor == nil else { return }
        backspaceMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 51, focused, deleteBackward() == .handled else { return event } // 51 = Backspace
            return nil
        }
    }

    private var fieldRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)

            ChipFieldLayout(spacing: 4) {
                ForEach(store.query.tagClauses, id: \.self) { clause in
                    QueryChip(clause: clause) { removeClause(clause) }
                }
                TextField(store.query.tagClauses.isEmpty ? "Search  #tag  -#tag" : "", text: $text)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit(submit)
                    .onKeyPress(.downArrow) { moveHighlight(1) }
                    .onKeyPress(.upArrow) { moveHighlight(-1) }
                    .onKeyPress(.tab) { acceptSuggestion() }
                    .onKeyPress(.escape) { escape() }
            }

            if !store.query.isEmpty || !text.isEmpty {
                Button(action: clearAll) {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }
        }
        .padding(7)
    }

    private var suggestionList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(suggestions.enumerated()), id: \.element.path) { index, suggestion in
                Button {
                    accept(suggestion)
                } label: {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(tagMetadata.color(for: suggestion.path)?.color ?? .clear)
                            .frame(width: 6, height: 6)
                        Text((context?.isExclusion == true ? "−#" : "#") + suggestion.path)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text("\(suggestion.count)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(index == highlightedIndex ? Color.accentColor.opacity(0.25) : Color.clear)
                .onHover { hovering in
                    if hovering { highlightedIndex = index }
                }
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
    }

    // MARK: Actions

    /// Pushes the free-text part of the field into the query (tag tokens still being typed are ignored).
    private func applyText() {
        var updated = store.query
        updated.setText(text)
        if updated != store.query { store.query = updated }
    }

    private func accept(_ suggestion: TagSuggestion) {
        text = SearchQuery.applyingCompletion(suggestion.path, to: text)
    }

    private func submit() {
        if !suggestions.isEmpty {
            accept(suggestions[highlightedIndex ?? 0])
            return
        }
        // Return also commits a typed tag that has no suggestion (e.g. a tag not used yet).
        if let extracted = SearchQuery.extractTags(from: text, includeTrailing: true) {
            extracted.clauses.forEach { store.query.append($0) }
            text = extracted.remaining
        }
        applyText()
    }

    private func removeClause(_ clause: TagClause) {
        store.query.tagClauses.removeAll { $0 == clause }
    }

    private func clearAll() {
        text = ""
        store.clearQuery()
    }

    private func moveHighlight(_ delta: Int) -> KeyPress.Result {
        guard !suggestions.isEmpty else { return .ignored }
        let count = suggestions.count
        if let current = highlightedIndex {
            highlightedIndex = (current + delta + count) % count
        } else {
            highlightedIndex = delta > 0 ? 0 : count - 1
        }
        return .handled
    }

    private func acceptSuggestion() -> KeyPress.Result {
        guard !suggestions.isEmpty else { return .ignored }
        accept(suggestions[highlightedIndex ?? 0])
        return .handled
    }

    /// Esc closes the suggestion list first; with no list open it clears the whole search.
    private func escape() -> KeyPress.Result {
        if !suggestions.isEmpty {
            suggestionsDismissed = true
            highlightedIndex = nil
            return .handled
        }
        guard !store.query.isEmpty || !text.isEmpty else { return .ignored }
        clearAll()
        return .handled
    }

    /// Backspace with nothing typed removes the last chip.
    private func deleteBackward() -> KeyPress.Result {
        guard text.isEmpty, let last = store.query.tagClauses.last else { return .ignored }
        removeClause(last)
        return .handled
    }
}

/// A tag clause as a capsule: `#ocs`, `#ocs | #pulse`, or a struck-through `−#todo`.
struct QueryChip: View {
    @EnvironmentObject var tagMetadata: TagMetadataStore
    let clause: TagClause
    let onRemove: () -> Void

    private var label: String {
        switch clause {
        case .anyOf(let tags):    return tags.map { "#\($0)" }.joined(separator: " | ")
        case .excluding(let tag): return "−#\(tag)"
        }
    }

    var body: some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.caption)
                .strikethrough(clause.isExclusion)
                .lineLimit(1)
            Button(action: onRemove) {
                Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .tagCapsule(clause.tags.lazy.compactMap(tagMetadata.color(for:)).first,
                    neutralFill: clause.isExclusion ? Color.red.opacity(0.12) : Color.accentColor.opacity(0.15))
        .help(clause.text)
    }
}

/// Flow layout whose last subview (the text field) stretches over the rest of its row,
/// wrapping to a full-width row of its own when less than `minLastWidth` is left.
private struct ChipFieldLayout: Layout {
    var spacing: CGFloat = 4
    var minLastWidth: CGFloat = 80

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 240
        return CGSize(width: width, height: frames(subviews: subviews, width: width).map(\.maxY).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, frame) in zip(subviews, frames(subviews: subviews, width: bounds.width)) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                          proposal: ProposedViewSize(frame.size))
        }
    }

    private func frames(subviews: Subviews, width: CGFloat) -> [CGRect] {
        var frames: [CGRect] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for (i, subview) in subviews.enumerated() {
            let isLast = i == subviews.count - 1
            var size = subview.sizeThatFits(.unspecified)
            if isLast {
                if width - x < minLastWidth, x > 0 { x = 0; y += rowHeight + spacing; rowHeight = 0 }
                size.width = width - x
                size.height = subview.sizeThatFits(ProposedViewSize(width: size.width, height: nil)).height
            } else if x + size.width > width, x > 0 {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            size.width = min(size.width, width)
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
        // Vertically center items within their row so chips line up with the text field.
        var result: [CGRect] = []
        var rowStart = 0
        for i in frames.indices {
            let endsRow = i == frames.count - 1 || frames[i + 1].minY != frames[i].minY
            guard endsRow else { continue }
            let row = frames[rowStart...i]
            let height = row.map(\.height).max() ?? 0
            result += row.map { $0.offsetBy(dx: 0, dy: (height - $0.height) / 2) }
            rowStart = i + 1
        }
        return result
    }
}
