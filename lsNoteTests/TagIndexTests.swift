import XCTest

final class TagIndexTests: XCTestCase {

    // MARK: Paths

    func testNormalize() {
        XCTAssertEqual(TagPath.normalize(" OCS//Diameter/ "), "ocs/diameter")
        XCTAssertEqual(TagPath.normalize("Rating Group"), "rating-group")
        XCTAssertEqual(TagPath.normalize("/"), "")
    }

    func testAncestors() {
        XCTAssertEqual(TagPath.ancestors(of: "ocs/diameter/ccr"), ["ocs", "ocs/diameter"])
        XCTAssertEqual(TagPath.ancestors(of: "ocs"), [])
    }

    func testSubtreeMembershipRequiresSegmentBoundary() {
        XCTAssertTrue(TagPath.isInSubtree("ocs/diameter", of: "ocs"))
        XCTAssertTrue(TagPath.isInSubtree("ocs", of: "ocs"))
        XCTAssertFalse(TagPath.isInSubtree("ocsx", of: "ocs"))
        XCTAssertFalse(TagPath.isInSubtree("ocs", of: "ocs/diameter"))
    }

    // MARK: Hierarchy

    func testImplicitParentAppearsInHierarchy() {
        let index = TagIndex(notes: [makeNote(["ocs/diameter"]), makeNote(["ocs/sy-interface"])])
        XCTAssertEqual(index.exactTags, ["ocs/diameter", "ocs/sy-interface"])
        XCTAssertTrue(index.allPaths.contains("ocs"))

        let tree = index.tree(counts: index.globalCounts, sortedBy: .alphabetical)
        XCTAssertEqual(tree.map(\.path), ["ocs"])
        XCTAssertEqual(tree[0].count, 2)
        XCTAssertEqual(tree[0].children.map(\.name), ["diameter", "sy-interface"])
    }

    func testSubtreeMatching() {
        let parent = makeNote(["ocs"])
        let child = makeNote(["ocs/diameter"])
        let grandchild = makeNote(["ocs/diameter/ccr"])
        let other = makeNote(["pulse"])
        let index = TagIndex(notes: [parent, child, grandchild, other])

        XCTAssertEqual(index.noteIDs(inSubtree: "ocs"), [parent.id, child.id, grandchild.id])
        XCTAssertEqual(index.noteIDs(inSubtree: "ocs/diameter"), [child.id, grandchild.id])
        XCTAssertEqual(index.noteIDs(inSubtree: "OCS/Diameter"), [child.id, grandchild.id])
        XCTAssertEqual(index.noteIDs(inSubtree: "oc"), [])
    }

    func testParentCountIsDeduplicated() {
        let both = makeNote(["ocs", "ocs/diameter", "ocs/diameter/ccr"])
        let index = TagIndex(notes: [both, makeNote(["ocs/sy"])])
        XCTAssertEqual(index.usageCount("ocs"), 2)
        XCTAssertEqual(index.globalCounts["ocs"], 2)
        XCTAssertEqual(index.globalCounts["ocs/diameter"], 1)
    }

    func testTagsAreCaseInsensitive() {
        let index = TagIndex(notes: [makeNote(["Surf"]), makeNote(["surf"])])
        XCTAssertEqual(index.exactTags, ["surf"])
        XCTAssertEqual(index.usageCount("SURF"), 2)
    }

    func testLastUsedIsLatestInSubtree() {
        let old = makeNote(["ocs"], minutesAgo: 60)
        let recent = makeNote(["ocs/diameter"], minutesAgo: 1)
        let index = TagIndex(notes: [old, recent])
        XCTAssertEqual(index.lastUsed("ocs"), recent.modifiedAt)
        XCTAssertEqual(index.lastUsed("ocs/diameter"), recent.modifiedAt)
    }

    func testSortModes() {
        let notes = [
            makeNote(["alpha"], minutesAgo: 30),
            makeNote(["beta"], minutesAgo: 1),
            makeNote(["gamma"], minutesAgo: 60),
            makeNote(["gamma"], minutesAgo: 50),
        ]
        let index = TagIndex(notes: notes)
        let counts = index.globalCounts
        XCTAssertEqual(index.tree(counts: counts, sortedBy: .frequency).map(\.path), ["gamma", "alpha", "beta"])
        XCTAssertEqual(index.tree(counts: counts, sortedBy: .recent).map(\.path), ["beta", "alpha", "gamma"])
        XCTAssertEqual(index.tree(counts: counts, sortedBy: .alphabetical).map(\.path), ["alpha", "beta", "gamma"])
    }

    // MARK: Facets

    func testFacetsRestrictedToResults() {
        let a = makeNote(["surf", "todo"])
        let b = makeNote(["surf", "ocs/diameter"])
        let c = makeNote(["pulse"])
        let index = TagIndex(notes: [a, b, c])

        let facets = index.facets(for: [a.id, b.id])
        XCTAssertEqual(facets, [
            TagFacet(path: "ocs", count: 1),
            TagFacet(path: "ocs/diameter", count: 1),
            TagFacet(path: "surf", count: 2),
            TagFacet(path: "todo", count: 1),
        ])
    }

    func testFacetsHideZeroCountsButKeepActiveTags() {
        let a = makeNote(["surf"])
        let b = makeNote(["pulse"])
        let index = TagIndex(notes: [a, b])

        let facets = index.facets(for: [a.id], keeping: ["pulse", "missing/tag"])
        XCTAssertEqual(facets, [
            TagFacet(path: "missing/tag", count: 0),
            TagFacet(path: "pulse", count: 0),
            TagFacet(path: "surf", count: 1),
        ])
        XCTAssertFalse(index.facets(for: [a.id]).contains { $0.path == "pulse" })
    }

    func testFacetsForEmptyResults() {
        let index = TagIndex(notes: [makeNote(["surf"])])
        XCTAssertEqual(index.facets(for: []), [])
    }

    // MARK: Incremental updates

    func testIncrementalUpdatesMatchFullRebuild() {
        var notes = [makeNote(["surf"]), makeNote(["ocs/diameter", "todo"]), makeNote([])]
        var index = TagIndex(notes: notes)

        // Add
        let added = makeNote(["ocs", "pulse"])
        notes.append(added)
        index.upsert(added)
        XCTAssertEqual(index, TagIndex(notes: notes))

        // Edit tags (remove one, add one, change case)
        notes[1].tags = ["OCS/Diameter", "shell"]
        index.upsert(notes[1])
        XCTAssertEqual(index, TagIndex(notes: notes))

        // Edit body only (modifiedAt changes, tags don't)
        notes[0].body = "hello"
        notes[0].modifiedAt = .now
        index.upsert(notes[0])
        XCTAssertEqual(index, TagIndex(notes: notes))

        // Delete, including the last note carrying a tag
        index.remove(noteID: added.id)
        notes.removeAll { $0.id == added.id }
        XCTAssertEqual(index, TagIndex(notes: notes))
        XCTAssertNil(index.notesByTag["pulse"])

        // Auto-delete of an empty, untagged note
        index.remove(noteID: notes[2].id)
        notes.remove(at: 2)
        XCTAssertEqual(index, TagIndex(notes: notes))

        // Removing an unknown note is a no-op
        index.remove(noteID: UUID())
        XCTAssertEqual(index, TagIndex(notes: notes))
    }

    // MARK: Model

    func testNoteDecodesWithoutModifiedAt() throws {
        let json = """
        {"id":"D07ADE9C-ED51-43AD-9065-A80C8CB0F2F1","title":"t","attachments":[],"isLocked":false,
         "body":"b","tags":["surf"],"createdAt":801019742.9}
        """
        let note = try JSONDecoder().decode(Note.self, from: Data(json.utf8))
        XCTAssertEqual(note.modifiedAt, note.createdAt)
        XCTAssertEqual(note.tags, ["surf"])
    }
}
