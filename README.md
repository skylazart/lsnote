# lsNote

A minimal, privacy-focused note-taking app for macOS. Notes are written in Markdown, stored locally as JSON, and can contain images and tags.

## Features

- Markdown editor with live preview (GFM: tables, fenced code, strikethrough, task lists)
- Tag-based organization with tag filter chips
- TODO view — aggregates `- [ ]`/`- [x]` items across all notes tagged `#todo`
- Image attachments via file picker or clipboard paste
- In-note find bar (Cmd+F) with match highlighting and navigation
- Full-text search across titles, bodies, and tags

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
| Esc | Close find bar |

## Data Storage

All data is stored locally — no cloud sync, no telemetry.

| Data | Path |
|---|---|
| Notes | `~/Library/Application Support/lsNote/notes.json` |
| Attachments | `~/Library/Application Support/lsNote/attachments/<noteID>/` |
