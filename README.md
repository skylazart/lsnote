# lsNote

A minimal, privacy-focused note-taking app for macOS. Notes are written in Markdown, stored locally as JSON, and can contain images and tags.

## Features

### Writing & Editing
- Markdown editor with formatting toolbar: bold (⌘B), italic (⌘I), links (⌘L), tables, and code blocks (⌘')
- **Block editing** — insert fenced code blocks from the toolbar; in the preview they render as collapsible, syntax-friendly blocks
- **Multi-cursor column editing** — Alt+drag a rectangular selection (or Alt+Shift+↑/↓ from the caret) to place a cursor at the same column on every line; typing, deleting, and pasting apply to all lines at once. Rectangular blocks copy and paste one entry per line. Configurable handling of lines shorter than the column (skip, or insert at end of line)
- **Multi-match selection** — select a word and press ⌘G to also select its next occurrence (⇧⌘G for previous, ⇧⌘L for all). Every match gets its own cursor, so typing renames all of them simultaneously. Double-click seeds whole-word matching; unselected occurrences are highlighted and a badge shows "X of Y matches selected". All simultaneous edits undo as a single step (⌘Z); Esc returns to a single cursor
- Per-note edit lock to prevent accidental changes (persisted across launches)
- Auto-save on every change; empty notes are deleted automatically

### Markdown Preview
- Live edit/preview toggle
- Custom GFM renderer (no external dependencies): headings, bold/italic/strikethrough, inline code, fenced code blocks, blockquotes, ordered/unordered lists, task lists, tables, horizontal rules, links, and images
- Attachment images with optional sizing: `![caption](attachment:file.png 400x300)`
- Links open in your external browser, with confirmation

### Organization
- **Tag-aware search (⇧⌘F)** — the sidebar search combines tags and text; all parts must match:

  | Input | Meaning |
  |---|---|
  | `#ocs` | tagged `ocs` (or any tag below it, e.g. `ocs/diameter`) |
  | `-#todo` | not tagged `todo` (or anything below it) |
  | `#ocs\|#pulse` | tagged `ocs` or `pulse` |
  | `quota` | title or body contains the word |
  | `"rating group"` | title or body contains the exact phrase |

  Example: `#surf -#todo quota`. Tags turn into removable chips (excluded tags are struck through). Typing `#` or `-#` suggests existing tags with their note counts, matching the start of the tag or of any path segment (`diam` finds `ocs/diameter`) and then looser matches. Text search matches titles and bodies only; use `#` to search by tag
- **Sidebar tag list** — a Tags section under Notes and TODO lists each tag with its color and note count. Pinned tags come first, in your order (drag to reorder). The rest are sorted by frequency, recent use, or name (sort button in the section header); the top 10 are shown, with **Show all** for the rest. Click a tag to add it to the search, click again to remove it. Right-click to pin/unpin, set a color, or exclude the tag
- **Faceted narrowing** — while a search is active, the tag list shows only tags present in the results, with counts for those results, so each click narrows further. **Clear filter** resets the search
- **Hierarchical tags** — use `/` to nest tags (`ocs/diameter`, `ocs/diameter/ccr`). Parents appear automatically and can be expanded in the sidebar. A parent's count is the number of distinct notes below it. `#ocs` includes everything under `ocs`; `-#ocs` excludes it all
- **Tag colors** — 8 colors that work in light and dark mode. A color set on a parent applies to its children unless they have their own. Colors show in the sidebar, search chips, note list, and note header
- Clicking a tag in the note list or in a note's header filters by that tag, keeping any search text
- TODO view — aggregates `- [ ]` / `- [x]` items across all notes tagged `#todo`; check items off without leaving the list, or jump to the source note
- In-note find bar (⌘F) with match highlighting and prev/next navigation

### Images
- Attach images via file picker or clipboard paste
- Thumbnail strip below the editor; click to insert into the note, hover to delete

### Customization
- Settings window: editor font face and size (also ⌘+ / ⌘- to resize), column-editing behavior for short lines

## Requirements

- macOS 14.0+
- Xcode 15+

## Build

```bash
./build.sh
```

Or open `lsNote.xcodeproj` in Xcode and run.

Run the unit tests (tag index, search query parser, tag metadata store):

```bash
./build.sh test
```

## Keyboard Shortcuts

| Shortcut | Action |
|---|---|
| ⌘N | New note |
| ⌘F | Open in-note find bar |
| ⇧⌘F | Focus sidebar search |
| ⌘B | Bold selection |
| ⌘I | Italic selection |
| ⌘' | Insert code block |
| ⌘L | Insert link |
| ⌘+ / ⌘- | Increase / decrease font size |
| Alt+Drag | Column (rectangular) selection |
| Alt+Shift+↑/↓ | Extend column selection up/down |
| ⌘G | Add next occurrence to selection |
| ⇧⌘G | Add previous occurrence to selection |
| ⇧⌘L | Select all occurrences |
| Esc | Close find bar / exit multi-cursor mode |

### Sidebar search

| Key | Action |
|---|---|
| `#` / `-#` | Suggest tags to include / exclude |
| ↑ / ↓ | Move through suggestions |
| Return / Tab | Accept the suggestion as a chip |
| Space | Turn a typed `#tag` into a chip |
| Backspace (empty field) | Remove the last chip |
| Esc | Close suggestions, or clear the search |

## Data Storage

All data is stored locally — no cloud sync, no telemetry.

| Data | Path |
|---|---|
| Notes | `~/Library/Application Support/lsNote/notes.json` |
| Attachments | `~/Library/Application Support/lsNote/attachments/<noteID>/` |
| Tag pins, colors, expanded groups | `~/Library/Application Support/lsNote/tags.json` |
