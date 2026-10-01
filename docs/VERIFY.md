# Xcode-Device Verification Checklist

Everything below needs the machine with Xcode (this dev Mac has only
Command Line Tools — code is verified here via swiftc typechecks, CLI test
runners, and the unsigned smoke bundle).

## Build

- [ ] `xcodebuild -project Tilde.xcodeproj -scheme Tilde build` succeeds
      (code already typechecks with `-default-isolation MainActor`; failures
      here would be project-config issues, not code)
- [ ] Asset catalog compiles — AppIcon renders in Dock, Finder, and ⌘Tab
- [ ] No warnings (the former `NSTextStorage`-Sendable one is resolved:
      `TextDocument` is explicitly `nonisolated` to match SwiftUI's
      background save path, with `nonisolated(unsafe)` narrowed to the
      main-thread-only text storage — see the comment in TextDocument.swift)

## Sandbox (the smoke bundle runs unsandboxed — these are UNVERIFIED)

- [ ] Open a file via Finder double-click → edit → ⌘S saves
- [ ] Save As (⌘⇧S) to a new location works
- [ ] Open via drag onto Dock icon and drag into an open window
- [ ] Reopen recent files via File → Open Recent

## File associations (Info.plist UTIs)

- [ ] `.md` / `.markdown` show Tilde in Finder's Open With
- [ ] `.txt` shows Tilde in Open With
- [ ] `.json` / `.log` / `.yml` open via Open With (plain text mode)
- [ ] "Get Info → Change All" association sticks
- [ ] `.toml` opens as text and shows key highlighting (needs the imported
      `io.toml.toml` UTI to register — verify on a clean install, since
      LaunchServices caches the dynamic type)

## Document behavior

- [ ] Save As an untitled document with Format "Markdown Document" →
      typography, Markdown styling, and the title-bar Reader toggle appear
      immediately (no reopen). Same live switch for `.json`/`.yaml`/`.toml`
      key highlighting via Save As. (Not automatable on the dev machine —
      the save panel's format picker needs a human.)
- [ ] Launching the app without a document opens a blank Untitled window,
      not the open panel (`NSShowAppCentricOpenPanelInsteadOfUntitledFile`
      registered false)

- [ ] Autosave: edit, wait, force-quit → relaunch restores content
- [ ] Versions: File → Revert To shows history and restores
- [ ] Window tabs (Window → Merge All Windows) behave
- [ ] Dirty-close on an untitled document prompts to save;
      existing documents close silently (autosave-in-place)
- [ ] Lossy-encoding file (e.g. EUC-KR, or BOM-less UTF-16 Korean): opens
      read-only with the notice bar, typing does nothing, and no save path
      (⌘S, autosave, Versions) writes the file (verified via CLI tests +
      smoke bundle on the dev machine; re-check under the sandbox)
- [ ] Mixed line endings (e.g. `a\r\nb\r\nc\r\nd\ne\r\n`): edit line 1 and
      ⌘S — only that line's ending changes (`d` keeps its LF); autosave,
      Save As and Duplicate without edits are byte-identical
      (regression-tested by CLI tests + `Tests/ui_smoke.sh`)
- [ ] Focus: ⌘N then type immediately — text lands in the body; Reader →
      Esc then type — same (regression-tested by `Tests/ui_smoke.sh` on
      the dev machine)

## Performance (targets from PRODUCT.md §28)

- [ ] Cold launch < 500 ms perceived (smoke bundle measured ~225 ms
      including LaunchServices overhead)
- [ ] 4 MB markdown opens in ~1 s, typing stays smooth

## Markdown Reader (⌘⇧R)

- [ ] ⌘⇧R toggles Reader; Esc returns to editor (and focus returns to the
      editor — typing works without a click)
- [ ] Command disabled for plain-text (.txt) documents
- [ ] Headings, lists, quotes, code blocks, HR, links, inline styles render
- [ ] Frontmatter: a post with `title:`, more than six other keys, and a
      long `description:` shows the title as the top H1, aligned key–value
      rows, a hairline, then the body. "+N more" and a value's "more"
      unfold in place, each on its own; hovering them shows the pointing
      hand while the text stays gray, and VoiceOver reads them as links.
      The editor shows the same block with dim fences and no Markdown
      styling inside (header layout and the unfolded rebuild are covered
      by `RendererTests`; the click path, real hover, and VoiceOver are
      not)
- [ ] A document that opens with a `---` rule and uses later `---` rules as
      chapter breaks renders every chapter, with no header
- [ ] Relative links: clicking `[x](other.md)` opens the file in Tilde
      **under the sandbox** (expected to work only for already-readable
      paths — on denial the click just beeps); `#fragment` links scroll to
      the matching heading
- [ ] Tables render with borders and column alignment
- [ ] Task lists: `- [ ]` / `- [x]` show an empty / checked box in place of
      the bullet, done items gray, in light and dark mode and across a live
      appearance switch while Reader is open; the boxes don't react to
      clicks. Check what VoiceOver says for a box — each carries "Done" /
      "Not done" as its image description, but an in-process accessibility
      probe found NSTextView doesn't expose attachments as elements, so it
      may read nothing useful (layout, colors, and boundaries are covered
      by `RendererTests` / `StylerTests`; the live switch and VoiceOver are
      not)
- [ ] **Sandbox image behavior** (unverifiable on the unsandboxed smoke
      bundle): a sibling `./image.png` is blocked by the sandbox and should
      show the alt-text fallback, NOT the image. Decide whether to add a
      security-scoped folder grant (product call) if this matters.
- [ ] Large document (~1 MB+) Reader does not freeze the UI (async render)

## Icon

- [ ] Regenerate if needed: `swift scripts/gen_icon.swift <outdir>` then
      copy sizes into `Tilde/Assets.xcassets/AppIcon.appiconset/`
