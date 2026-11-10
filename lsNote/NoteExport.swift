import Foundation

/// Converts notes to plain Markdown files. Foundation-only so the tests can compile it directly.
enum MarkdownExport {
    /// Folder, next to the exported `.md` files, that receives attachment images.
    static let attachmentsFolder = "attachments"

    private static let attachmentPattern = try! NSRegularExpression(
        pattern: #"!\[([^\]]*)\]\(attachment:([^\s\)]+)(?:\s+(\d*)x(\d*))?\)"#)

    /// File-system-safe name derived from the title, unique (case-insensitively) within `taken`.
    static func fileName(for note: Note, taken: inout Set<String>, pathExtension ext: String = "md") -> String {
        let illegal = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.controlCharacters).union(.newlines)
        var base = note.title.components(separatedBy: illegal).joined(separator: "-")
            .trimmingCharacters(in: .whitespaces)
        while base.hasPrefix(".") { base.removeFirst() }
        base = String(base.prefix(120)).trimmingCharacters(in: .whitespaces)
        if base.isEmpty { base = "Untitled" }

        var name = "\(base).\(ext)"
        var n = 2
        while taken.contains(name.lowercased()) {
            name = "\(base) \(n).\(ext)"
            n += 1
        }
        taken.insert(name.lowercased())
        return name
    }

    /// The note as Markdown: YAML front matter (title, tags, dates) followed by the body, with
    /// `attachment:` images rewritten to standard links into `attachments/`. Sizes are dropped,
    /// since plain Markdown has no syntax for them. Also returns the referenced attachment filenames.
    static func document(for note: Note) -> (text: String, attachments: [String]) {
        let iso = ISO8601DateFormatter()
        var lines = ["---", "title: \(yamlQuoted(note.title))"]
        if !note.tags.isEmpty {
            lines.append("tags: [\(note.tags.map(yamlQuoted).joined(separator: ", "))]")
        }
        lines.append("created: \(iso.string(from: note.createdAt))")
        lines.append("modified: \(iso.string(from: note.modifiedAt))")
        lines.append("---")

        let body = note.body as NSString
        var rewritten = ""
        var files: [String] = []
        var cursor = 0
        for match in attachmentPattern.matches(in: note.body, range: NSRange(location: 0, length: body.length)) {
            let caption = body.substring(with: match.range(at: 1))
            let filename = body.substring(with: match.range(at: 2))
            rewritten += body.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            rewritten += "![\(caption)](\(attachmentsFolder)/\(filename))"
            cursor = match.range.location + match.range.length
            if !files.contains(filename) { files.append(filename) }
        }
        rewritten += body.substring(from: cursor)

        return (lines.joined(separator: "\n") + "\n\n" + rewritten, files)
    }

    /// Writes each note as `<title>.md` into `directory`, copying referenced images from
    /// `attachmentsRoot/<noteID>/` into `directory/attachments/`. Missing images are skipped.
    /// Returns the written files' URLs.
    @discardableResult
    static func export(_ notes: [Note], to directory: URL, attachmentsRoot: URL) throws -> [URL] {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        var taken = Set((try? fm.contentsOfDirectory(atPath: directory.path))?.map { $0.lowercased() } ?? [])
        var written: [URL] = []
        for note in notes {
            let url = directory.appendingPathComponent(fileName(for: note, taken: &taken))
            try write(note, to: url, attachmentsRoot: attachmentsRoot)
            written.append(url)
        }
        return written
    }

    /// Writes one note to `url`; images go into an `attachments/` folder next to it.
    static func write(_ note: Note, to url: URL, attachmentsRoot: URL) throws {
        let fm = FileManager.default
        let (text, files) = document(for: note)
        try Data(text.utf8).write(to: url, options: .atomic)
        try? fm.setAttributes([.creationDate: note.createdAt, .modificationDate: note.modifiedAt],
                              ofItemAtPath: url.path)

        let source = attachmentsRoot.appendingPathComponent(note.id.uuidString, isDirectory: true)
        let target = url.deletingLastPathComponent().appendingPathComponent(attachmentsFolder, isDirectory: true)
        for file in files {
            let from = source.appendingPathComponent(file)
            guard fm.fileExists(atPath: from.path) else { continue }
            try fm.createDirectory(at: target, withIntermediateDirectories: true)
            let to = target.appendingPathComponent(file)
            try? fm.removeItem(at: to)
            try fm.copyItem(at: from, to: to)
        }
    }

    private static func yamlQuoted(_ s: String) -> String {
        let escaped = s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
    }
}

/// Full backup of the app's data folder (notes.json, tags.json, attachments/) as a zip archive.
enum NoteBackup {
    static let items = ["notes.json", "tags.json", "attachments"]

    static let defaultDataDirectory = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("lsNote", isDirectory: true)

    /// Sortable, file-name-safe stamp such as `2026-10-02 153012`.
    static func timestamp(_ date: Date = .now) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HHmmss"
        return f.string(from: date)
    }

    static func defaultArchiveName(date: Date = .now) -> String {
        "lsNote Backup \(timestamp(date)).zip"
    }

    /// Copies the backed-up items from `dataDirectory` into a new folder `name` inside `parent`.
    /// Items that don't exist yet (e.g. no tags.json) are skipped.
    static func stage(from dataDirectory: URL, into parent: URL, name: String) throws -> URL {
        let fm = FileManager.default
        let folder = parent.appendingPathComponent(name, isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        for item in items {
            let from = dataDirectory.appendingPathComponent(item)
            guard fm.fileExists(atPath: from.path) else { continue }
            try fm.copyItem(at: from, to: folder.appendingPathComponent(item))
        }
        return folder
    }

    /// Zips the data folder to `destination`, replacing any file already there.
    /// Unzipping yields a folder whose contents can be copied back into the data directory.
    static func archive(from dataDirectory: URL = defaultDataDirectory, to destination: URL) throws {
        let fm = FileManager.default
        let scratch = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? fm.removeItem(at: scratch) }
        let folder = try stage(from: dataDirectory, into: scratch,
                               name: destination.deletingPathExtension().lastPathComponent)

        // Reading a directory with `.forUploading` hands back a temporary zip of it.
        var coordinatorError: NSError?
        var copyError: Error?
        let zipped = scratch.appendingPathComponent("backup.zip")
        NSFileCoordinator().coordinate(readingItemAt: folder, options: .forUploading,
                                       error: &coordinatorError) { zipURL in
            do { try fm.copyItem(at: zipURL, to: zipped) } catch { copyError = error }
        }
        if let error = coordinatorError ?? copyError { throw error }

        if fm.fileExists(atPath: destination.path) {
            _ = try fm.replaceItemAt(destination, withItemAt: zipped)
        } else {
            try fm.moveItem(at: zipped, to: destination)
        }
    }
}
