# lsNote — Project Context

## Overview
lsNote is a macOS note-taking app built with SwiftUI. Notes are written in Markdown, stored locally as JSON, and can contain images and tags. The app has a three-column layout: a navigation sidebar (Notes / TODO), a note list, and an editor.

## Tech Stack
- **Language:** Swift
- **UI:** SwiftUI + AppKit (NSViewRepresentable for the text editor and Markdown preview)
- **Persistence:** JSON file at `~/Library/Application Support/lsNote/notes.json`; tag metadata in `tags.json` next to it
- **Image storage:** PNG files at `~/Library/Application Support/lsNote/attachments/<noteID>/`
- **Markdown preview:** Custom inline GFM renderer → WKWebView

## Data Model

### `Note` (Codable, Identifiable)
| Field | Type | Notes |
|---|---|---|
| `id` | UUID | Primary key |
| `title` | String | Auto-generated: `"Wednesday, March 25 2026 · 3:45 PM"` |
| `body` | String | Raw Markdown |
| `tags` | [String] | Lowercase, hyphenated; `/` nests (`ocs/diameter`) |
| `attachments` | [String] | PNG filenames (stored via ImageStore) |
| `createdAt` | Date | |
| `modifiedAt` | Date | Last title/body/tag change; falls back to `createdAt` for notes saved before it existed |

### `NoteStore` (ObservableObject, @MainActor)
Central state. Published: `notes`, `selectedID`, `isPreview`, `tagIndex`, `query` (sidebar search), `sidebarSelection` (Notes/TODO). Persists notes on every mutation and keeps `tagIndex` updated incrementally. `filteredNotes` evaluates `query` against the index.

### `TagIndex` (value type)
Exact tag → note IDs, note → tags, note → `modifiedAt`. Resolves a tag to its subtree's notes, gives deduplicated subtree counts, last-used dates, the derived hierarchy tree (`tree(counts:sortedBy:)`) and result-restricted `facets(for:keeping:)`.

### `SearchQuery` (value type)
`tagClauses` (`.anyOf([tags])`, `.excluding(tag)`), `terms`, `phrases`. `parse(_:)`, `evaluate(_:index:)`, plus the edits used by tag clicks (`replaceTags`, `toggle`, `exclude`) and the search-field helpers (`extractTags`, `completionContext`, `applyingCompletion`). `TagSuggester.rank` orders autocomplete suggestions.

### `TagMetadata` / `TagMetadataStore` (ObservableObject, @MainActor)
`pinned` (ordered), `colors` (`[tag: TagColor]`, inherited by descendants), `expanded`. Stored in `tags.json`, written atomically; a missing or unreadable file falls back to defaults (an unreadable one is moved to `tags.json.corrupt`). Entries for tags no longer in use are kept. See `docs/adr/0003-tag-query-syntax-hierarchy-and-metadata-store.md`.

## File Structure
```
lsNote/
├── lsNoteApp.swift        # App entry point, menu commands (⌘N new note, ⇧⌘F sidebar search)
├── ContentView.swift      # NavigationSplitView: sidebar nav (Notes, TODO, Tags) | SidebarView/TodoView | EditorView
├── SidebarView.swift      # QueryField + filtered note list with clickable tag labels, FlowLayout
├── QueryField.swift       # Chip search field, tag autocomplete, debounced free text
├── TagListView.swift      # Sidebar Tags section: pins, sort modes, hierarchy, facets, context menu
├── TagIndex.swift         # TagPath helpers, TagIndex, TagNode, TagFacet, TagSortMode
├── SearchQuery.swift      # Query model, parser, evaluator, TagSuggester
├── TagMetadataStore.swift # tags.json persistence (pins, colors, expansion)
├── TagColor.swift         # Tag palette + tagCapsule style
├── EditorView.swift       # Toolbar, tag bar, find bar (⌘F), MarkdownTextEditor or MarkdownPreview
├── MarkdownTextEditor.swift # NSTextView wrapper; formatting helpers (bold, italic, table, find/highlight)
├── MarkdownPreview.swift  # WKWebView-based GFM renderer (fenced code, tables, images, inline styles)
├── TodoView.swift         # Aggregated TODO list from notes tagged #todo; toggle done/pending
├── Note.swift             # Note model
├── NoteStore.swift        # State + persistence
└── ImageStore.swift       # PNG save/load/delete helpers
lsNoteTests/               # XCTest target; compiles the pure model files directly (no app host)
```

## Key Behaviors

### Keyboard Shortcuts
| Shortcut | Action |
|---|---|
| ⌘N | New note |
| ⌘F | Open in-note find bar (EditorView) |
| ⇧⌘F | Focus sidebar search field |
| `#` / `-#` in search | Tag suggestions (↑/↓, Return/Tab accept, Esc dismiss) |
| Backspace in empty search | Remove last tag chip |
| ⌘B | Bold selection |
| ⌘I | Italic selection |
| Esc | Close find bar / exit multi-cursor mode |
| Alt+Drag | Column (rectangular) selection |
| Alt+Shift+↑/↓ | Extend column selection up/down |
| ⌘G | Add next occurrence of selection to multi-selection |
| ⇧⌘G | Add previous occurrence to multi-selection |
| ⇧⌘L | Select all occurrences of selection |

### Sidebar Search & Tags
- Query syntax: `#tag`, `-#tag`, `#a|#b`, free words, `"exact phrase"`; all clauses ANDed. Tags match their whole subtree and are case-insensitive. Free text matches title and body only (not tag names).
- Tag clauses render as chips in `QueryField`; typing `#`/`-#` shows suggestions with counts (path prefix > segment prefix > subsequence, then usage). A tag token followed by a space, or accepted with Return/Tab, becomes a chip. Free text is applied after 150 ms.
- Tag clicks all go through `NoteStore`: note list / note header → `showTag` (replace tag clauses, keep text); sidebar tag list → `toggleTagFilter` (AND in, or remove if active); context menu → `excludeTag`. `clearQuery()` also clears the field's uncommitted text.
- Sidebar Tags section: pinned first (drag to reorder), then top-level tags sorted by `AppSettings.tagSortMode` (frequency / recent / alphabetical), top 10 unless `tagListShowAll`. Hierarchy shown with disclosure groups (expansion stored in `tags.json`). With an active query, counts are facets over the results; zero-count tags hide unless they are in the query.
- Suggestions render inline under the field, not as an overlay, because the AppKit-backed note list would cover an overlay. Backspace-to-remove-chip uses an `NSEvent` local monitor because the field editor swallows Backspace before `onKeyPress`.

### Tag Autocomplete (note header)
- Typing in the tag bar's "Add tag…" field shows a dropdown of existing tags (from all notes) matching the input, ranked like the sidebar search (`TagSuggester`); tags already on the note are excluded. Clicking a tag chip filters the sidebar by it.
- ↑/↓ move the highlight, Return commits the highlighted suggestion (or the typed text if none is highlighted), Tab accepts the highlighted/first suggestion, Esc dismisses the dropdown. Clicking a suggestion also adds it.
- Input is normalized (lowercased, spaces → hyphens) before matching; committed tags also go through `TagPath.normalize` (empty `/` segments dropped).

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
Custom renderer (no external dependencies). Supports: headings, bold/italic/strikethrough, inline code, fenced code blocks (collapsible `<details>`), blockquotes, unordered/ordered lists, GFM tables, horizontal rules, links, standard images, attachment images (`![title](attachment:filename.png [WxH])`), and inline math (`$\command$` — Greek letters, binary/relation operators, arrows, and other common symbols mapped to Unicode; see `mathSymbols` in `MarkdownPreview.swift`).

## Attachment Images
- Syntax in editor: `![caption](attachment:uuid.png)` or `![caption](attachment:uuid.png 400x300)`
- Stored as PNG under `~/Library/Application Support/lsNote/attachments/<noteID>/`
- Rendered inline in preview as base64-embedded `<img>` tags.
- Insert via toolbar button (file picker) or paste from clipboard.
