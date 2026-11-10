# 5. AI actions via the Claude API

Date: 2026-11-10

## Status

Accepted

## Context

Notes often need mechanical rewriting: cleaning up Markdown, fixing grammar, translating between
Portuguese (Brazil) and English. We want to hand the selection, or the whole note, to an AI model
with either a predefined prompt or one the user writes, without adding package dependencies
(the app has none) and without letting a model change a note unseen.

## Decision

- **Backend:** call the Claude Messages API directly over HTTPS with `URLSession` and read the
  server-sent event stream. Anthropic has no Swift SDK, and a local agent CLI would make the feature
  depend on software outside the app. The model defaults to `claude-haiku-5-5` and is a free-text
  setting.
- **Credentials:** the API key lives in the login keychain (`KeychainStore`), never in
  `UserDefaults` or `notes.json`. `ANTHROPIC_API_KEY` in the environment is a fallback for
  development runs.
- **Actions:** an `AIAction` is a name plus an instruction. Built-ins are compiled in
  (`AIAction.builtIns`); custom ones are stored as JSON in `UserDefaults` and edited in
  Settings → AI. A one-off "Custom Prompt…" needs no saved action.
- **Scope:** the selection if there is one, otherwise the whole note.
- **Review before write:** the result streams into a sheet. Nothing changes until the user picks
  Replace or Insert Below, which go through the text view as a single undoable edit; Copy leaves the
  note untouched. Locked notes can run actions but only copy the result.
- **Prompt shape:** the instruction and the note text are sent in separate tags, and the system
  prompt tells the model the text is material to transform, not instructions to follow.

## Consequences

- Pros: no dependencies; works with any Claude model; edits are always reviewed and undoable; the
  pure parts (`AIAction`, `AIPrompt`, `AIStreamEvent`) are unit-tested without the network.
- Cons: needs an API key and is billed per use; the text of the note is sent to a third party when
  an action runs (stated in Settings); attachments are not sent, so actions see image links only.
