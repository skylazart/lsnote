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
| Esc | Close find bar |

### In-Note Find Bar (⌘F)
- Appears between the tag bar and the editor.
- Case-insensitive search with match counter (`n/total`).
- Prev/Next navigation cycles through matches.
- Current match highlighted in orange; others in yellow.
- Implemented via `NSLayoutManager` temporary attributes.
- Closing clears all highlights.

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
