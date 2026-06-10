import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared

    private let availableFonts: [String] = {
        NSFontManager.shared.availableFontFamilies.sorted()
    }()

    var body: some View {
        Form {
            Picker("Font:", selection: $settings.fontName) {
                ForEach(availableFonts, id: \.self) { family in
                    Text(family).tag(
                        NSFontManager.shared.font(withFamily: family, traits: [], weight: 5, size: 0)?.fontName ?? family
                    )
                }
            }
            HStack {
                Text("Size:")
                TextField("", value: $settings.fontSize, format: .number)
                    .frame(width: 50)
                Stepper("", value: $settings.fontSize, in: 8...72, step: 1)
                    .labelsHidden()
            }
            Text("The quick brown fox jumps over the lazy dog")
                .font(.init(settings.font))
                .padding(.top, 8)
            Toggle("Column editing on short lines inserts at end of line", isOn: $settings.columnInsertAtLineEnd)
                .help("When a line is shorter than the selected column, insert there at the end of the line instead of skipping the line.")
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 240)
    }
}
