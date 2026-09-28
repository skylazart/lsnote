import SwiftUI
import AppKit

/// Fixed tag palette. System colors adapt to light and dark mode on their own.
enum TagColor: String, Codable, CaseIterable, Identifiable {
    case red, orange, yellow, green, teal, blue, purple, pink
    var id: String { rawValue }

    var title: String { rawValue.capitalized }

    var nsColor: NSColor {
        switch self {
        case .red:    return .systemRed
        case .orange: return .systemOrange
        case .yellow: return .systemYellow
        case .green:  return .systemGreen
        case .teal:   return .systemTeal
        case .blue:   return .systemBlue
        case .purple: return .systemPurple
        case .pink:   return .systemPink
        }
    }

    var color: Color { Color(nsColor: nsColor) }
}

extension TagColor {
    /// Non-template dot for menus, which would otherwise tint SF Symbols monochrome.
    var swatch: NSImage {
        let nsColor = self.nsColor
        let image = NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
            nsColor.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }
}

extension View {
    /// Capsule tag style: tinted fill and outline for a colored tag, `neutralFill` otherwise.
    func tagCapsule(_ color: TagColor?, neutralFill: Color) -> some View {
        self
            .background(color.map { $0.color.opacity(0.22) } ?? neutralFill)
            .overlay(Capsule().strokeBorder(color?.color.opacity(0.55) ?? .clear, lineWidth: 1))
            .clipShape(Capsule())
    }
}
