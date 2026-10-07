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
- [ ] `id_ed25519`, `id_ed25519.pub`, `.gitignore`, `.env`, `Dockerfile`
      open via Open With, the open panel, and a Dock drag, as plain text
      (no Markdown styling or key highlighting). Test on a clean install or
      after `lsregister -f`, since LaunchServices caches document types.
      LaunchServices doesn't offer an app that lives under `/tmp` in Open
      With, so copy a build from a temporary DerivedData path elsewhere first
- [ ] Edit and save `id_ed25519`: the name stays the same and permissions
      stay `-rw-------` (ssh refuses a group/world-readable private key)
- [ ] The save panel's format menu for a new document gains no
      "Other Text File" / data entry
- [ ] A PNG or PDF picked in the open panel shows the "isn't a text file"
      alert
- [ ] Tilde does not become the default app for any file type it wasn't
      before (Finder Get Info on a `.png`, `.zip`)

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
- [ ] **Sandbox image behavior** (unverifiable on the unsandboxed smoke
      bundle): a sibling `./image.png` is blocked by the sandbox and should
      show the alt-text fallback, NOT the image. Decide whether to add a
      security-scoped folder grant (product call) if this matters.
- [ ] Large document (~1 MB+) Reader does not freeze the UI (async render)

## In-app updates (DMG build only, #27)

Needs two signed, notarized DMG builds with different `CURRENT_PROJECT_VERSION`
values (e.g. from Actions → Release → Run workflow), and a test appcast that
points at the newer one.

Already exercised end to end on the dev machine (2026-10-02) with
`scripts/build_direct.sh` copies under a test bundle ID: ad-hoc signed,
sandboxed (with the `-spks`/`-spki` exception), a throwaway EdDSA key, and
a localhost feed. Menu placement, no request at launch, the dialog, sandboxed
download + install + relaunch, and "up to date" all worked. Not covered
there: the hardened runtime (ad-hoc signatures fail its library validation,
so the copies ran without it), Developer ID signing, notarization, and
Gatekeeper on the downloaded update.

- [ ] Tilde menu shows **Check for Updates…** right below About Tilde; the
      App Store / plain Xcode build has no such item
- [ ] Launching and idling makes no network requests (no automatic check,
      no "check automatically?" prompt on the second launch)
- [ ] With the newest version installed: Check for Updates… says you're up
      to date
- [ ] With the older version installed: the dialog shows the release notes
      (Markdown rendered) and Install Update / Skip This Version, with no
      "install automatically" checkbox (Sparkle drops Remind Me Later while
      automatic checks are off; closing the window does the same)
- [ ] Install Update **under the sandbox**: downloads, quits, replaces
      `/Applications/Tilde.app`, relaunches as the new version; open
      documents and unsaved edits come back (autosave)
- [ ] A DMG whose signature doesn't match the appcast's `edSignature` is
      refused
- [ ] Localized menu item in ko / ja / zh-Hans

## Icon

- [ ] Regenerate if needed: `swift scripts/gen_icon.swift <outdir>` then
      copy sizes into `Tilde/Assets.xcassets/AppIcon.appiconset/`
