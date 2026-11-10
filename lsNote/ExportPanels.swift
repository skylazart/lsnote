import AppKit
import UniformTypeIdentifiers

/// File panels and error reporting for backup and export; the work itself is in NoteExport.swift and HTMLExport.swift.
@MainActor
enum ExportPanels {
    private static var attachmentsRoot: URL {
        NoteBackup.defaultDataDirectory.appendingPathComponent("attachments", isDirectory: true)
    }

    static func backUpAllNotes() {
        let panel = NSSavePanel()
        panel.title = "Back Up All Notes"
        panel.nameFieldStringValue = NoteBackup.defaultArchiveName()
        panel.allowedContentTypes = [.zip]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        perform("The backup could not be created.") {
            try NoteBackup.archive(to: url)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    /// Asks for a parent folder and exports into a new, dated subfolder so existing files are never touched.
    static func exportAll(_ notes: [Note]) {
        let panel = NSOpenPanel()
        panel.title = "Export All Notes as Markdown"
        panel.prompt = "Export"
        panel.message = "A new folder with one Markdown file per note will be created here."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let parent = panel.url else { return }

        let base = "lsNote Export \(NoteBackup.timestamp())"
        var folder = parent.appendingPathComponent(base, isDirectory: true)
        var n = 2
        while FileManager.default.fileExists(atPath: folder.path) {
            folder = parent.appendingPathComponent("\(base) \(n)", isDirectory: true)
            n += 1
        }
        perform("The notes could not be exported.") {
            try MarkdownExport.export(notes, to: folder, attachmentsRoot: attachmentsRoot)
            NSWorkspace.shared.activateFileViewerSelecting([folder])
        }
    }

    static func export(_ note: Note) {
        let panel = NSSavePanel()
        panel.title = "Export Note as Markdown"
        var taken = Set<String>()
        panel.nameFieldStringValue = MarkdownExport.fileName(for: note, taken: &taken)
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.canCreateDirectories = true
        if note.body.contains("](attachment:") {
            panel.message = "Images are saved to an “attachments” folder next to the file."
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        perform("The note could not be exported.") {
            try MarkdownExport.write(note, to: url, attachmentsRoot: attachmentsRoot)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    /// Saves the note as one self-contained HTML file (see HTMLExport.swift).
    static func exportHTML(_ note: Note) {
        let panel = NSSavePanel()
        panel.title = "Export Note as HTML"
        var taken = Set<String>()
        panel.nameFieldStringValue = MarkdownExport.fileName(for: note, taken: &taken, pathExtension: "html")
        panel.allowedContentTypes = [.html]
        panel.canCreateDirectories = true
        panel.message = "Images and diagrams are embedded in the file."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            do {
                let html = try await HTMLExport.document(for: note)
                try Data(html.utf8).write(to: url, options: .atomic)
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch {
                report("The note could not be exported.", error)
            }
        }
    }

    private static func perform(_ failure: String, _ work: () throws -> Void) {
        do {
            try work()
        } catch {
            report(failure, error)
        }
    }

    private static func report(_ failure: String, _ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = failure
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }
}
