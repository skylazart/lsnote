import AppKit
import Foundation

enum ImageStore {
    private static let fm = FileManager.default

    private static func attachmentsDir(for noteID: UUID) -> URL {
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("lsNote/attachments/\(noteID.uuidString)", isDirectory: true)
        try? fm.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    static func save(_ image: NSImage, noteID: UUID) -> String? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return nil }
        let filename = "\(UUID().uuidString).png"
        let url = attachmentsDir(for: noteID).appendingPathComponent(filename)
        try? png.write(to: url)
        return filename
    }

    static func load(filename: String, noteID: UUID) -> NSImage? {
        let url = attachmentsDir(for: noteID).appendingPathComponent(filename)
        return NSImage(contentsOf: url)
    }

    static func delete(filename: String, noteID: UUID) {
        let url = attachmentsDir(for: noteID).appendingPathComponent(filename)
        try? fm.removeItem(at: url)
    }

    static func deleteAll(noteID: UUID) {
        let dir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("lsNote/attachments/\(noteID.uuidString)", isDirectory: true)
        try? fm.removeItem(at: dir)
    }
}
