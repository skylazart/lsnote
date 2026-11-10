import XCTest

final class NoteExportTests: XCTestCase {
    private var dir: URL!
    private let fm = FileManager.default

    override func setUp() {
        super.setUp()
        dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? fm.removeItem(at: dir)
        super.tearDown()
    }

    // MARK: File names

    func testFileNameReplacesIllegalCharactersAndDedupes() {
        var taken = Set<String>()
        let note = makeNote([], title: "Wednesday, March 25 2026 · 3:45 PM")
        XCTAssertEqual(MarkdownExport.fileName(for: note, taken: &taken), "Wednesday, March 25 2026 · 3-45 PM.md")
        XCTAssertEqual(MarkdownExport.fileName(for: note, taken: &taken), "Wednesday, March 25 2026 · 3-45 PM 2.md")

        let upper = makeNote([], title: "WEDNESDAY, MARCH 25 2026 · 3:45 PM")
        XCTAssertEqual(MarkdownExport.fileName(for: upper, taken: &taken), "WEDNESDAY, MARCH 25 2026 · 3-45 PM 3.md")
    }

    func testFileNameFallbacks() {
        var taken = Set<String>()
        XCTAssertEqual(MarkdownExport.fileName(for: makeNote([], title: "  "), taken: &taken), "Untitled.md")
        XCTAssertEqual(MarkdownExport.fileName(for: makeNote([], title: "..hidden"), taken: &taken), "hidden.md")
        XCTAssertEqual(MarkdownExport.fileName(for: makeNote([], title: "a/b\nc"), taken: &taken), "a-b-c.md")
        XCTAssertEqual(MarkdownExport.fileName(for: makeNote([], title: "a/b\nc"), taken: &taken, pathExtension: "html"),
                       "a-b-c.html")
    }

    // MARK: Document

    func testDocumentHasFrontMatterAndRewritesAttachments() {
        let note = makeNote(["ocs/diameter", "todo"], title: #"Say "hi""#,
                            body: "Intro\n![Diagram](attachment:a.png 400x300)\n![](attachment:b.png)\n![again](attachment:a.png)\n![web](https://x/y.png)")
        let (text, files) = MarkdownExport.document(for: note)

        XCTAssertTrue(text.hasPrefix("---\ntitle: \"Say \\\"hi\\\"\"\ntags: [\"ocs/diameter\", \"todo\"]\ncreated: "))
        XCTAssertTrue(text.contains("\n---\n\nIntro\n"))
        XCTAssertTrue(text.contains("![Diagram](attachments/a.png)\n![](attachments/b.png)\n![again](attachments/a.png)"))
        XCTAssertTrue(text.hasSuffix("![web](https://x/y.png)"))
        XCTAssertFalse(text.contains("attachment:"))
        XCTAssertEqual(files, ["a.png", "b.png"])
    }

    func testDocumentWithoutTagsOmitsTagsLine() {
        let (text, files) = MarkdownExport.document(for: makeNote([], title: "t", body: "body"))
        XCTAssertFalse(text.contains("tags:"))
        XCTAssertTrue(text.hasSuffix("---\n\nbody"))
        XCTAssertEqual(files, [])
    }

    // MARK: Export

    func testExportWritesFilesAndCopiesExistingAttachments() throws {
        let root = dir.appendingPathComponent("attachments-src", isDirectory: true)
        let out = dir.appendingPathComponent("out", isDirectory: true)
        let note = makeNote([], title: "With image", body: "![](attachment:a.png) ![](attachment:missing.png)")
        let noteDir = root.appendingPathComponent(note.id.uuidString, isDirectory: true)
        try fm.createDirectory(at: noteDir, withIntermediateDirectories: true)
        try Data("png".utf8).write(to: noteDir.appendingPathComponent("a.png"))

        let written = try MarkdownExport.export([note, makeNote([], title: "With image")], to: out, attachmentsRoot: root)

        XCTAssertEqual(written.map(\.lastPathComponent), ["With image.md", "With image 2.md"])
        XCTAssertEqual(try Data(contentsOf: out.appendingPathComponent("attachments/a.png")), Data("png".utf8))
        XCTAssertFalse(fm.fileExists(atPath: out.appendingPathComponent("attachments/missing.png").path))
        let attrs = try fm.attributesOfItem(atPath: written[0].path)
        XCTAssertEqual(attrs[.modificationDate] as? Date, note.modifiedAt)
    }

    func testExportDoesNotOverwriteExistingFiles() throws {
        try Data("keep".utf8).write(to: dir.appendingPathComponent("Note.md"))
        let written = try MarkdownExport.export([makeNote([], title: "Note")], to: dir, attachmentsRoot: dir)
        XCTAssertEqual(written.map(\.lastPathComponent), ["Note 2.md"])
        XCTAssertEqual(try String(contentsOf: dir.appendingPathComponent("Note.md"), encoding: .utf8), "keep")
    }

    // MARK: Backup

    func testBackupArchivesDataFolder() throws {
        let data = dir.appendingPathComponent("data", isDirectory: true)
        try fm.createDirectory(at: data.appendingPathComponent("attachments/n1"), withIntermediateDirectories: true)
        try Data("[]".utf8).write(to: data.appendingPathComponent("notes.json"))
        try Data("png".utf8).write(to: data.appendingPathComponent("attachments/n1/a.png"))
        try Data("ignored".utf8).write(to: data.appendingPathComponent("tags.json.corrupt"))

        let staged = try NoteBackup.stage(from: data, into: dir, name: "staged")
        XCTAssertEqual(Set(try fm.contentsOfDirectory(atPath: staged.path)), ["notes.json", "attachments"])
        XCTAssertTrue(fm.fileExists(atPath: staged.appendingPathComponent("attachments/n1/a.png").path))

        let zip = dir.appendingPathComponent("backup.zip")
        try Data("old".utf8).write(to: zip)
        try NoteBackup.archive(from: data, to: zip)
        let header = try Data(contentsOf: zip).prefix(4)
        XCTAssertEqual(Array(header), [0x50, 0x4B, 0x03, 0x04], "expected a zip archive")
    }
}
