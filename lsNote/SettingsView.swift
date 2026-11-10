import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared

    private let availableFonts: [String] = {
        NSFontManager.shared.availableFontFamilies.sorted()
    }()

    var body: some View {
        TabView {
            general.tabItem { Label("General", systemImage: "gearshape") }
            AISettingsView().tabItem { Label("AI", systemImage: "sparkles") }
        }
        .frame(width: 480, height: 440)
    }

    private var general: some View {
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
            Section("Preview") {
                HStack {
                    Text(settings.customCSSPath.isEmpty ? "No custom CSS" : settings.customCSSPath)
                        .foregroundStyle(settings.customCSSPath.isEmpty ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Choose…", action: chooseCustomCSS)
                    if !settings.customCSSPath.isEmpty {
                        Button("Clear") { settings.customCSSPath = "" }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func chooseCustomCSS() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "css")].compactMap { $0 }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        settings.customCSSPath = url.path
    }
}

/// Settings → AI: the Anthropic API key (keychain), the model, and the user's custom actions.
struct AISettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var keyDraft = ""
    @State private var hasSavedKey = KeychainStore.read()?.isEmpty == false
    @State private var keyError = false
    @State private var actions: [AIAction] = AppSettings.shared.aiCustomActions

    var body: some View {
        Form {
            Section {
                HStack {
                    SecureField("API key:", text: $keyDraft,
                                prompt: Text(hasSavedKey ? "Saved in your keychain" : "sk-ant-…"))
                        .onSubmit(saveKey)
                    Button("Save", action: saveKey).disabled(keyDraft.isEmpty)
                    if hasSavedKey {
                        Button("Remove") {
                            KeychainStore.save("")
                            hasSavedKey = false
                        }
                    }
                }
                if keyError {
                    Text("The key could not be saved to the keychain.").font(.caption).foregroundStyle(.red)
                }
                TextField("Model:", text: $settings.aiModel, prompt: Text(AIClient.defaultModel))
            } header: {
                Text("Anthropic API")
            } footer: {
                Text("Running an AI action sends the selected text (or the whole note) to Anthropic's API. Nothing is sent otherwise.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                ForEach($actions) { $action in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            TextField("Name", text: $action.name, prompt: Text("Name shown in the menu"))
                                .labelsHidden()
                            Button {
                                actions.removeAll { $0.id == action.id }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help("Delete this action")
                        }
                        TextField("Prompt", text: $action.prompt,
                                  prompt: Text("Instruction, e.g. “Rewrite in a formal tone.”"), axis: .vertical)
                            .labelsHidden()
                            .lineLimit(2...5)
                    }
                    .padding(.vertical, 2)
                }
                Button("Add Action") {
                    actions.append(AIAction(name: "New Action", prompt: ""))
                }
            } header: {
                Text("Custom Actions")
            } footer: {
                Text("Listed in the editor's ✦ menu after the built-in actions. Actions without a name or prompt are hidden.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onChange(of: actions) { _, newValue in settings.aiCustomActions = newValue }
    }

    private func saveKey() {
        let key = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        keyError = !KeychainStore.save(key)
        if !keyError {
            hasSavedKey = true
            keyDraft = ""
        }
    }
}
