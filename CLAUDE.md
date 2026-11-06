# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build

```bash
./build.sh
# or directly:
xcodebuild -scheme lsNote -configuration Release -derivedDataPath build
```

Open `lsNote.xcodeproj` in Xcode to run in debug mode. No linter is configured.

```bash
./build.sh test   # XCTest target lsNoteTests
```

`lsNoteTests` has no app host: it compiles the pure model files (`Note`, `TagIndex`, `SearchQuery`, `TagMetadataStore`, `TagColor`, `NoteExport`) directly into the test bundle, so tests never launch the app or touch real user data. When adding a file those tests need, add it to both targets' Sources. The Xcode project is hand-maintained (short object IDs such as `A017`/`B017`/`C00x`); a shared scheme lives in `lsNote.xcodeproj/xcshareddata/xcschemes/`.

## Architecture

lsNote is a macOS-only (14.0+) note-taking app. SwiftUI for layout, AppKit bridges (`NSViewRepresentable`) for the text editor and Markdown preview. No package dependencies; the only third-party code is the vendored `mermaid.min.js` in `lsNote/Vendor/` (see `docs/adr/0004-render-mermaid-with-bundled-mermaid-js.md`).

**State:** `NoteStore` (`ObservableObject`, `@MainActor`) is the single source of truth — injected as `@EnvironmentObject` from `lsNoteApp`. It holds `@Published notes`, `selectedID`, `isPreview` (global edit/preview toggle, intentionally not per-note), `tagIndex`, `query` (sidebar search) and `sidebarSelection`. Edits go through `update(id) { $0… }` (mutate the current stored note — never pass back a whole `Note` copied in a render, it may be stale). Every mutation updates `tagIndex` incrementally (never rebuilt per keystroke) and saves `~/Library/Application Support/lsNote/notes.json` atomically: immediately for create/delete/import, debounced 750 ms for `update`; call `save()` to flush before reading the file (backup) — `AppDelegate` flushes on quit. `TagMetadataStore` is a second environment object for `tags.json` (pins, colors, expansion).

**Layout root:** `ContentView` uses `NavigationSplitView` with three columns — sidebar nav (Notes/TODO selector plus the `TagListView` Tags section), `SidebarView` or `TodoView`, and `EditorView`.

**Tags & search:** see `docs/adr/0003-tag-query-syntax-hierarchy-and-metadata-store.md` for the query syntax and hierarchy rules. `SearchQuery` (parser + evaluator) and `TagIndex` are pure value types; evaluation resolves tag clauses by set operations on the index before any text matching. Hierarchy is derived from `/` in tag strings — never stored. All tag clicks route through `NoteStore.showTag` / `toggleTagFilter` / `excludeTag`; don't add another filtering path. Sort mode and "show all" live in `AppSettings` (`UserDefaults`).

**Text editing:** `MarkdownTextEditor` wraps `MultiCursorTextView` (an `NSTextView` subclass). While editing, the text view is the source of truth: `EditorView` ignores `note.body` values it pushed itself (`PushedBodies`) and only adopts bodies written elsewhere (TODO view). `updateNSView` runs per keystroke, so it only assigns `font`/`isEditable` when they change — assigning `font` re-lays out the whole document. All formatting helpers (bold, italic, table insert, find+highlight) are static methods on `MarkdownTextEditor`. The find bar highlights matches via `NSLayoutManager` temporary attributes (orange for current, yellow for others) and is invoked with Cmd+F from `EditorView`.

**Multi-cursor:** `MultiCursorTextView` implements column editing (Alt+drag, Alt+Shift+↑/↓) and multi-match selection (⌘G next / ⇧⌘G previous / ⇧⌘L all occurrences; word-boundary matching when the seed selection was a double-click). Cursor state lives in its `cursors` array (NSTextView has no multi-cursor API); all simultaneous edits go through one `shouldChangeText(inRanges:replacementStrings:)` call so each operation is a single undo step. Escape, a plain click/selection change, or any external text mutation exits multi-cursor mode. `EditorView` shows a status badge ("3 of 7 matches selected") via the `onMultiCursorStatus` callback. The short-line column behavior (skip vs. insert at end of line) is configurable via `AppSettings.columnInsertAtLineEnd`.

**Markdown preview:** `MarkdownPreview` wraps `WKWebView` with a fully custom GFM renderer written in Swift — no Markdown libraries. Attachment images use the syntax `![caption](attachment:uuid.png [WxH])` and are embedded as base64 data URIs to bypass WKWebView's file:// restrictions. ```` ```mermaid ```` fences become `<pre class="mermaid">`; the bundled mermaid.js is evaluated in `didFinish` only when the note has one.

**Images:** `ImageStore` saves PNGs to `~/Library/Application Support/lsNote/attachments/<noteID>/`. Insertion happens via file picker or clipboard paste from `EditorView`'s toolbar.

**TODO view:** `TodoView` parses `- [ ]`/`- [x]` lines from all notes tagged `#todo`, identifies each item by its line index, and rewrites the note body in-place when toggling.

**Sidebar search focus:** Uses `NotificationCenter` (`Notification.Name.focusSearch`) instead of passing focus state through the view hierarchy — `lsNoteApp` posts on Cmd+Shift+F, `QueryField` listens.

**Backup & export:** File menu commands call `ExportPanels` (AppKit panels/alerts), which delegates to the Foundation-only `MarkdownExport` and `NoteBackup` in `NoteExport.swift`. Backup zips the whole data folder; Markdown export writes front matter + body and rewrites `attachment:` links to a sibling `attachments/` folder.

**Auto-delete:** `EditorView.onDisappear` calls `NoteStore.deleteEmptyNote(id:)`, removing the note and its attachments if the body is blank.

## Persistence paths

| Data | Path |
|---|---|
| Notes | `~/Library/Application Support/lsNote/notes.json` |
| Attachments | `~/Library/Application Support/lsNote/attachments/<noteID>/` |
| Tag metadata | `~/Library/Application Support/lsNote/tags.json` |

See `CONTEXT.md` for keyboard shortcuts, detailed data model, and Markdown renderer feature list.
