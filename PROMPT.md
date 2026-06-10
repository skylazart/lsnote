# Feature Prompt: Multi-Cursor Column & Match Editing

Add multi-cursor column editing and multi-match selection to the markdown editor.

---

## PART 1 — COLUMN MODE EDITING

### Activation
- `Alt+Click` and drag vertically to create a column selection across multiple lines
- `Alt+Shift+ArrowUp` / `Alt+Shift+ArrowDown` to extend a column selection from the current cursor position

### Core Behavior
- When a column selection is active, place a virtual cursor at the same column position on every selected line
- Any typed characters are inserted at that column position on all selected lines simultaneously
- `Backspace`/`Delete` removes the character at that column position on all selected lines simultaneously

### Key Use Case — Prepend text to multiple lines
1. User clicks at column 0 of the first line
2. User extends the column selection down to the last target line (via `Alt+drag` or `Alt+Shift+Down`)
3. User types `- ` (or any prefix)
4. Result: `- ` is inserted at the beginning of every selected line

**Example:**

```
Before:       After typing "- ":
first         - first
second   →    - second
third         - third
```

### Copy/Paste
- `Ctrl+C` with a column selection copies the rectangular text block (one entry per line)
- `Ctrl+V` pastes the block as a column insert at the current cursor column, one entry per line

### Visual Feedback
- The column selection must be visually distinct (e.g. a highlighted rectangle or matching highlights on each line)
- Each active cursor line should show a blinking cursor at the correct column offset

### Edge Cases
- If a line is shorter than the selected column, skip insertion on that line (or insert at end of line — make this configurable)
- Pressing `Escape` cancels the column selection and returns to normal single cursor
- `Ctrl+Z` should revert all simultaneous insertions/deletions as a single undo step

---

## PART 2 — MULTI-MATCH SELECTION (Find & Select)

### Activation
- User selects a word or phrase with a normal click+drag or double-click
- `Cmd+G` (Mac) / `Ctrl+G` (Windows/Linux) selects the **next** occurrence of that word/phrase
- Pressing `Cmd+G` / `Ctrl+G` repeatedly keeps adding the next occurrence to the selection
- `Cmd+Shift+G` / `Ctrl+Shift+G` selects the **previous** occurrence
- `Cmd+Shift+L` / `Ctrl+Shift+L` selects **all** occurrences of the word/phrase at once

### Core Behavior
- Each matched occurrence gets its own independent cursor and selection highlight
- All active cursors behave identically: typing replaces all selected occurrences simultaneously
- `Backspace`/`Delete` removes the selected text at every cursor position simultaneously
- Any text operation (cut, paste, type) applies to all matched selections at once

### Key Use Case — Rename a word across the document
1. User double-clicks a word, e.g. `foo`
2. User presses `Cmd+G` twice to also select the 2nd and 3rd occurrences of `foo`
3. User types `bar`
4. Result: all selected occurrences of `foo` are replaced with `bar` simultaneously

### Match Behavior
- Matching is case-sensitive by default
- Matches respect word boundaries when the original selection was made via double-click
- Matches do not respect word boundaries when the selection was made via click+drag (partial word)

### Visual Feedback
- Each active match is highlighted with a distinct selection color
- All other non-selected occurrences of the word in the document are shown with a subtle secondary highlight (like a "find" highlight), so the user knows how many matches exist
- A small badge or count indicator shows `X of Y matches selected` somewhere unobtrusive (e.g. bottom right of the editor or inline near the last cursor)

### Edge Cases
- Pressing `Escape` cancels all multi-match selections and returns to a single cursor
- `Ctrl+Z` should revert all simultaneous edits as a single undo step
- If a new match would overlap with an existing selection, skip it
- Selections should update live if the document content changes between `Cmd+G` presses

---

## SHARED REQUIREMENTS

- Column selections and multi-match selections are mutually exclusive; activating one cancels the other
- All multi-cursor operations must be treated as a single atomic undo step
- `Escape` always clears all active cursors and returns to normal editing mode
- Both features must work correctly inside markdown code blocks, tables, and lists
- Implement this using the editor's existing extension or plugin API if available (e.g. CodeMirror 6 extensions, Monaco editor contributions, or ProseMirror plugins). If the editor does not have a native API for this, implement it using multiple cursor state tracked in a custom hook or state manager

