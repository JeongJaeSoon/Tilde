# Tilde Technical Design

Companion to [PRODUCT.md](PRODUCT.md). PRODUCT.md defines *what*; this document defines *how*.

---

## 1. Settled Decisions

| Decision | Choice | Rationale |
| --- | --- | --- |
| Min. deployment target | **macOS 14 (Sonoma)** | Stable TextKit 2 + modern SwiftUI APIs, no legacy branches |
| Text engine | **TextKit 2** | Viewport-based layout → fast with multi-MB files |
| Document layer | **SwiftUI `DocumentGroup`** | SwiftUI-first; NSDocument-backed on macOS so Autosave/Versions/tabs come free. Fall back to `NSDocument` only if we hit a hard wall |
| Document type | **`ReferenceFileDocument`** (class) | Value-type `FileDocument` copies the whole string and re-evaluates SwiftUI on every keystroke; a reference type lets the editor own the text storage directly |
| Editor view | **`NSTextView`** wrapped in `NSViewRepresentable` | Undo, Find bar, spell check, IME, drag & drop all built in |
| Markdown display | **Syntax stays visible; attributes only** | Screen text == file text. No cursor mapping, no layout jumps. Markers rendered small/dim |
| Fully rendered Markdown | **Post-MVP read-only Reader mode (`⌘⇧R`)** | Read-only removes all cursor-mapping complexity; Apple's `AttributedString(markdown:)` fits perfectly there |
| Markdown parser | **Custom lightweight line-based styler, zero dependencies** | "The Markdown parser should not become the center of the app's architecture" (PRODUCT.md §27) |
| Settings storage | **`@AppStorage` / `UserDefaults`** | Settings are tiny (one screen); no config files |
| Buffer ownership | **Document owns `NSTextStorage`; view renders it directly** | Round-tripping the text through SwiftUI copied+compared the whole buffer per keystroke (janky at 4MB). Content becomes a `String` only at save-snapshot time |
| Line rhythm | **`lineSpacing`, not `lineHeightMultiple`** | A 1.5× line box makes the insertion caret 1.5× the text height |
| Fence tracking | **Incremental fence-line cache** (shift by edit delta + rescan edited paragraphs) | Rescanning the document per keystroke cost ~21ms at 4MB; incremental is ~1ms. Verified by a 400-edit fuzz test against full rescan |
| Gutter alignment | **Baseline + cap-height optical centering, per-line font** | Raw baseline sits low for the smaller gutter digits; line-box centering floats. Cap-center matching degrades to baseline alignment at equal sizes |

Known limit (post-MVP): the initial full styling pass is synchronous (~0.8s at 4MB, ~0.2s at 1MB). If large files matter more later, style the viewport first and the remainder in the background.

---

## 2. Architecture

```text
TildeApp (@main)
├── DocumentGroup(newDocument:) ─── macOS document system (open/save/autosave/tabs)
│      └── EditorView (SwiftUI) ─── settings, Reader state, title-bar toggle
│             ├── TextEditorView (NSViewRepresentable) ─── the editor
│             │      └── NSScrollView + EditorTextView (TextKit 2)
│             │             ├── MarkdownStyler / CodeSyntaxStyler ─── edited paragraphs only
│             │             └── LineNumberRulerView ─── optional gutter
│             └── ReaderView (NSViewRepresentable, ⌘⇧R) ─── read-only render
│                    └── NSScrollView + NSTextView (TextKit 1, for NSTextTable)
│                           └── MarkdownRenderer + CodeHighlighter
├── Settings ─── SettingsView
└── Commands ─── View menu (Reader, Word Wrap, Line Numbers, font size ⌘+/⌘-/⌘0)
```

### File layout

```text
Tilde
├── App
│   └── TildeApp.swift             Scenes + menu commands
├── Document
│   ├── TextDocument.swift         ReferenceFileDocument; owns the storage,
│   │                              tracks encoding + line endings
│   ├── FileEncoding.swift         Encoding detection (BOM → UTF-16 → UTF-8)
│   └── LineEnding.swift           Dominant-EOL detect / normalize / restore
├── Editor
│   ├── EditorView.swift           SwiftUI shell; settings + Reader toggle
│   ├── TextEditorView.swift       NSTextView wrapper + Coordinator
│   ├── EditorTextView.swift       NSTextView subclass; unified code-block fill
│   ├── MarkdownStyler.swift       Attribute-only Markdown styling rules
│   ├── CodeSyntaxStyler.swift     JSON/YAML/TOML keys-only highlighting
│   ├── LineNumberRulerView.swift  Adaptive-width gutter (off by default)
│   ├── LineIndex.swift            Incremental newline index for the gutter
│   └── EditorTheme.swift          Font/color tokens (semantic colors only)
├── Reader
│   ├── ReaderView.swift           Read-only rendered Markdown (⌘⇧R)
│   ├── MarkdownRenderer.swift     PresentationIntent → NSAttributedString
│   └── CodeHighlighter.swift      Generic lexer for fenced code blocks
├── Settings
│   ├── AppSettings.swift          @AppStorage keys in one place
│   └── SettingsView.swift         Single-screen settings
├── Localizable.xcstrings          UI strings — en source, ko / ja / zh-Hans
└── InfoPlist.xcstrings            Document type names shown by Finder
```

### Localization

Tilde ships in English, Korean, Japanese, and Simplified Chinese. The
mechanism is the standard one, chosen so there is nothing to maintain:

- **String Catalogs, not `.strings` files.** SwiftUI's `Text("…")`,
  `Button("…")`, `Toggle("…")`, `Section("…")`, `.help("…")` literals are
  `LocalizedStringKey`s already; the only code-side rule is that a string
  handed around as a plain `String` (e.g. `AppearanceSetting.label`, the
  Reader's `(image)` placeholder, error descriptions) goes through
  `String(localized:)`. Interpolations become printf keys — the Settings
  stepper's `"Font Size: \(Int(fontSize)) pt"` is the catalog entry
  `Font Size: %lld pt`.
- **Terminology follows Apple.** Where macOS already names a concept —
  Safari's Reader (읽기 도구 / リーダー / 阅读器), TextEdit's wrap, System
  Settings' appearance — Tilde uses the same words, so the app reads like
  a built-in one (PRODUCT.md §35). Font-size commands match the READMEs.
- **Standard menus come free.** File / Edit / Format / View / Window / Help
  and every system panel are localized by AppKit as soon as the bundle
  contains the matching `<lang>.lproj` folder; the catalogs only cover
  Tilde's own two dozen strings.
- **Adding a language**: add the translations to both catalogs (Xcode's
  catalog editor, or by hand — the file is JSON) and the region to
  `knownRegions` in `project.pbxproj`. `Tests/LocalizationTests` then
  enforces completeness for it once it is added to `shippedLanguages`.
- **Development without Xcode.** `xcodebuild` compiles the catalogs; the
  swiftc smoke bundle can't, so `scripts/compile_xcstrings.py` writes the
  equivalent `.lproj/*.strings` into the bundle. Try a language with
  `open Tilde.app --args -AppleLanguages '(ko)'`.

### Concurrency model

The target uses `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`: everything is
main-actor unless it says otherwise, which is right for a document editor.
Three kinds of code say otherwise, each for a reason the compiler can check
— the whole app type-checks with zero diagnostics in Swift 6 language mode
(`-swift-version 6`), which is how drift gets caught:

- **`TextDocument` is `nonisolated`.** `ReferenceFileDocument` is a
  `Sendable` protocol whose witnesses SwiftUI calls off the main thread
  (the snapshot is serialized on a background queue). Its metadata is
  immutable `let`s; the one main-thread-only member, the `NSTextStorage`
  shared with the text view, is `nonisolated(unsafe)` with the reasoning
  next to it. `FileEncoding`, `LineEnding`, and the `UTType` extension are
  `nonisolated` pure value code the save path can call.
- **The Reader's renderer is `nonisolated`.** `MarkdownRenderer`,
  `CodeHighlighter`, and `EditorTheme` (fonts and colors are `Sendable`)
  are pure functions of their input; `ReaderView` runs them on a global
  queue for documents over the sync threshold, and the isolation makes that
  hop legal rather than merely unchecked.
- **Stylers have isolated conformances.** `MarkdownStyler` and
  `CodeSyntaxStyler` mutate the live buffer from `NSTextStorageDelegate`
  callbacks AppKit delivers on the main thread, so they conform as
  `@MainActor SyntaxHighlighting` (the inheriting conformance has to agree
  with the delegate one).

---

## 3. Document Layer

### TextDocument (`ReferenceFileDocument`)

- Owns the `NSTextStorage` directly (the editor renders it in place — the
  buffer never round-trips through SwiftUI on a keystroke; it becomes a
  `String` only when a save snapshot is taken), plus metadata captured at load:
  - `encoding: FileEncoding` (default `.utf8` for new documents)
  - `lineEnding: LineEnding` (default `.lf` for new documents)
  - `isLossy: Bool` — true when the bytes couldn't be decoded exactly
- **Read**: detect encoding → decode → detect dominant line ending → normalize buffer to LF.
- **Write (snapshot)**: restore original line endings → encode with original encoding.
- Registered content types: `public.plain-text`, `net.daringfireball.markdown`
  and `io.toml.toml` (both imported UTIs, see Info.plist), plus `public.text`
  so the broader family (JSON, XML, …) opens via "Open With".
- Markdown-ness for styling/Reader follows the LIVE file URL
  (`TextDocument.isMarkdown(openedAsMarkdown:fileURL:)`): the current
  extension wins, so Save As between `.md` and `.txt`/`.json` switches
  modes without reopening; the open-time type only decides for
  extension-less files and untitled documents.

### Encoding detection order

1. BOM present → UTF-8 / UTF-16 BE / UTF-16 LE
2. UTF-16 without BOM via the NUL-alternation heuristic (must run before
   the UTF-8 pass — NUL bytes are valid UTF-8)
3. Try strict UTF-8 decode
4. Last resort: lossy UTF-8 (never fail to open a text file)

No encoding conversion UI. What comes in goes back out unchanged — except
the lossy last resort, which CANNOT round-trip (invalid UTF-8, BOM-less
UTF-16 CJK, legacy encodings like EUC-KR): those documents open
**read-only** with a one-line notice, and `fileWrapper` refuses to write
them as a backstop, so a plain open-and-save can never corrupt a file
Tilde couldn't fully read.

---

## 4. Editor Layer

### TextEditorView (the NSTextView wrapper)

- Creates `NSScrollView` + `NSTextView` with TextKit 2 (`NSTextLayoutManager`).
- `Coordinator` is the `NSTextViewDelegate` / `NSTextStorageDelegate`:
  - pushes text changes back to `TextDocument`
  - triggers `MarkdownStyler` on edits
- System features switched on, not built:
  - `usesFindBar = true`, `isIncrementalSearchingEnabled = true` (⌘F / ⌥⌘F)
  - `allowsUndo = true`, undo manager wired to the window's document undo manager
  - spell checking / substitutions follow macOS user settings
- Word wrap toggle = text container width tracking on/off + horizontal scroll.
- Line numbers (off by default): `NSRulerView`-based gutter, added only when
  enabled. Line counting is incremental (`LineIndex`, a sorted newline-offset
  array updated from `NSTextStorage` edit deltas) — no O(n) rescan per
  keystroke, so the gutter stays free on multi-MB documents.
- Keyboard focus: `EditorTextView.viewDidMoveToWindow` claims first
  responder when the window still holds it (a fresh document window parks
  focus on itself — typing went nowhere until a click); Reader exit hands
  focus back through `EditorScrollBridge.focusEditor`.

### Layout (EditorView)

| | Plain text | Markdown |
| --- | --- | --- |
| Content width | full window width | max ≈ 760–900 pt, centered |
| Padding | 24–32 pt | 24–32 pt |
| Body font | SF Mono | SF Pro (SF Mono in code spans) |
| Line height | 1.5–1.6 | 1.5–1.6 |

Colors: semantic only (`.labelColor`, `.textBackgroundColor`, …). Light/Dark/System follows the system with zero custom theming.

### CJK and monospace

SF Mono has no CJK glyphs; Korean/Japanese/Chinese characters fall back to proportional system fonts (Apple SD Gothic Neo, Hiragino Sans, PingFang), breaking column alignment in plain-text mode. This is an industry-wide limitation shared by every major text editor.

If CJK column alignment becomes a requirement, candidate replacement: **Sarasa Gothic** (Iosevka + Source Han Sans, proper 2:1 duospacing across JP/KR/ZH). Would require bundling or user installation.

---

## 5. Markdown Styling

### Principle

Styling is **attributes only** — the character content of the buffer is never modified. Syntax markers stay visible but recede: rendered in `.tertiaryLabelColor` at slightly reduced size.

### Rules

| Element | Content style | Marker style |
| --- | --- | --- |
| Heading 1–3 | SF Pro bold, ~1.6× / 1.4× / 1.2× body | `#` dim |
| Heading 4–6 | SF Pro semibold, ~1.05× body | `#` dim |
| Bold | bold | `**` dim |
| Italic | italic | `*` `_` dim |
| Strikethrough | strikethrough | `~~` dim |
| Inline code | SF Mono, subtle background | `` ` `` dim |
| Code block | SF Mono, subtle background | ``` ``` ``` dim |
| Blockquote | `.secondaryLabelColor` | `>` dim |
| Link | link color | brackets/URL dim |
| List bullet / number | body | marker slightly emphasized |
| Horizontal rule | — | `---` dim |
| Frontmatter (line 1 `---` … `---`/`...`, empty or with a top-level `key:` line) | `.secondaryLabelColor`, no Markdown rules inside | fences dim, never an HR |

### Algorithm

1. On `NSTextStorage.processEditing`, expand the edited range to paragraph boundaries.
2. Reset attributes in that range to body defaults, then apply line rules (heading, quote, list, HR) and inline rules (bold, italic, code, strikethrough, link) via scanner/regex.
3. **Fenced code blocks** and the **leading frontmatter block** are the only cross-line state: maintain a cheap fence map (scan lines starting with ```` ``` ````) refreshed when a fence line itself is edited, and the frontmatter range, rescanned only when an edit reaches into it or line 1 opens a block that has not closed yet. Paragraphs inside a fence get only the code-block style; frontmatter lines get only the frontmatter style.
4. Full-document pass runs once on open; afterwards only edited paragraphs are restyled.

Styling applies only to `.md` / `.markdown` documents with the setting enabled. Plain text mode applies body attributes only.

---

## 6. Settings

```text
Appearance      ○ System  ○ Light  ○ Dark
Font Size       14 (⌘+ / ⌘- / ⌘0)
☑ Word Wrap
☐ Line Numbers
☑ Enhanced Markdown Styling
```

All `@AppStorage`. Font family is fixed (SF Mono / SF Pro) in MVP.

---

## 7. Performance

| Target | Approach |
| --- | --- |
| Cold launch < 500 ms perceived | No work in `App.init`; no frameworks beyond SwiftUI/AppKit; styler built lazily |
| < 1 MB files open instantly | Single decode + one styling pass |
| Multi-MB files usable | TextKit 2 viewport layout; per-paragraph restyling; fence map instead of full reparse |
| Idle CPU ≈ 0 | No timers, no polling, no background work |

---

## 8. Milestones

1. **Skeleton** — DocumentGroup + TextDocument + unstyled NSTextView. Open → edit → save `.txt`/`.md` works end to end, undo/find/spell check via system.
2. **Typography** — fonts, line height, padding, content width, Light/Dark.
3. **Markdown styler** — rules table above, per-paragraph restyling, fence map.
4. **Settings & menus** — Settings scene, View menu, font size commands.
5. **macOS polish** — Info.plist file associations, Dock/window drag-in, Autosave/Versions verification, Open Recent.
6. **Performance pass** — measure cold launch, test multi-MB files, fix hot spots.

Each milestone ends in a state where the app builds, runs, and is demonstrably better than the previous one.

---

## 9. Out of Scope (v1)

- Markdown Reader mode (`⌘⇧R`) — first post-MVP candidate; read-only render via `AttributedString(markdown:)`
- Syntax highlighting for JSON/YAML/etc.
- Quick Open (`⌘P`), word count, always-on-top
- Everything in PRODUCT.md §31 (terminal, Git, plugins, AI, sync, collaboration)
