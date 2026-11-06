# 4. Render Mermaid diagrams with a bundled mermaid.js

Date: 2026-11-06

## Status

Accepted

## Context

Notes need to show diagrams written as ```` ```mermaid ```` fenced blocks (sequence diagrams, flowcharts, …).
The preview is a hand-written Markdown renderer with no third-party code. Mermaid's grammar covers many diagram
types and layout engines; re-implementing even one of them in Swift is not realistic. The only practical renderer
is the official `mermaid.js`, which can run inside the preview's `WKWebView`.

We considered loading it from a CDN when a note contains a diagram. That needs a network connection and contacts a
third party on every preview, which doesn't fit a local, private notes app.

## Decision

Bundle `mermaid.min.js` (npm `mermaid` 12.3.0, MIT) as an app resource under `lsNote/Vendor/`, with its license and
a README recording the source and tarball integrity.

- `MarkdownPreview` renders a `mermaid` fence as `<pre class="mermaid">` (escaped source, inside the usual
  collapsible `<details>`), hidden until processed.
- The library is evaluated with `evaluateJavaScript` in the navigation delegate's `didFinish`, and only when the note
  contains a mermaid fence, so notes without diagrams don't pay for parsing ~5.5 MB of JavaScript.
- `securityLevel: 'strict'` (no click handlers or raw HTML in labels); theme follows the system appearance.
- If the resource is missing, mermaid fences fall back to ordinary code blocks.

## Consequences

- Pros: works offline; note content never leaves the machine; full Mermaid feature set; syntax errors render as
  Mermaid's own error diagram.
- Cons: the app's first third-party code; the bundle grows by ~5.5 MB; updates are manual (see
  `lsNote/Vendor/README.md`). Previewing a note with a diagram costs a fraction of a second to evaluate the library.
- Markdown export keeps the fenced source unchanged, which GitHub, Obsidian and most editors render natively.
