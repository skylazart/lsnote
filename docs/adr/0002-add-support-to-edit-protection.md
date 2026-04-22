# 2. Add support to Edit Protection

Date: 2026-04-22

## Status

Accepted

## Context

To prevent accidental modifications to personal notes during reading or navigation, the application needs a way to "
freeze" content. We rejected an auto-lock timer to avoid user confusion and ensure the application remains predictable.

## Decision

Implement a Manual Toggle to switch between editing and viewing:

- User Trigger: A lock/unlock icon in the toolbar toggles the state.
- State Persistence: The is_locked status is saved per note. Locked notes will always open in Preview Mode by default
  until manually unlocked.

## Consequences

- Pros: Total user control; eliminates "invisible" logic; provides a clean reading experience.
- Cons: Requires manual action to protect notes; adds a boolean field to the note data schema.
