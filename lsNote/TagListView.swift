import SwiftUI

/// "Tags" section of the navigation column: pinned tags first (drag to reorder), then the
/// remaining top-level tags in the chosen sort order, with hierarchy shown as disclosure groups.
struct TagListView: View {
    @EnvironmentObject var store: NoteStore
    @EnvironmentObject var tagMetadata: TagMetadataStore
    @ObservedObject private var settings = AppSettings.shared

    private static let collapsedLimit = 10

    /// Node counts to display (global subtree counts).
    private var counts: [String: Int] {
        store.tagIndex.globalCounts
    }

    var body: some View {
        let roots = store.tagIndex.tree(counts: counts, sortedBy: settings.tagSortMode)
        let nodesByPath = Self.flatten(roots)
        let pinned = tagMetadata.metadata.pinned.compactMap { nodesByPath[$0] }
        let pinnedPaths = Set(pinned.map(\.path))
        let unpinned = roots.filter { !pinnedPaths.contains($0.path) }
        let shown = settings.tagListShowAll ? unpinned : Array(unpinned.prefix(Self.collapsedLimit))

        Section {
            ForEach(pinned) { node in
                TagTreeRow(node: node, showsFullPath: true)
            }
            .onMove { source, destination in
                tagMetadata.movePinned(visible: pinned.map(\.path), fromOffsets: source, toOffset: destination)
            }

            if !pinned.isEmpty, !shown.isEmpty {
                Divider()
            }

            ForEach(shown) { node in
                TagTreeRow(node: node, showsFullPath: false)
            }

            if unpinned.count > Self.collapsedLimit {
                Button(settings.tagListShowAll ? "Show less" : "Show all (\(unpinned.count))") {
                    settings.tagListShowAll.toggle()
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        } header: {
            header
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("Tags")
            Spacer()
            Menu {
                Picker("Sort By", selection: $settings.tagSortMode) {
                    ForEach(TagSortMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Image(systemName: "arrow.up.arrow.down")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Sort tags")
        }
    }

    private static func flatten(_ nodes: [TagNode]) -> [String: TagNode] {
        var result: [String: TagNode] = [:]
        func visit(_ node: TagNode) {
            result[node.path] = node
            node.children.forEach(visit)
        }
        nodes.forEach(visit)
        return result
    }
}

/// A tag row plus, for parents, a disclosure group of its children.
private struct TagTreeRow: View {
    @EnvironmentObject var tagMetadata: TagMetadataStore
    let node: TagNode
    /// Pinned rows show the full path; nested rows show only their own segment.
    let showsFullPath: Bool

    var body: some View {
        if node.children.isEmpty {
            TagRow(node: node, showsFullPath: showsFullPath)
        } else {
            DisclosureGroup(isExpanded: Binding(
                get: { tagMetadata.isExpanded(node.path) },
                set: { tagMetadata.setExpanded(node.path, $0) }
            )) {
                ForEach(node.children) { child in
                    TagTreeRow(node: child, showsFullPath: false)
                }
            } label: {
                TagRow(node: node, showsFullPath: showsFullPath)
            }
        }
    }
}

private struct TagRow: View {
    @EnvironmentObject var store: NoteStore
    @EnvironmentObject var tagMetadata: TagMetadataStore
    let node: TagNode
    let showsFullPath: Bool

    private var isActive: Bool { store.query.activeTags.contains(node.path) }
    private var isPinned: Bool { tagMetadata.isPinned(node.path) }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(tagMetadata.color(for: node.path)?.color ?? .clear)
                .frame(width: 7, height: 7)
            Text(showsFullPath ? node.path : node.name)
                .lineLimit(1)
                .fontWeight(isActive ? .semibold : .regular)
            Spacer(minLength: 4)
            if isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
            }
            Text("\(node.count)")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
        .background(isActive ? Color.accentColor.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 4))
        .contentShape(Rectangle())
        .onTapGesture { store.toggleTagFilter(node.path) }
        .help("#\(node.path)")
        .contextMenu {
            Button(isPinned ? "Unpin" : "Pin") { tagMetadata.togglePin(node.path) }
            Picker("Set Color", selection: Binding(
                get: { tagMetadata.explicitColor(for: node.path) },
                set: { tagMetadata.setColor($0, for: node.path) }
            )) {
                ForEach(TagColor.allCases) { color in
                    Label { Text(color.title) } icon: { Image(nsImage: color.swatch) }
                        .tag(TagColor?.some(color))
                }
                Divider()
                Text("None").tag(TagColor?.none)
            }
            .pickerStyle(.menu)
            Divider()
            Button("Filter Excluding This Tag") { store.excludeTag(node.path) }
        }
    }
}
