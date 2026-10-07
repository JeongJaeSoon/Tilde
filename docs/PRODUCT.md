# Tilde Product Specification

**A tiny, beautiful text editor for macOS.**

> `~` — home, plain text, and nothing more than you need.

## 1. Product Overview

### 1.1 Background

The way software is built has changed.

In the past, developers spent much of their time reading and editing code directly inside an IDE. With AI-assisted development, they need to inspect the code itself far less often. As a result, a general-purpose code editor feels unnecessarily heavy when all you need to do is check a single `.txt` or `.md` file.

Tilde fills that gap as an ultra-lightweight text editor for macOS.

The goal is not to make a smaller version of a full IDE.

The goal is to build an app that is **instant, quiet, and beautiful** — the best possible place to read and lightly edit plain text.

---

## 2. Product Vision

Tilde aims to make the editor itself disappear when a user opens a file.

Launch the app, read the file, change a few characters, and close it.

At no point should the user have to think about projects, workspaces, plugins, terminals, Git, sidebars, or session management.

### Core Values

**Instant**

Double-click a file and it opens almost immediately.

**Quiet**

The interface never draws more attention than the content.

**Native**

It behaves like a built-in macOS app.

**Beautiful**

Reading text is a pleasure in itself.

**Disposable**

There is almost nothing to configure or manage.

---

## 3. Target User

Tilde is primarily for:

- Developers who work with AI and spend less time in code editors
- People who frequently read Markdown documents
- People who want to briefly inspect a README, note, or configuration file
- People who do not want to launch a heavy editor just to open a plain-text file
- People who want a better plain-text experience without the complexity of a full editor

Tilde is not intended for:

- Developers who need an IDE
- People who need to navigate dozens of files at once
- People who need Git integration
- People who want a plugin ecosystem
- People who need a project-based development environment

---

## 4. Core Philosophy

### 4.1 Document First

Tilde has no concept of a project.

Its fundamental unit is always **one file**.

```text
Open File
   ↓
Read / Edit
   ↓
Save
   ↓
Close
```

There is no workspace model.

---

### 4.2 Content Over Chrome

The text is the most important thing on the screen.

Remove as much editor UI as possible.

The default window layout:

```text
┌──────────────────────────────────────────┐
│              README.md                   │
├──────────────────────────────────────────┤
│                                          │
│        # Hello                           │
│                                          │
│        This is some text.                │
│                                          │
│                                          │
│                                          │
└──────────────────────────────────────────┘
```

Keep the always-visible elements to a minimum:

- File name
- Document content

There is no status bar by default.

---

## 5. Primary User Scenarios

### Scenario A — Read Markdown

The user double-clicks `README.md` in Finder.

Tilde launches immediately.

Markdown syntax is presented for easy reading.

The user reads the document and closes the window with `⌘W`.

---

### Scenario B — Make a Small Edit

The user opens `notes.txt`.

They edit a few lines.

`⌘S`.

Done.

---

### Scenario C — Write New Text

The user launches Tilde.

A blank document appears.

They write some text.

`⌘S`.

They choose a name and location in the macOS save panel.

---

### Scenario D — Inspect an AI-Generated File

An AI coding agent creates files such as:

```text
README.md
SPEC.md
TODO.md
config.json
.env.example
```

The user opens one in Finder and quickly reviews it in Tilde.

If necessary, they change a line or two.

---

## 6. Supported Files

### MVP

Officially supported formats:

```text
.txt
.md
.markdown
```

In practice, Tilde should be able to open most UTF-based plain-text files.

Examples:

```text
.json
.yaml
.yml
.toml
.xml
.csv
.log
.env
.gitignore
```

Files with no extension, or one macOS doesn't know, open the same way as
long as their contents are text:

```text
id_ed25519
id_ed25519.pub
config
Dockerfile
```

They open as plain text, and saving keeps the name as is. A file whose
contents aren't text (an image, a PDF) is refused with a short alert.

Tilde does not provide dedicated IDE features for these formats.

They are all treated as **plain text**.

---

## 7. Editor Modes

Tilde provides two document representations.

### 7.1 Plain Text

A standard text editing view.

Every file, including Markdown, can be viewed as raw text.

---

### 7.2 Markdown Enhanced Editing

For Markdown files, Tilde provides **lightweight semantic styling**.

It is not a full WYSIWYG editor.

For example:

```markdown
# Hello
```

The `#` remains visible while the heading text is rendered slightly larger.

```markdown
**important**
```

The bold syntax remains visible while the enclosed text can also be rendered in bold.

The goal is not:

> To hide Markdown

It is:

> To make Markdown easier to read

#### Styled Elements

- Heading
- Bold
- Italic
- Strikethrough
- Inline code
- Code block
- Blockquote
- Link
- Bullet list
- Numbered list
- Horizontal rule

---

## 8. Markdown Reader

The MVP does not include a separate preview pane.

Tilde will not provide a split view like this:

```text
Editor │ Preview
```

Tilde is not a Markdown IDE.

Instead, the editor itself presents Markdown in a readable way.

If there is a demonstrated need later, a **Reader mode** could be added with a shortcut such as:

```text
⌘⇧R
```

---

## 9. Window Model

Tilde follows the macOS document-based app model.

### One File = One Window

```text
README.md → Window
TODO.md   → Window
notes.txt → Window
```

Opening multiple files creates multiple windows.

The system's standard window tab behavior remains available.

Tilde does not implement its own tab system.

---

## 10. Launch Behavior

### Opening a File from Finder

Display the file's contents immediately.

### Launching the App from the Dock

Create a new blank document.

The MVP does not include a custom start screen with a list of recent files.

Use the standard macOS **File → Open Recent** menu instead.

---

## 11. Editing Features

The MVP supports the following features.

### Basic Editing

- Undo / Redo
- Cut
- Copy
- Paste
- Select All
- Drag-and-drop text
- macOS spell checking
- macOS substitutions (smart quotes/dashes default OFF — they corrupt code
  and config files; re-enable per window via Edit ▸ Substitutions)
- Find
- Find & Replace

### Find

Keyboard shortcuts:

```text
⌘F     Find
⌘G     Find Next
⌘⇧G    Find Previous
⌥⌘F    Find & Replace
```

Use standard macOS behavior wherever possible.

---

## 12. Line Numbers

Default:

**Off**

Tilde is not a code editor.

Line numbers can be enabled in Settings.

```text
☐ Show Line Numbers
```

Even when line numbers are enabled, keep their UI as subtle as possible.

---

## 13. Word Wrap

Default:

**On**

Setting:

```text
View
 ├─ Word Wrap
 └─ Line Numbers
```

---

## 14. Font

Default font:

**SF Mono**

Alternatively, use the default macOS monospaced font.

Markdown Enhanced Editing may mix SF Pro and SF Mono according to context.

For example:

```text
Heading       → SF Pro
Paragraph     → SF Pro
Inline Code   → SF Mono
Code Block    → SF Mono
```

Plain Text mode uses SF Mono.

---

## 15. Typography

Typography is the most important part of Tilde's design.

Core principles:

- Generous line height
- Avoid excessively long lines
- Generous horizontal padding
- High text contrast
- Minimal UI chrome

Recommended defaults:

```text
Body Font Size    14–15pt
Line Height       1.5–1.6
Editor Padding    24–32pt
```

Even in a wide window, a Markdown document's content width may be constrained to keep lines from becoming too long.

For example:

```text
max content width ≈ 760–900pt
```

Plain text can use the full width of the window.

---

## 16. Appearance

Automatically support the following appearance options:

- Light
- Dark
- System

Tilde does not provide its own theme system.

Use macOS semantic colors wherever possible.

```swift
Color.primary
Color.secondary
Color(nsColor: .textBackgroundColor)
```

---

## 17. Window Design

Use the standard macOS window chrome wherever possible.

Avoid an overly customized title bar.

The toolbar is empty by default.

Only the file name appears in the title area.

For example:

```text
             README.md
```

Use the standard macOS document-edited indicator for unsaved changes.

---

## 18. Focus Mode

Tilde's default interface should already feel like a focus mode.

The MVP therefore does not include a separate Focus Mode feature.

If the interface needs a feature to hide it, the default interface is already too complex.

---

## 19. File Saving

Use the standard macOS document-saving behavior.

Supported shortcuts:

```text
⌘S       Save
⌘⇧S      Save As
```

When a modified document is closed, display the standard macOS save confirmation.

Use the macOS document architecture for autosave.

---

## 20. Encoding

Default:

```text
UTF-8
```

Candidate encodings:

```text
UTF-8
UTF-16
UTF-16 LE
UTF-16 BE
```

In the MVP, detect and handle encodings automatically wherever possible.

An encoding conversion interface is not required.

Complex, fine-grained encoding management is out of scope.

---

## 21. Line Endings

Readable formats:

```text
LF
CRLF
CR
```

Preserve the existing line endings when saving whenever possible.

Default for new documents:

```text
LF
```

The MVP does not include a separate line-ending selector.

---

## 22. Settings

Settings should be very small.

For example:

```text
General

Appearance
○ System
○ Light
○ Dark

Editor
Font                   SF Mono
Font Size              14
☑ Word Wrap
☐ Line Numbers

Markdown
☑ Enhanced Markdown Styling
```

All settings should fit on a single screen if possible.

---

## 23. Keyboard Shortcuts

Follow macOS conventions.

| Action | Shortcut |
| --- | --- |
| New | `⌘N` |
| Open | `⌘O` |
| Save | `⌘S` |
| Save As | `⌘⇧S` |
| Close | `⌘W` |
| Find | `⌘F` |
| Find Next | `⌘G` |
| Find Previous | `⌘⇧G` |
| Preferences | `⌘,` |
| Increase Font | `⌘+` |
| Decrease Font | `⌘-` |
| Reset Font | `⌘0` |

---

## 24. macOS Integration

Tilde should behave like a proper macOS app.

Support:

- Finder Open With
- Default app association
- Drag a file onto the Dock icon
- Drag a file into an app window
- Recent Documents
- macOS Autosave
- macOS Versions
- Full Screen
- Window Tabs
- Services
- Share
- A Quick Look-friendly file structure

Wherever possible, do not reimplement features that macOS already provides.

---

## 25. File Associations

After installation, users can associate Tilde with the following extensions.

Primary:

```text
.txt
.md
.markdown
```

Secondary:

Support plain-text UTIs so that other text files can also be opened through Open With.

---

## 26. Architecture

Technology stack:

```text
Swift
SwiftUI
AppKit
```

Use SwiftUI as the primary implementation technology wherever possible.

However, because AppKit's `NSTextView` is a mature text editor on macOS, wrap it for SwiftUI when needed.

For example:

```text
SwiftUI
   │
   ├── DocumentGroup
   │
   ├── EditorView
   │
   └── Settings
          │
          ▼
       NSTextView
```

### Recommended Structure

```text
Tilde
├── App
│   └── TildeApp.swift
│
├── Document
│   ├── TextDocument.swift
│   └── FileEncoding.swift
│
├── Editor
│   ├── EditorView.swift
│   ├── TextEditorView.swift
│   └── MarkdownStyler.swift
│
├── Settings
│   └── SettingsView.swift
│
└── Utilities
```

Do not use a large-scale architecture framework.

Redux, TCA, and similar frameworks are unnecessary.

---

## 27. Markdown Implementation

First, evaluate Apple's Markdown support in `AttributedString` for parsing.

Introduce a separate parser only if the built-in functionality is insufficient.

Principle:

> Do not build a Markdown editor just to support Markdown.

The Markdown parser should not become the center of the app's architecture.

---

## 28. Performance Goals

Performance is one of Tilde's most important competitive advantages.

### Launch

The app should become editable as quickly as possible after the user clicks its icon.

Targets:

```text
Cold Launch < 500ms perceived
Warm Launch ≈ instant
```

### File Opening

Typical text files under:

```text
< 1 MB
```

should open effectively instantly.

Tilde should also handle files several megabytes in size without difficulty.

---

## 29. Resource Usage

When the app is open and idle, its CPU usage should be effectively zero.

Do not run unnecessary:

- Background processes
- File indexing
- Sync
- Analytics workers
- Update polling

---

## 30. Privacy

By default, Tilde processes every document locally.

No server uploads.

No account.

No sign-in.

No cloud storage.

No AI features.

If telemetry is ever added, limit it to app usage statistics and never collect file contents.

If possible, do not include analytics at all in the initial release.

---

## 31. Explicit Non-Goals

Tilde does not include the following features.

### Development

- Terminal
- Git
- GitHub
- Debugger
- Build
- Run
- LSP
- IntelliSense
- Code Completion
- Refactoring
- Project Explorer

### Extensibility

- Extensions
- Plugins
- Marketplace

### Knowledge Management

- Notes database
- Tags
- Backlinks
- Vault
- Wiki
- Sync

### Collaboration

- Accounts
- Comments
- Shared workspaces
- Real-time collaboration

### AI

- AI completion
- AI chat
- AI rewrite
- AI agent

Do not add features that turn Tilde back into a full IDE.

---

## 32. MVP

### Version 1.0

Required features:

- [ ] Native macOS document app
- [ ] Open, edit, and save `.txt` files
- [ ] Open, edit, and save `.md` files
- [ ] New documents
- [ ] Undo / Redo
- [ ] Find / Replace
- [ ] Word Wrap
- [ ] Font size adjustment
- [ ] Light / Dark Mode
- [ ] Basic Markdown styling
- [ ] Finder file associations
- [ ] Drag & Drop
- [ ] macOS Autosave
- [ ] Basic Settings
- [ ] Fast launch

This is enough for Tilde 1.0.

---

## 33. Post-MVP Candidates

Add these only after real-world use demonstrates a genuine need.

### 1. Markdown Reader

A read-only rendered mode.

### 2. Syntax Highlighting

Very lightweight highlighting for JSON, YAML, Swift, and similar formats.

Do not expand it to IDE-level functionality.

### 3. Quick Open

A small command palette for opening recent documents quickly.

For example:

```text
⌘P
```

### 4. Character / Word Count

Information that appears only when needed.

### 5. Always on Top

This could be useful when referring to a short note or README.

---

## 34. Feature Admission Rule

Ask three questions before adding a new feature.

### Question 1

Does this feature improve the experience of **reading or making a small edit to a text file**?

### Question 2

Does macOS already provide this feature?

If so, do not implement it ourselves.

### Question 3

Does this feature require users to learn a new concept?

If so, avoid adding it whenever possible.

---

## 35. Design Touchstones

The qualities Tilde aims for.

### Reading & writing feel

- Careful typography
- Markdown readability
- Content-centric layout
- Visual calmness
- A pleasant writing experience

### Native reliability

- Native macOS behavior
- Fast launch
- Solid file handling
- Reliability
- Simple, focused editor functionality

### Immediacy

- Opens instantly
- Document-based interaction
- Standard macOS conventions

### What Tilde deliberately avoids

The complexity of a full IDE — almost all of it.

---

## 36. Product Identity

**Name**

Tilde

**Symbol**

```text
~
```

In Unix-like systems, the tilde represents the home directory.

```text
~
~/Documents
~/Desktop
```

It is familiar to developers while appearing as a simple symbol to everyone else.

It also fits the character of the app.

> A small, comfortable place to briefly open the file you need.

---

## 37. One-Sentence Definition

> **Tilde is a tiny, beautiful text editor for macOS.**

In more product-oriented language:

> **A quiet place for plain text.**

Or:

> **Just open the file.**

---

## 38. North Star

Tilde's success is not measured by its number of features.

When a user double-clicks an `.md` file in Finder, the goal is to make them feel:

> **“Ah, this is all I needed.”**

Tilde should not be an app where users spend all day.

It should be **the app they can open without thinking whenever they need it**.
