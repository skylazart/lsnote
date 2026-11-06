import AppKit
import UniformTypeIdentifiers

/// File panels and error reporting for backup and Markdown export; the work itself is in NoteExport.swift.
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

    private static func perform(_ failure: String, _ work: () throws -> Void) {
        do {
            try work()
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = failure
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }
}
