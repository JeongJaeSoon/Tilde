# Markdown Reader (⌘⇧R) — Design

Post-MVP Phase 2 feature (see ROADMAP.md). Read-only rendered Markdown as a
**mode**, not a split view (PRODUCT.md §8). Decisions settled 2026-08-15:
full v1 scope (tables + local images + fenced-code highlighting), entered
via the title-bar toggle / ⌘⇧R, exited via the same or Esc.

---

## 1. Architecture

```text
document.textStorage.string
        │
        ▼
AttributedString(markdown:, interpretedSyntax: .full)   Apple parser, zero deps
        │   runs + PresentationIntent (block structure as metadata)
        ▼
MarkdownRenderer                                         intent → attributes
        │   NSAttributedString (EditorTheme tokens)
        ▼
ReaderTextView (read-only NSTextView)                   selection/copy/⌘F free
```

Key fact driving the design: Apple's parser identifies block structure
(header level, list ordinal, quote depth, code language, table geometry)
but applies **no visual styling** — `MarkdownRenderer` walks the runs'
`PresentationIntent` and builds the styled string. That walker is plain
logic → fully testable with the CLI runner on the no-Xcode machine.

### Files

```text
Tilde/Reader/
├── ReaderView.swift         NSViewRepresentable (read-only NSTextView)
├── MarkdownRenderer.swift   String → NSAttributedString
└── CodeHighlighter.swift    Generic lexer for fenced code blocks
```

Plus: `EditorView` gains the mode state, `TildeApp` the menu command.

## 2. Mode switching

- Per-window transient state: `@State var isReaderMode` in `EditorView`.
  Never persisted — a document always opens in the editor.
- **ZStack, not view swap**: the editor stays alive underneath (opacity 0,
  hit-testing off) so caret, scroll, and IME state survive the round trip.
  The Reader view is created lazily on first use.
- Three entry points, all driving the same `isReaderMode` binding:
  1. **Title-bar toggle** — a single `.toolbar` item (`Toggle` in
     `.button` style) beside the file name, shown only for Markdown
     documents. Window uses `.unifiedCompact` toolbar style so there is no
     separate toolbar row. Plain-text/config windows show no button but
     still carry the toolbar (an invisible flexible space): with no
     toolbar at all, AppKit gives those windows a shorter title bar and a
     permanently visible proxy icon, so `.md` and `.txt` windows looked
     subtly different and Save As between them made the title bar jump.
     Every window now shares one title-bar treatment — the proxy icon
     appears on hover, macOS-standard. The book icon fills/accents when
     Reader is active.
  2. **Menu**: View → “Show Reader” / “Hide Reader”, `⌘⇧R`, Safari-style
     dynamic label. Wiring: `focusedSceneValue` binding read by
     `ViewCommands` via `@FocusedValue`.
  3. **Esc** in Reader returns to the editor: `ReaderTextView` subclass
     overrides `cancelOperation(_:)`.
- No "Reader" window subtitle: the title-bar toggle's active state and the
  rendered content already signal the mode, and the title area shows only
  the file name (PRODUCT.md §17).

## 3. Rendering rules (EditorTheme continuity)

Same body size, content-width cap (820), padding, and semantic colors as
the editor — toggling should feel like the markers dissolve, not like a
different app.

| Block | Treatment |
| --- | --- |
| Paragraph | body font, lineSpacing rhythm, paragraphSpacing between blocks |
| Heading 1–6 | `EditorTheme.headingFont`, extra space above |
| Unordered list | inserted `•\t`, hanging indent via tab stop + headIndent |
| Ordered list | inserted `N.\t`, same indent scheme; ordinals from intent |
| Nested lists | indent per nesting depth from the intent stack |
| Blockquote | quoteColor + a quiet left bar (NSTextBlock border) |
| Code block | codeFont + one filled NSTextBlock, tokens tinted by `CodeHighlighter` (comments/strings/numbers/keywords) |
| Thematic break | hairline via 1-pt NSTextAttachment image spanning content width |
| Frontmatter | hidden: a leading `---` … `---`/`...` block that is empty or carries a top-level `key:` line is sliced off before parsing, so the page starts at the real content (the editor keeps it editable). A document that is only frontmatter shows the block as a code listing instead of a blank page. An unclosed `---` on line 1, or a `---` rule followed by prose, stays a thematic break |
| Link | linkColor + `.link` attribute (clickable; read-only view makes this safe). Relative paths resolve against the document's directory; `#fragment` links jump to the matching rendered heading (GitHub-style slugs, duplicates get `-1`/`-2`…); local files open as their own document windows (sandbox permitting); scheme'd URLs go to the system default |
| Inline bold/italic/code/strike | same tokens as the editor styler |
| Table | NSTextTable / NSTextTableBlock paragraph styles (see constraint A) |
| Image (local) | NSTextAttachment, scaled to fit content width (constraint B) |
| Image (remote) | never fetched — alt text styled as a link (privacy §30) |

### Constraint A — tables force TextKit 1 in the Reader view

`NSTextTable` is not supported by TextKit 2; NSTextView falls back to
TextKit 1 for content containing text blocks. Acceptable: the Reader is
read-only and rendered per-toggle, so TK1 performance characteristics
don't matter. The EDITOR stays TextKit 2 — only `ReaderTextView` is
affected. Note: construct the Reader NSTextView the classic way to avoid
mixed-mode surprises.

### Constraint B — sandbox blocks sibling images

Opening `doc.md` grants sandbox access to that file only, NOT to
`./images/foo.png` next to it. Behavior:

1. Resolve the image URL relative to the document's directory
2. Try to load; on success → attachment, scaled to `min(natural, content width)`
3. On denial/missing → render alt text in quoteColor with a small missing-image mark

The unsandboxed smoke bundle will always load images (dev machine);
Real sandbox behavior gets verified on the Xcode device. If real-world use
demands sibling images, revisit with a security-scoped folder grant —
that's a product decision (quiet app vs permission prompt), not v1.

## 4. Content, performance & scroll sync

- Render happens on: entering Reader, document instance change (Revert),
  font size change. NOT live-per-keystroke — there is no editing path
  while the editor is hidden. Exactly ONCE per entry: the file URL (for
  relative link/image resolution) is passed into `ReaderView` rather than
  read off the window, so nothing needs a second deferred render, and the
  render cache key includes content, font size, AND base URL.
- **Performance**: Apple's `AttributedString(markdown:)` parser dominates
  the cost and cannot be sped up (measured: ~90 ms at 50 KB, ~170 ms at
  100 KB, ~1.8 s at 1 MB, ~7.5 s at 4 MB). Documents ≤ 256 KB render
  synchronously (no flash); larger ones render on a background queue with a
  generation token so ⌘⇧R never freezes the UI. Verified with a size-sweep
  benchmark and a 500-input renderer fuzz (no crashes).
- Scroll position: Reader opens at the editor's reading position — the
  editor reports the fraction of characters above its viewport
  (`EditorScrollBridge.readFraction`) and Reader scrolls there after
  render. It's the approximate fractional mapping ROADMAP sketched, not
  live sync: positions are exchanged only at mode entry, and continuous
  editor↔Reader sync stays deferred (§7).

## 5. Failure policy

The renderer must never fail: `failurePolicy: .returnPartiallyParsedIfPossible`,
and if parsing throws entirely, fall back to plain body-styled text.
A fuzz test (random byte-noise + truncated markdown) asserts no crash.

## 6. Milestones

1. **Renderer core** — paragraphs, headings, lists, quotes, code blocks,
   HR, links, inline styles. CLI attribute tests (styler-test pattern)
2. **Mode plumbing** — ReaderView, ZStack toggle, ⌘⇧R/Esc, menu item,
   subtitle. Smoke-verify via osascript + screenshots
3. **Tables** — NSTextTable rendering, alignment from column intents
4. **Local images** — attachment loading, scaling, alt-text fallback
5. **Polish** — renderer fuzz + big-doc perf (async render above the size
   threshold). Scroll fraction sync deferred to v2.

Each milestone ends buildable + visually verified on the smoke bundle.

Status: milestones 1–5 implemented and verified on the smoke bundle
(renderer 75 CLI tests incl. fuzz, link resolution, and an entry-cost
timing bound; mode toggle, tables, and local images confirmed visually).
Post-review additions: relative/fragment link navigation, single-render
entry, and focus restore on every Reader exit (2026-08 app review). Remaining
before shipping: real-sandbox image behavior and the whole feature under
a full Xcode build (docs/VERIFY.md).

## 7. Explicitly not in v1

- CONTINUOUS scroll sync between editor and Reader (entry position IS
  restored via fractional offset — see §4; live two-way sync is v2)
- Live side-by-side or live-typing reader (mode only, §8)
- Remote images, raw HTML, footnotes, task-list checkboxes (the parser
  doesn't emit them anyway)
- Print/PDF export from Reader (could ride on the same attributed string later)
