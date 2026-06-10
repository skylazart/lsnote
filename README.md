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
- Tag-based organization with tag filter chips in the sidebar
- TODO view — aggregates `- [ ]` / `- [x]` items across all notes tagged `#todo`; check items off without leaving the list, or jump to the source note
- Full-text search across titles, bodies, and tags (⇧⌘F)
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

## Data Storage

All data is stored locally — no cloud sync, no telemetry.

| Data | Path |
|---|---|
| Notes | `~/Library/Application Support/lsNote/notes.json` |
| Attachments | `~/Library/Application Support/lsNote/attachments/<noteID>/` |
