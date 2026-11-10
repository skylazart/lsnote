import Foundation

/// GitHub-compatible heading anchors, so `[Intro](#intro)` links written for GitHub also work in
/// the preview and in HTML exports. Foundation-only so the tests can compile it directly.
enum HeadingAnchor {
    /// Hands out ids for one document, in heading order. Like GitHub, a repeated heading gets
    /// `-1`, `-2`, … appended, skipping any id an earlier heading already took.
    struct Slugger {
        /// Every id handed out so far → how many times it has been suffixed as a base.
        private var occurrences: [String: Int] = [:]

        mutating func slug(for text: String) -> String {
            let base = HeadingAnchor.slug(text)
            var id = base
            while occurrences[id] != nil {
                occurrences[base, default: 0] += 1
                id = "\(base)-\(occurrences[base]!)"
            }
            occurrences[id] = 0
            return id
        }
    }

    /// GitHub's rule: lowercase; keep letters (accents included), digits, `-` and `_`; turn each
    /// space into `-`; drop everything else. `"Cenário 1 · Fluxo"` → `"cenário-1--fluxo"`.
    static func slug(_ text: String) -> String {
        var id = String.UnicodeScalarView()
        for scalar in text.lowercased().unicodeScalars {
            if scalar == " " {
                id.append("-")
            } else if scalar == "-" || scalar == "_" || CharacterSet.alphanumerics.contains(scalar) {
                id.append(scalar)
            }
        }
        return String(id)
    }

    /// The visible text of rendered inline HTML (tags removed, basic entities decoded), which is
    /// what GitHub slugs — so `## **Bold** title` gets `bold-title`.
    static func plainText(fromHTML html: String) -> String {
        html.replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespaces)
    }
}
