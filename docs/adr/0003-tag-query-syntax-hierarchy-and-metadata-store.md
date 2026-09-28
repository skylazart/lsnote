# 3. Tag query syntax, hierarchical tags, and a separate tag metadata store

Date: 2026-09-28

## Status

Accepted

## Context

Tags were a flat cloud in the sidebar with a single-tag filter next to a plain substring search. As the number of
tags grew, the cloud stopped being navigable, a note could only be filtered by one tag at a time, and there was no way
to exclude a tag, group related tags, or mark important ones. Tags need to become the main way to navigate and search,
without breaking existing `notes.json` files or adding dependencies.

## Decision

**Query syntax.** The sidebar search is parsed into a `SearchQuery` (pure value type, `SearchQuery.parse(_:)`):

| Input | Meaning |
|---|---|
| `#ocs` | note has tag `ocs` or a descendant |
| `-#todo` | note has neither `todo` nor a descendant |
| `#ocs\|#pulse` | note has `ocs` OR `pulse` |
| `quota` | title or body contains the word (case-insensitive) |
| `"rating group"` | title or body contains the exact phrase |

Top-level clauses are ANDed. Free text no longer matches tag names; tags are matched only through `#` clauses.
Malformed input degrades instead of failing: a lone `#` or `-` is ignored and an unclosed quote runs to the end.
Tag clauses show as chips in the search field. Clicking a tag in the note list or note header replaces the tag
clauses (free text is kept). Clicking a tag in the sidebar list ANDs it in, or removes it if it is already active.

**Evaluation.** An in-memory `TagIndex` maps each tag to its note IDs. It is built once on load and updated
incrementally by `NoteStore` mutations, and only touches tag sets when a note's tags actually change. Tag clauses
are resolved with set operations on the index first; text matching then runs only over the remaining candidates.

**Hierarchical tags.** `/` separates levels (`ocs/diameter`). A tag is still one string in `Note.tags`; the
hierarchy is derived. Parents exist implicitly: `ocs/diameter` alone makes `ocs` appear as a parent node.
`#ocs` matches `ocs` and every descendant, `#ocs/diameter` does not match plain `ocs`, and `-#ocs` excludes the
whole subtree. A parent's count is the number of distinct notes in its subtree. All matching is case-insensitive
through `TagPath.normalize` (lowercase, spaces to hyphens, empty segments dropped).

**Separate metadata store.** Pins (with order), colors and hierarchy expansion are stored in
`~/Library/Application Support/lsNote/tags.json` through `TagMetadataStore`, not in `notes.json`:

- The note schema stays as it is, so there is no migration, and a tag's metadata is independent of which notes
  carry it.
- Entries are never pruned: removing a tag's last note and adding the tag again restores its pin and color.
- Writes are atomic. A missing file means defaults. An unreadable file is moved to `tags.json.corrupt` and
  defaults are used, so the next save cannot destroy it. Unknown fields or color names are skipped.
- Colors come from a fixed palette of 8 system colors, so they adapt to light and dark mode. A tag without its own
  color inherits the nearest ancestor's color.

Pure view preferences (the sort mode and the "show all tags" toggle) live in `UserDefaults` through `AppSettings`,
like the app's other settings.

**"Recently used" ordering** needs a note modification date. `Note` gains a `modifiedAt` field that falls back to
`createdAt` when missing, the same way `isLocked` was added in ADR 2. Existing files load unchanged. The field is
written from then on.

## Consequences

- Pros: multi-tag, exclusion and OR filters; hierarchy without a storage change; pins and colors survive tag churn;
  filtering stays cheap because tag clauses never scan note bodies; the parser, index and store are unit-tested
  (`lsNoteTests`) with no UI or disk access beyond temp files.
- Cons: two files make up the user's data (`notes.json` and `tags.json`); metadata for tags that are gone
  accumulates (it is small, and renaming or merging tags is out of scope); free-text search no longer finds tag
  names without `#`; `/` can no longer be part of a flat tag name.
