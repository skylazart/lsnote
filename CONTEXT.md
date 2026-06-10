# lsNote — Project Context

## Overview
lsNote is a macOS note-taking app built with SwiftUI. Notes are written in Markdown, stored locally as JSON, and can contain images and tags. The app has a three-column layout: a navigation sidebar (Notes / TODO), a note list, and an editor.

## Tech Stack
- **Language:** Swift
- **UI:** SwiftUI + AppKit (NSViewRepresentable for the text editor and Markdown preview)
- **Persistence:** JSON file at `~/Library/Application Support/lsNote/notes.json`
- **Image storage:** PNG files at `~/Library/Application Support/lsNote/attachments/<noteID>/`
- **Markdown preview:** Custom inline GFM renderer → WKWebView

## Data Model

### `Note` (Codable, Identifiable)
| Field | Type | Notes |
|---|---|---|
| `id` | UUID | Primary key |
| `title` | String | Auto-generated: `"Wednesday, March 25 2026 · 3:45 PM"` |
| `body` | String | Raw Markdown |
| `tags` | [String] | Lowercase, hyphenated |
| `attachments` | [String] | PNG filenames (stored via ImageStore) |
| `createdAt` | Date | |

### `NoteStore` (ObservableObject, @MainActor)
Central state. Published: `notes`, `selectedID`, `isPreview`. Persists on every mutation.

## File Structure
```
lsNote/
├── lsNoteApp.swift        # App entry point, menu commands (⌘N new note, ⇧⌘F sidebar search)
├── ContentView.swift      # NavigationSplitView: sidebar nav | SidebarView/TodoView | EditorView
├── SidebarView.swift      # Note list with search field, tag filter chips, FlowLayout
├── EditorView.swift       # Toolbar, tag bar, find bar (⌘F), MarkdownTextEditor or MarkdownPreview
├── MarkdownTextEditor.swift # NSTextView wrapper; formatting helpers (bold, italic, table, find/highlight)
├── MarkdownPreview.swift  # WKWebView-based GFM renderer (fenced code, tables, images, inline styles)
├── TodoView.swift         # Aggregated TODO list from notes tagged #todo; toggle done/pending
├── Note.swift             # Note model
├── NoteStore.swift        # State + persistence
└── ImageStore.swift       # PNG save/load/delete helpers
```

## Key Behaviors

### Keyboard Shortcuts
| Shortcut | Action |
|---|---|
| ⌘N | New note |
| ⌘F | Open in-note find bar (EditorView) |
| ⇧⌘F | Focus sidebar search field |
| ⌘B | Bold selection |
| ⌘I | Italic selection |
| Esc | Close find bar / exit multi-cursor mode |
| Alt+Drag | Column (rectangular) selection |
| Alt+Shift+↑/↓ | Extend column selection up/down |
| ⌘G | Add next occurrence of selection to multi-selection |
| ⇧⌘G | Add previous occurrence to multi-selection |
| ⇧⌘L | Select all occurrences of selection |

### In-Note Find Bar (⌘F)
- Appears between the tag bar and the editor.
- Case-insensitive search with match counter (`n/total`).
- Prev/Next navigation cycles through matches.
- Current match highlighted in orange; others in yellow.
- Implemented via `NSLayoutManager` temporary attributes.
- Closing clears all highlights.

### Multi-Cursor Editing (`MultiCursorTextView`)
- **Column mode:** Alt+drag a rectangle (or Alt+Shift+↑/↓ from the caret) to place a cursor at the same column on every selected line. Typing, Backspace/Delete, and paste apply to all lines at once — e.g. type `- ` at column 0 to prefix every line. Lines shorter than the column are skipped by default (Settings can switch this to insert at end of line).
- **Multi-match mode:** select a word, then ⌘G repeatedly adds the next occurrences (⇧⌘G previous, ⇧⌘L all). Double-click seeds a whole-word match; drag-selection matches partial words. Matching is case-sensitive. Unselected occurrences get a subtle yellow highlight; a badge in the editor's bottom-right shows "X of Y matches selected".
- Copying a column selection puts one entry per line on the pasteboard; pasting distributes entries back one-per-line (column block paste also works from a single caret).
- Every simultaneous edit is one undo step. Escape, clicking, moving the caret, or any external edit (toolbar formatting, undo, note switch) returns to a single cursor. Column and match modes are mutually exclusive — starting one cancels the other.

### TODO View
- Aggregates `- [ ] task` / `- [x] task` lines from all notes tagged `#todo`.
- Tapping the circle toggles done state by rewriting the note body.
- Tapping the row navigates to the source note.

### Auto-delete Empty Notes
When the editor disappears, `NoteStore.deleteEmptyNote` removes the note if its body is blank (also deletes any attachments).

### Markdown Preview
Custom renderer (no external dependencies). Supports: headings, bold/italic/strikethrough, inline code, fenced code blocks (collapsible `<details>`), blockquotes, unordered/ordered lists, GFM tables, horizontal rules, links, standard images, and attachment images (`![title](attachment:filename.png [WxH])`).

## Attachment Images
- Syntax in editor: `![caption](attachment:uuid.png)` or `![caption](attachment:uuid.png 400x300)`
- Stored as PNG under `~/Library/Application Support/lsNote/attachments/<noteID>/`
- Rendered inline in preview as base64-embedded `<img>` tags.
- Insert via toolbar button (file picker) or paste from clipboard.
