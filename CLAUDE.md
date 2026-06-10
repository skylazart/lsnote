# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build

```bash
./build.sh
# or directly:
xcodebuild -scheme lsNote -configuration Release -derivedDataPath build
```

Open `lsNote.xcodeproj` in Xcode to run in debug mode. There is no test suite and no linter configured.

## Architecture

lsNote is a macOS-only (14.0+) note-taking app. SwiftUI for layout, AppKit bridges (`NSViewRepresentable`) for the text editor and Markdown preview. No external dependencies.

**State:** `NoteStore` (`ObservableObject`, `@MainActor`) is the single source of truth — injected as `@EnvironmentObject` from `lsNoteApp`. It holds `@Published notes`, `selectedID`, and `isPreview` (global edit/preview toggle, intentionally not per-note). Every mutation auto-saves to `~/Library/Application Support/lsNote/notes.json`.

**Layout root:** `ContentView` uses `NavigationSplitView` with three columns — sidebar nav (Notes/TODO selector), `SidebarView` or `TodoView`, and `EditorView`.

**Text editing:** `MarkdownTextEditor` wraps `MultiCursorTextView` (an `NSTextView` subclass). All formatting helpers (bold, italic, table insert, find+highlight) are static methods on `MarkdownTextEditor`. The find bar highlights matches via `NSLayoutManager` temporary attributes (orange for current, yellow for others) and is invoked with Cmd+F from `EditorView`.

**Multi-cursor:** `MultiCursorTextView` implements column editing (Alt+drag, Alt+Shift+↑/↓) and multi-match selection (⌘G next / ⇧⌘G previous / ⇧⌘L all occurrences; word-boundary matching when the seed selection was a double-click). Cursor state lives in its `cursors` array (NSTextView has no multi-cursor API); all simultaneous edits go through one `shouldChangeText(inRanges:replacementStrings:)` call so each operation is a single undo step. Escape, a plain click/selection change, or any external text mutation exits multi-cursor mode. `EditorView` shows a status badge ("3 of 7 matches selected") via the `onMultiCursorStatus` callback. The short-line column behavior (skip vs. insert at end of line) is configurable via `AppSettings.columnInsertAtLineEnd`.

**Markdown preview:** `MarkdownPreview` wraps `WKWebView` with a fully custom GFM renderer written in Swift — no Markdown libraries. Attachment images use the syntax `![caption](attachment:uuid.png [WxH])` and are embedded as base64 data URIs to bypass WKWebView's file:// restrictions.

**Images:** `ImageStore` saves PNGs to `~/Library/Application Support/lsNote/attachments/<noteID>/`. Insertion happens via file picker or clipboard paste from `EditorView`'s toolbar.

**TODO view:** `TodoView` parses `- [ ]`/`- [x]` lines from all notes tagged `#todo`, identifies each item by its line index, and rewrites the note body in-place when toggling.

**Sidebar search focus:** Uses `NotificationCenter` (`Notification.Name.focusSearch`) instead of passing focus state through the view hierarchy — `lsNoteApp` posts on Cmd+Shift+F, `SidebarView` listens.

**Auto-delete:** `EditorView.onDisappear` calls `NoteStore.deleteEmptyNote(id:)`, removing the note and its attachments if the body is blank.

## Persistence paths

| Data | Path |
|---|---|
| Notes | `~/Library/Application Support/lsNote/notes.json` |
| Attachments | `~/Library/Application Support/lsNote/attachments/<noteID>/` |

See `CONTEXT.md` for keyboard shortcuts, detailed data model, and Markdown renderer feature list.
