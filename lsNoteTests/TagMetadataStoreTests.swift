import XCTest

@MainActor
final class TagMetadataStoreTests: XCTestCase {
    private var dir: URL!
    private var url: URL { dir.appendingPathComponent("tags.json") }

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    func testRoundTrip() {
        let store = TagMetadataStore(url: url)
        store.togglePin("Surf")
        store.togglePin("ocs")
        store.setColor(.blue, for: "ocs")
        store.setExpanded("ocs", true)

        let reloaded = TagMetadataStore(url: url)
        XCTAssertEqual(reloaded.metadata, store.metadata)
        XCTAssertEqual(reloaded.metadata.pinned, ["surf", "ocs"])
        XCTAssertEqual(reloaded.explicitColor(for: "ocs"), .blue)
        XCTAssertTrue(reloaded.isExpanded("ocs"))
    }

    func testMissingFileFallsBackToDefaults() {
        let store = TagMetadataStore(url: url)
        XCTAssertEqual(store.metadata, TagMetadata())
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testCorruptFileFallsBackToDefaultsAndIsPreserved() throws {
        try Data("{ not json".utf8).write(to: url)
        let store = TagMetadataStore(url: url)
        XCTAssertEqual(store.metadata, TagMetadata())
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.appendingPathExtension("corrupt").path))

        store.togglePin("surf")
        XCTAssertEqual(TagMetadataStore(url: url).metadata.pinned, ["surf"])
    }

    func testWrongShapeIsTreatedAsCorrupt() throws {
        try Data("[1, 2, 3]".utf8).write(to: url)
        XCTAssertEqual(TagMetadataStore(url: url).metadata, TagMetadata())
    }

    func testPartialFileKeepsValidFields() throws {
        try Data(#"{"pinned":["surf"],"colors":{"ocs":"blue","x":"chartreuse"},"expanded":42}"#.utf8).write(to: url)
        let metadata = TagMetadataStore(url: url).metadata
        XCTAssertEqual(metadata.pinned, ["surf"])
        XCTAssertEqual(metadata.colors, ["ocs": .blue])
        XCTAssertEqual(metadata.expanded, [])
    }

    func testColorInheritance() {
        let store = TagMetadataStore(url: url)
        store.setColor(.green, for: "ocs")
        store.setColor(.red, for: "ocs/diameter")
        XCTAssertEqual(store.color(for: "ocs/sy"), .green)
        XCTAssertEqual(store.color(for: "ocs/diameter/ccr"), .red)
        XCTAssertEqual(store.color(for: "OCS/Diameter"), .red)
        XCTAssertNil(store.color(for: "pulse"))
        XCTAssertNil(store.explicitColor(for: "ocs/sy"))

        store.setColor(nil, for: "ocs/diameter")
        XCTAssertEqual(store.color(for: "ocs/diameter"), .green)
    }

    func testTogglePinTwiceUnpins() {
        let store = TagMetadataStore(url: url)
        store.togglePin("surf")
        store.togglePin("surf")
        XCTAssertFalse(store.isPinned("surf"))
    }

    func testMovePinnedKeepsHiddenPinsInPlace() {
        let store = TagMetadataStore(url: url)
        ["a", "b", "c", "d"].forEach(store.togglePin)
        // "b" is hidden by a filter; drag "d" to the top of the visible list.
        store.movePinned(visible: ["a", "c", "d"], fromOffsets: [2], toOffset: 0)
        XCTAssertEqual(store.metadata.pinned, ["d", "b", "a", "c"])
    }

    func testMetadataForAbsentTagsIsKept() {
        let store = TagMetadataStore(url: url)
        store.setColor(.pink, for: "gone")
        store.togglePin("gone")
        // Nothing prunes metadata; a later reload still has it.
        let reloaded = TagMetadataStore(url: url)
        XCTAssertEqual(reloaded.explicitColor(for: "gone"), .pink)
        XCTAssertTrue(reloaded.isPinned("gone"))
    }
}
