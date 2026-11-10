import SwiftUI
import AppKit

/// What the editor hands to the AI sheet: the text to work on and where it came from.
struct AIRequest: Identifiable {
    let id = UUID()
    /// nil asks for a one-off custom prompt before running.
    let action: AIAction?
    let source: String
    /// Range of `source` in the text view (the whole document when nothing was selected).
    let range: NSRange
    let isSelection: Bool
}

/// The editor toolbar's AI menu. Equatable for the same reason as `PreviewModePicker`: the editor
/// re-renders on every keystroke and the menu should only be rebuilt when its content changes.
struct AIActionMenu: View, Equatable {
    let customActions: [AIAction]
    /// nil = custom prompt.
    let onPick: (AIAction?) -> Void

    static func == (a: Self, b: Self) -> Bool { a.customActions == b.customActions }

    var body: some View {
        Menu {
            ForEach(AIAction.builtIns) { action in
                Button(action.name) { onPick(action) }
            }
            if !customActions.isEmpty {
                Divider()
                ForEach(customActions) { action in
                    Button(action.name) { onPick(action) }
                }
            }
            Divider()
            Button("Custom Prompt…") { onPick(nil) }
            SettingsLink { Text("Manage Actions…") }
        } label: {
            Image(systemName: "sparkles")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("AI Actions — applies to the selection, or the whole note if nothing is selected")
    }
}

/// Runs an AI action and lets the user review the streamed result before it touches the note.
struct AIActionSheet: View {
    let request: AIRequest
    /// Locked notes can still be read and copied from, but not changed.
    let isLocked: Bool
    let onReplace: (String) -> Void
    let onInsertBelow: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = AppSettings.shared

    private enum Phase: Equatable { case compose, running, done, failed(String) }
    @State private var phase: Phase = .compose
    @State private var instruction = ""
    @State private var output = ""
    @State private var truncated = false
    @State private var task: Task<Void, Never>? = nil
    @FocusState private var promptFocused: Bool

    private var title: String { request.action?.name ?? "Custom Prompt" }
    private var scope: String {
        let count = request.source.count
        return "\(request.isSelection ? "Selection" : "Whole note") · \(count) character\(count == 1 ? "" : "s")"
    }
    private var hasResult: Bool {
        phase == .done && !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles").foregroundStyle(.tint)
                Text(title).font(.headline)
                Spacer()
                Text(scope).font(.caption).foregroundStyle(.secondary)
            }

            if request.action == nil {
                HStack(alignment: .top) {
                    TextField("What should be done with the text?", text: $instruction, axis: .vertical)
                        .lineLimit(1...4)
                        .textFieldStyle(.roundedBorder)
                        .focused($promptFocused)
                        .disabled(phase == .running)
                        .onSubmit(run)
                    Button(phase == .compose ? "Run" : "Run Again", action: run)
                        .disabled(phase == .running
                                  || instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            resultArea

            HStack {
                if phase == .running {
                    ProgressView().controlSize(.small)
                    Text("Working…").font(.caption).foregroundStyle(.secondary)
                } else if truncated {
                    Label("The result was cut off at the output limit.", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(trimmedOutput, forType: .string)
                    dismiss()
                }
                .disabled(!hasResult)
                Button("Insert Below") {
                    onInsertBelow(trimmedOutput)
                    dismiss()
                }
                .disabled(!hasResult || isLocked)
                Button("Replace") {
                    onReplace(AIPrompt.tidy(output, replacing: request.source))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!hasResult || isLocked)
                .help(isLocked ? "This note is locked" : "Replace the \(request.isSelection ? "selection" : "note") with the result (⌘Z undoes it)")
            }
        }
        .padding(16)
        .frame(width: 600, height: 440)
        .onAppear {
            if let action = request.action {
                instruction = action.prompt
                run()
            } else {
                promptFocused = true
            }
        }
        .onDisappear { task?.cancel() }
    }

    private var trimmedOutput: String { output.trimmingCharacters(in: .whitespacesAndNewlines) }

    @ViewBuilder
    private var resultArea: some View {
        Group {
            if case .failed(let message) = phase {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle").font(.title2).foregroundStyle(.orange)
                    Text(message).multilineTextAlignment(.center).textSelection(.enabled)
                    HStack {
                        SettingsLink { Text("Open Settings…") }
                        Button("Try Again", action: run)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if phase == .compose {
                Text("The result appears here for review before anything in the note changes.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        Text(output)
                            .font(.init(settings.font))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                        Color.clear.frame(height: 1).id("end")
                    }
                    .onChange(of: output) { _, _ in
                        if phase == .running { proxy.scrollTo("end", anchor: .bottom) }
                    }
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
    }

    private func run() {
        let prompt = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, phase != .running else { return }
        task?.cancel()
        output = ""
        truncated = false
        phase = .running
        let source = request.source
        let model = settings.aiModel.trimmingCharacters(in: .whitespacesAndNewlines)
        task = Task {
            do {
                for try await chunk in AIClient.run(instruction: prompt, text: source, model: model) {
                    output += chunk.text
                    if chunk.truncated { truncated = true }
                }
                if !Task.isCancelled { phase = .done }
            } catch {
                if !Task.isCancelled { phase = .failed(error.localizedDescription) }
            }
        }
    }
}
