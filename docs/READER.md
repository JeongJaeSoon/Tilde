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
| Task list item | `[ ] `, `[x] `, or `[X] ` opening a list item's own first paragraph (any list, any depth) becomes a checkbox in place of the bullet or number, before the same tab stop: SF Symbols `square` / `checkmark.square`, sized to the text and centered on its cap height so the line stays exactly as tall as a bullet's, and kept inside the marker column at large sizes. Apple's parser has no task-list extension and passes the marker through as text, so it must open a plain run — `` `[ ]` ``, `[link](url)`, `[ x]`, `[]`, `[x]` with no space, and brackets in a later paragraph stay text. Done items' box and text recede to quoteColor (links keep linkColor), no strikethrough. Read-only, not clickable. The box takes a palette color, not a template tint (TextKit 1 draws template attachments black), and copies as an attachment character, like images and rules. Its image carries "Done" / "Not done" as the accessibility description (whether VoiceOver reads it is unverified — VERIFY.md). The parser drops a backslash escape before the renderer sees it, so `\[ ]` shows a box too (GitHub shows text) |
| Blockquote | quoteColor + a quiet left bar (NSTextBlock border) |
| Code block | codeFont + one filled NSTextBlock, tokens tinted by `CodeHighlighter` (comments/strings/numbers/keywords) |
| Thematic break | hairline via 1-pt NSTextAttachment image spanning content width |
| Frontmatter | a leading `---` … `---`/`...` block that is empty or carries a top-level `key:` line is sliced off before parsing and shown where it stands, as a quiet header at the top — the editor's lines with the syntax dissolved: `title:` as an H1, then the other keys as rows (key, then value; keys in quoteColor, values in labelColor a point smaller), the closing fence a hairline rule. The body renders as written below it, its own H1 included; the `title:` H1 takes no `#fragment` anchor, so the body's headings keep their GitHub slugs. At most five rows, the rest folded into one "+N more" link, and each value cut to three lines or 240 characters — at a sentence end when one is near (no ellipsis), otherwise between words with "…" (trailing punctuation dropped, so a period never runs into it) — followed by a quiet "more". Clicking "+N more" shows the folded rows (their long values stay cut) and clicking a value's "more" shows that value whole — each on its own, for as long as Reader stays open. Reader swaps in a rebuilt header over the rendering's first `prefixLength` characters, so the body isn't parsed again. Multi-line values are one paragraph per line, indented to the value column, so copied text keeps its newlines. Lists (`[a, b]` / `- a`) join with commas and `\|` / `>` blocks keep their text; a value the small key reader can't flatten (nested map, anchor, flow map, multi-line quoted or flow value) stays in its row as written, in the code face. Keys without values are left out, and a block with nothing left is hidden; only a block with lines that belong to no key appears raw as a code listing. The editor keeps the block editable. An unclosed `---` on line 1, or a `---` rule followed by prose, stays a thematic break |
| Link | linkColor + underline + `.link` attribute (clickable; read-only view makes this safe). The styling lives in the text — the view's `linkTextAttributes` adds only the pointing hand, so the metadata header's "+N more" link can stay quiet. Relative paths resolve against the document's directory; `#fragment` links jump to the matching rendered heading (GitHub-style slugs, duplicates get `-1`/`-2`…); local files open as their own document windows (sandbox permitting); scheme'd URLs go to the system default |
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
- Remote images, raw HTML, footnotes (the parser doesn't emit them anyway)
- Toggling a task-list checkbox from Reader (it is read-only; checkboxes
  are edited as `[ ]` / `[x]` in the editor)
- Print/PDF export from Reader (could ride on the same attributed string later)
