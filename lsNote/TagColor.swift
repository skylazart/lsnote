import SwiftUI
import AppKit

/// Fixed tag palette. System colors adapt to light and dark mode on their own.
enum TagColor: String, Codable, CaseIterable, Identifiable {
    case red, orange, yellow, green, teal, blue, purple, pink
    var id: String { rawValue }

    var title: String { rawValue.capitalized }

    var color: Color {
        switch self {
        case .red:    return Color(nsColor: .systemRed)
        case .orange: return Color(nsColor: .systemOrange)
        case .yellow: return Color(nsColor: .systemYellow)
        case .green:  return Color(nsColor: .systemGreen)
        case .teal:   return Color(nsColor: .systemTeal)
        case .blue:   return Color(nsColor: .systemBlue)
        case .purple: return Color(nsColor: .systemPurple)
        case .pink:   return Color(nsColor: .systemPink)
        }
    }
}
