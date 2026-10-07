// CLI test runner for MarkdownRenderer: render markdown, assert attributes.

import AppKit

var passed = 0
var failed = 0

func expect(_ condition: Bool, _ name: String) {
    if condition { passed += 1; print("  ok  \(name)") }
    else { failed += 1; print("FAIL  \(name)") }
}

let renderer = MarkdownRenderer()

func render(_ md: String) -> NSAttributedString { renderer.render(md) }

func font(_ s: NSAttributedString, at i: Int) -> NSFont? {
    s.attribute(.font, at: i, effectiveRange: nil) as? NSFont
}
func color(_ s: NSAttributedString, at i: Int) -> NSColor? {
    s.attribute(.foregroundColor, at: i, effectiveRange: nil) as? NSColor
}
func background(_ s: NSAttributedString, at i: Int) -> NSColor? {
    s.attribute(.backgroundColor, at: i, effectiveRange: nil) as? NSColor
}
func paragraphStyle(_ s: NSAttributedString, at i: Int) -> NSParagraphStyle? {
    s.attribute(.paragraphStyle, at: i, effectiveRange: nil) as? NSParagraphStyle
}
func isBold(_ f: NSFont?) -> Bool { f?.fontDescriptor.symbolicTraits.contains(.bold) ?? false }
func isItalic(_ f: NSFont?) -> Bool { f?.fontDescriptor.symbolicTraits.contains(.italic) ?? false }
func isMono(_ f: NSFont?) -> Bool { f?.fontDescriptor.symbolicTraits.contains(.monoSpace) ?? false }
func offset(of needle: String, in s: NSAttributedString) -> Int {
    (s.string as NSString).range(of: needle).location
}

// MARK: - Headings

do {
    let s = render("# Title\n\nbody text\n")
    let titleAt = offset(of: "Title", in: s)
    let bodyAt = offset(of: "body", in: s)
    expect(font(s, at: titleAt)?.pointSize == EditorTheme.headingFont(level: 1, size: 14).pointSize, "h1 sized")
    expect(isBold(font(s, at: titleAt)), "h1 bold")
    expect(font(s, at: bodyAt)?.pointSize == 14, "body after heading is body size")
    expect(!s.string.contains("#"), "heading marker removed in preview")
}

do {
    let s = render("### Small\n")
    let at = offset(of: "Small", in: s)
    expect(font(s, at: at)?.pointSize == EditorTheme.headingFont(level: 3, size: 14).pointSize, "h3 sized")
}

// MARK: - Inline styles

do {
    let s = render("normal **bold** and *italic* and `code` and ~~gone~~\n")
    expect(isBold(font(s, at: offset(of: "bold", in: s))), "bold run is bold")
    expect(isItalic(font(s, at: offset(of: "italic", in: s))), "italic run is italic")
    expect(isMono(font(s, at: offset(of: "code", in: s))), "code run is monospaced")
    expect(background(s, at: offset(of: "code", in: s)) != nil, "inline code has background")
    let goneAt = offset(of: "gone", in: s)
    expect((s.attribute(.strikethroughStyle, at: goneAt, effectiveRange: nil) as? Int) == NSUnderlineStyle.single.rawValue, "strikethrough applied")
    expect(!isBold(font(s, at: offset(of: "normal", in: s))), "plain run stays regular")
    expect(!s.string.contains("**") && !s.string.contains("~~"), "inline markers removed")
}

// MARK: - Links

do {
    let s = render("see [the docs](https://example.com) now\n")
    let at = offset(of: "the docs", in: s)
    expect(color(s, at: at) == EditorTheme.linkColor, "link text tinted")
    // Reader's text view adds only the pointing hand, so the underline
    // lives in the text itself.
    expect(s.attribute(.underlineStyle, at: at, effectiveRange: nil) as? Int == NSUnderlineStyle.single.rawValue, "link text underlined")
    expect((s.attribute(.link, at: at, effectiveRange: nil) as? URL)?.absoluteString == "https://example.com", "link URL attached")
    expect(!s.string.contains("https://"), "link URL hidden in preview")
}

// MARK: - Relative link resolution (2026-08 app review P2)

func link(_ s: NSAttributedString, at i: Int) -> URL? {
    s.attribute(.link, at: i, effectiveRange: nil) as? URL
}

do {
    let base = URL(fileURLWithPath: "/tmp/docs", isDirectory: true)
    let r = MarkdownRenderer(baseURL: base)
    let s = r.render("""
        [sibling](README.ko.md) [sub](guides/setup.md) [up](../LICENSE) \
        [frag](#section-title) [both](other.md#part) [web](https://example.com/x)
        """)

    let sibling = link(s, at: offset(of: "sibling", in: s))
    expect(sibling?.isFileURL == true && sibling?.path == "/tmp/docs/README.ko.md",
           "relative link resolved against the document directory")

    let sub = link(s, at: offset(of: "sub", in: s))
    expect(sub?.path == "/tmp/docs/guides/setup.md", "subdirectory link resolved")

    let up = link(s, at: offset(of: "up", in: s))
    expect(up?.path == "/tmp/LICENSE", "../ link collapsed to the parent directory")

    let frag = link(s, at: offset(of: "frag", in: s))
    expect(frag?.scheme == nil && frag?.fragment == "section-title" && frag?.relativePath.isEmpty == true,
           "fragment-only link kept for in-document navigation")

    let both = link(s, at: offset(of: "both", in: s))
    expect(both?.isFileURL == true && both?.path == "/tmp/docs/other.md" && both?.fragment == "part",
           "file link keeps its fragment")

    let web = link(s, at: offset(of: "web", in: s))
    expect(web?.absoluteString == "https://example.com/x", "absolute link passes through unchanged")
}

do {
    // Untitled document (no baseURL): a relative link can't resolve — it
    // must pass through unchanged rather than crash or invent a path.
    let s = render("[rel](notes.md)\n")
    let rel = link(s, at: offset(of: "rel", in: s))
    expect(rel != nil && rel?.scheme == nil, "relative link without baseURL left as-is")
}

// MARK: - Heading anchors for #fragment jumps

do {
    let s = render("# Section Title\n\nbody\n\n## Section Title\n\n### 한글 제목!\n")
    func anchor(at i: Int) -> String? {
        s.attribute(MarkdownRenderer.headingAnchorKey, at: i, effectiveRange: nil) as? String
    }
    let first = offset(of: "Section Title", in: s)
    expect(anchor(at: first) == "section-title", "heading tagged with its anchor slug")
    let second = (s.string as NSString).range(of: "Section Title", options: .backwards).location
    expect(anchor(at: second) == "section-title-1", "duplicate heading slug disambiguated")
    let korean = offset(of: "한글 제목!", in: s)
    expect(anchor(at: korean) == "한글-제목", "korean heading slug keeps letters, drops punctuation")
    expect(anchor(at: offset(of: "body", in: s)) == nil, "body text carries no anchor")
    expect(MarkdownLink.anchorSlug(for: "Hello, World!") == "hello-world", "slug drops punctuation")
    expect(MarkdownLink.anchorSlug(for: "already-a-slug") == "already-a-slug", "slugging is idempotent")
}

do {
    // A suffixed slug must not collide with a heading that slugs to the
    // same text naturally: "Foo", "Foo", "Foo 1" must all stay unique.
    let s = render("# Foo\n\n# Foo\n\n# Foo 1\n")
    var slugs: [String] = []
    s.enumerateAttribute(MarkdownRenderer.headingAnchorKey, in: NSRange(location: 0, length: s.length)) { v, _, _ in
        if let slug = v as? String { slugs.append(slug) }
    }
    expect(slugs.count == 3 && Set(slugs).count == 3, "anchor slugs stay unique against natural collisions")
    expect(slugs.first == "foo", "first heading keeps the bare slug")
}

// MARK: - Lists

do {
    let s = render("- alpha\n- beta\n")
    expect(s.string.contains("•\t"), "unordered bullet inserted")
    let alphaAt = offset(of: "alpha", in: s)
    let ps = paragraphStyle(s, at: alphaAt)
    expect(ps != nil && ps!.headIndent > 0, "list item is indented")
}

do {
    let s = render("1. first\n2. second\n")
    expect(s.string.contains("1.\t") && s.string.contains("2.\t"), "ordered markers with ordinals")
}

do {
    let s = render("- top\n  1. nested\n")
    let nestedAt = offset(of: "nested", in: s)
    let topAt = offset(of: "top", in: s)
    let nestedPS = paragraphStyle(s, at: nestedAt)
    let topPS = paragraphStyle(s, at: topAt)
    expect(nestedPS != nil && topPS != nil && nestedPS!.headIndent > topPS!.headIndent, "nested list indented deeper")
    expect(s.string.contains("1.\t"), "nested ordered marker present")
}

// MARK: - Task lists (heyeuca/Tilde#12)

/// "Done" / "Not done" for a checkbox attachment, nil for anything else.
func checkbox(_ s: NSAttributedString, at i: Int) -> String? {
    (s.attribute(.attachment, at: i, effectiveRange: nil) as? NSTextAttachment)?.image?.accessibilityDescription
}
/// Where the rendered line holding `needle` starts — its marker.
func lineStart(of needle: String, in s: NSAttributedString) -> Int {
    (s.string as NSString).lineRange(for: NSRange(location: offset(of: needle, in: s), length: 0)).location
}
func hasCheckbox(_ s: NSAttributedString) -> Bool {
    (0..<s.length).contains { checkbox(s, at: $0) != nil }
}

do {
    let s = render("- [ ] Write the spec\n- [x] Ship it\n- [X] Tag it\n- plain\n")
    expect(s.string == "\u{FFFC}\tWrite the spec\n\u{FFFC}\tShip it\n\u{FFFC}\tTag it\n•\tplain\n", "task items: a checkbox in place of the bullet, before the same tab (\(s.string.debugDescription))")
    expect(checkbox(s, at: lineStart(of: "Write", in: s)) == "Not done", "task: open item shows an empty box")
    expect(checkbox(s, at: lineStart(of: "Ship", in: s)) == "Done", "task: [x] shows a checked box")
    expect(checkbox(s, at: lineStart(of: "Tag", in: s)) == "Done", "task: [X] shows a checked box")
    expect(color(s, at: offset(of: "Write", in: s)) == NSColor.textColor, "task: open item text at full ink")
    expect(color(s, at: offset(of: "Ship", in: s)) == EditorTheme.quoteColor, "task: done item text in quote color")
    expect(s.attribute(.strikethroughStyle, at: offset(of: "Ship", in: s), effectiveRange: nil) == nil, "task: done item not struck through")
    let task = paragraphStyle(s, at: offset(of: "Write", in: s))
    let bullet = paragraphStyle(s, at: offset(of: "plain", in: s))
    expect(task?.headIndent == bullet?.headIndent && task?.tabStops == bullet?.tabStops, "task: item keeps the bullet's hanging indent")
}

do {
    let s = render("1. [ ] first\n2. [x] second\n")
    expect(s.string == "\u{FFFC}\tfirst\n\u{FFFC}\tsecond\n", "task: ordered items swap the number for the box (\(s.string.debugDescription))")
    expect(checkbox(s, at: lineStart(of: "second", in: s)) == "Done", "task: ordered done item checked")

    let nested = render("- [ ] top\n  - [x] nested\n    1. [ ] deeper\n")
    expect(checkbox(nested, at: lineStart(of: "top", in: nested)) == "Not done"
        && checkbox(nested, at: lineStart(of: "nested", in: nested)) == "Done"
        && checkbox(nested, at: lineStart(of: "deeper", in: nested)) == "Not done", "task: boxes at every nesting depth")
    let top = paragraphStyle(nested, at: offset(of: "top", in: nested))?.headIndent ?? 0
    let deeper = paragraphStyle(nested, at: offset(of: "deeper", in: nested))?.headIndent ?? 0
    expect(deeper > top, "task: nested items indent deeper")
    expect(color(nested, at: offset(of: "top", in: nested)) == NSColor.textColor, "task: an open parent stays at full ink under a done child")

    let quoted = render("> - [x] in a quote\n")
    expect(checkbox(quoted, at: lineStart(of: "in a quote", in: quoted)) == "Done", "task: a list inside a quote still gets boxes")
}

do {
    // The text after the box keeps its inline styles; a done item's links
    // keep their color so they still read as links.
    let s = render("- [x] **bold** and [docs](https://example.com)\n- [ ]   spaced out\n")
    let boldAt = offset(of: "bold", in: s)
    expect(isBold(font(s, at: boldAt)) && color(s, at: boldAt) == EditorTheme.quoteColor, "task: bold in a done item stays bold, quiet")
    expect(color(s, at: offset(of: "docs", in: s)) == EditorTheme.linkColor, "task: a done item's link keeps the link color")
    expect(s.string.contains("\u{FFFC}\tspaced out"), "task: extra spaces after the box don't indent the text")
}

do {
    // Only an exact `[ ] ` / `[x] ` / `[X] ` opening a list item's first
    // paragraph is a box; everything else stays text.
    let s = render("- [link](https://example.com) item\n- [ x] spaced\n- [] empty\n- [x]tight\n- `[ ]` code\n- [ ]\n")
    expect(!hasCheckbox(s), "task: near-misses get no box")
    expect(s.string == "•\tlink item\n•\t[ x] spaced\n•\t[] empty\n•\t[x]tight\n•\t[ ] code\n•\t[ ]\n", "task: near-misses keep their bullets and text (\(s.string.debugDescription))")
    expect(color(s, at: offset(of: "link", in: s)) == EditorTheme.linkColor, "task: - [link](url) is still a link")

    let second = render("- [ ] first paragraph\n\n  [ ] second paragraph\n")
    expect(second.string.contains("[ ] second paragraph"), "task: an item's later paragraph keeps its brackets")
    let plain = render("[ ] not in a list\n\n- > [ ] quoted in an item\n")
    expect(!hasCheckbox(plain) && plain.string.contains("[ ] not in a list") && plain.string.contains("[ ] quoted"), "task: brackets outside a list item's own paragraph stay text")
}

do {
    // The box leaves the line exactly as tall as a bullet's, at any size,
    // and at large sizes stays inside the marker column.
    func firstLineHeight(_ s: NSAttributedString) -> CGFloat {
        let storage = NSTextStorage(attributedString: s)
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: 600, height: 10_000))
        layout.addTextContainer(container)
        layout.ensureLayout(for: container)
        return layout.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil).height
    }
    for size: CGFloat in [9, 14, 24, 36] {
        let r = MarkdownRenderer(fontSize: size)
        let task = r.render("- [x] item\n")
        expect(firstLineHeight(task) == firstLineHeight(r.render("- item\n")), "task: line as tall as a bullet's at \(Int(size)) pt")
        let box = (task.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment)?.bounds.width ?? .infinity
        let tab = paragraphStyle(task, at: 0)?.tabStops.first?.location ?? 0
        expect(box < tab, "task: box fits before the tab stop at \(Int(size)) pt (\(box) < \(tab))")
    }
}

// MARK: - Blockquote

do {
    let s = render("> quoted line\n")
    let at = offset(of: "quoted", in: s)
    expect(color(s, at: at) == NSColor.textColor, "quote text keeps full ink")
    let ps = paragraphStyle(s, at: at)
    expect(ps?.textBlocks.isEmpty == false, "quote has a bar text block")
    expect(!s.string.contains(">"), "quote marker removed")
}

// Blocks following a quote or code listing get leading spacing (their own
// paragraphSpacing is swallowed by the NSTextBlock layout).
do {
    let s = render("> quoted\n\nafter quote\n\n```\ncode\n```\n\nafter code\n")
    let afterQuote = paragraphStyle(s, at: offset(of: "after quote", in: s))
    expect((afterQuote?.paragraphSpacingBefore ?? 0) > 0, "paragraph after quote gets leading spacing")
    let afterCode = paragraphStyle(s, at: offset(of: "after code", in: s))
    expect((afterCode?.paragraphSpacingBefore ?? 0) > 0, "paragraph after code gets leading spacing")
    let inCode = offset(of: "code", in: s)
    expect(s.attribute(EditorTheme.codeBlockMarker, at: inCode, effectiveRange: nil) != nil,
           "code listing tagged for the rounded band")
}

// Two adjacent text blocks (quote→code, code→quote) get a real spacer
// paragraph — leading spacing is absorbed INSIDE a text block, so the beat
// needs an actual (invisible, one-beat-tall) paragraph between them.
do {
    let s = render("> quoted\n\n```\ncode\n```\n\n> second quote\n")
    expect(s.string.contains("quoted\n\ncode"), "spacer between quote and code")
    expect(s.string.contains("code\n\nsecond"), "spacer between code and quote")
    // Normal paragraph flow stays spacer-free.
    let p = render("one\n\ntwo\n")
    expect(!p.string.contains("one\n\ntwo"), "no spacer between plain paragraphs")
}

// MARK: - Code block

do {
    let s = render("intro\n\n```swift\nlet x = 1\nprint(x)\n```\n\noutro\n")
    let codeAt = offset(of: "let x", in: s)
    expect(isMono(font(s, at: codeAt)), "code block is monospaced")
    expect(paragraphStyle(s, at: codeAt)?.textBlocks.first?.backgroundColor == nil, "code block fill left to the view")
    expect(s.attribute(EditorTheme.codeBlockMarker, at: codeAt, effectiveRange: nil) != nil, "code block tagged for the rounded band")
    expect(s.string.contains("let x = 1\nprint(x)"), "code block preserves internal newlines")
    expect(!s.string.contains("```"), "code fence markers removed")
    expect(font(s, at: offset(of: "outro", in: s))?.pointSize == 14, "body resumes after code block")
}

// MARK: - Thematic break

do {
    let s = render("above\n\n---\n\nbelow\n")
    // The break is an attachment; find it.
    var foundAttachment = false
    s.enumerateAttribute(.attachment, in: NSRange(location: 0, length: s.length)) { value, _, _ in
        if value != nil { foundAttachment = true }
    }
    expect(foundAttachment, "thematic break rendered as attachment")
    expect(!s.string.contains("---"), "break markers removed")
}

// MARK: - Frontmatter

func hasAttachment(_ s: NSAttributedString) -> Bool {
    var found = false
    s.enumerateAttribute(.attachment, in: NSRange(location: 0, length: s.length)) { value, _, _ in
        if value != nil { found = true }
    }
    return found
}

/// The unfold links on "more" labels, in order.
func moreLinks(_ s: NSAttributedString) -> [URL] {
    var urls: [URL] = []
    s.enumerateAttribute(.link, in: NSRange(location: 0, length: s.length)) { value, range, _ in
        if let url = value as? URL, (s.string as NSString).substring(with: range) == "more" { urls.append(url) }
    }
    return urls
}

func attachmentCount(_ s: NSAttributedString) -> Int {
    var count = 0
    s.enumerateAttribute(.attachment, in: NSRange(location: 0, length: s.length)) { value, _, _ in
        if value != nil { count += 1 }
    }
    return count
}

do {
    // The frontmatter renders where it stands: `title:` as an H1, the other
    // keys as rows, a rule — then the body as written, its own H1 included.
    let s = render("---\ntitle: Hello\ntags: [a_b]\n---\n# Heading\n\nbody\n")
    expect(s.string.hasPrefix("Hello\ntags\ta_b\n\u{FFFC}\nHeading\nbody"), "frontmatter header: title, rows, rule, then the body's H1 (\(s.string.debugDescription))")
    expect(attachmentCount(s) == 1, "frontmatter header: fences are not thematic breaks; the closing fence dissolves into one rule")
    let keyAt = offset(of: "tags", in: s)
    expect(color(s, at: keyAt) == EditorTheme.quoteColor, "frontmatter header: key in quote color")
    expect(color(s, at: offset(of: "a_b", in: s)) == NSColor.labelColor, "frontmatter header: value in label color")
    expect(font(s, at: keyAt)?.pointSize == EditorTheme.defaultFontSize - 1 && !isMono(font(s, at: keyAt)), "frontmatter header: body face, a point smaller")
    expect(s.attribute(EditorTheme.codeBlockMarker, at: keyAt, effectiveRange: nil) == nil, "frontmatter header: no code-block band")
    expect(paragraphStyle(s, at: 0)?.paragraphSpacingBefore == 0, "frontmatter header: the title opens the page")
    expect(font(s, at: offset(of: "Heading", in: s)) == EditorTheme.headingFont(level: 1, size: EditorTheme.defaultFontSize), "frontmatter header: the body's H1 renders as written")
    let valueColumn = paragraphStyle(s, at: keyAt)?.tabStops.first?.location ?? 0
    expect(valueColumn > 0 && paragraphStyle(s, at: keyAt)?.headIndent == valueColumn, "frontmatter header: wrapped values align under the value column")
}

do {
    let s = render("---\ntitle: My Post\ndate: 2026-09-24\n---\nIntro paragraph.\n")
    expect(s.string == "My Post\ndate\t2026-09-24\n\u{FFFC}\nIntro paragraph.\n", "frontmatter title: rendered as the top H1 (\(s.string.debugDescription))")
    expect(font(s, at: 0) == EditorTheme.headingFont(level: 1, size: EditorTheme.defaultFontSize), "frontmatter title: set as an H1")
    expect(s.attribute(MarkdownRenderer.headingAnchorKey, at: 0, effectiveRange: nil) == nil, "frontmatter title: takes no anchor — it isn't a Markdown heading")
    expect(render("---\ntitle: a *b* [c]\n---\nbody\n").string.hasPrefix("a *b* [c]\n"), "frontmatter title: Markdown characters stay literal")
    expect(render("---\ntitle: Hello\n...\nbody\n").string == "Hello\nbody\n", "frontmatter: `...` closes the block; a lone title needs no rule")
}

do {
    // Both render as written, even when they say the same thing; the body's
    // heading keeps the slug its `#fragment` links expect.
    let s = render("---\ntitle: Release notes\ndate: 2026\n---\n# Release Notes\n\nbody\n")
    expect(s.string.hasPrefix("Release notes\ndate\t2026\n\u{FFFC}\nRelease Notes\nbody"), "frontmatter title: shown even when the body's H1 repeats it (\(s.string.debugDescription))")
    expect(s.attribute(MarkdownRenderer.headingAnchorKey, at: offset(of: "Release Notes", in: s), effectiveRange: nil) as? String == "release-notes", "frontmatter title: the body's H1 keeps its own slug")
}

do {
    let s = render("---\n---\nbody\n")
    expect(s.string.hasPrefix("body") && !hasAttachment(s), "frontmatter: empty block hidden")
    expect(render("---\ntitle:\ntags: []\n---\nbody\n").string == "body\n", "frontmatter: keys without values hidden, no empty header")
}

do {
    let s = render("---\ntitle: Hello\n\nbody\n")
    expect(hasAttachment(s), "frontmatter: no closing fence keeps the thematic break")
    expect(s.string.contains("title: Hello"), "frontmatter: no closing fence keeps the text")
}

do {
    let keys = (1...8).map { "k\($0): v\($0)" }.joined(separator: "\n")
    let s = render("---\n" + keys + "\n---\nbody\n")
    expect(s.string.hasPrefix("k1\tv1\nk2\tv2\nk3\tv3\nk4\tv4\nk5\tv5\n+3 more\n\u{FFFC}\nbody"), "frontmatter header: five rows, then the rest folded (\(s.string.debugDescription))")
    let six = render("---\n" + (1...6).map { "k\($0): v" }.joined(separator: "\n") + "\n---\nbody\n")
    expect(six.string.contains("k6\tv") && !six.string.contains("more"), "frontmatter header: a lone sixth row is shown, not folded")
    let titled = render("---\ntitle: T\n" + (1...6).map { "k\($0): v" }.joined(separator: "\n") + "\n---\nbody\n")
    expect(titled.string.hasPrefix("T\n") && titled.string.contains("k6\tv"), "frontmatter header: a raised title doesn't count as a row")

    // "+N more" is a link Reader handles itself; following it shows every row.
    let moreAt = offset(of: "+3 more", in: s)
    expect(s.attribute(.link, at: moreAt, effectiveRange: nil) as? URL == MarkdownRenderer.MetadataUnfold.rows.link, "frontmatter header: \"+N more\" links to unfolding the rows")
    expect(color(s, at: moreAt) == EditorTheme.quoteColor && s.attribute(.underlineStyle, at: moreAt, effectiveRange: nil) == nil, "frontmatter header: \"+N more\" is as quiet as the keys")
    expect(s.attribute(.link, at: moreAt + 7, effectiveRange: nil) == nil, "frontmatter header: the link stops at the line's end")
    let all = MarkdownRenderer(showsAllMetadataRows: true).render("---\n" + keys + "\n---\nbody\n")
    expect(all.string.hasPrefix("k1\tv1\nk2\tv2\nk3\tv3\nk4\tv4\nk5\tv5\nk6\tv6\nk7\tv7\nk8\tv8\n\u{FFFC}\nbody") && !all.string.contains("more"), "frontmatter header: unfolded, every row shows (\(all.string.debugDescription))")
}

do {
    // A value the key reader can't flatten stays in its row, as written.
    let s = render("---\ntitle: Hello\ncover:\n  image: a.png\n  alt: A cover\n---\n# Heading\n")
    expect(s.string == "Hello\ncover\timage: a.png\nalt: A cover\n\u{FFFC}\nHeading\n", "frontmatter header: nested value kept raw in its row (\(s.string.debugDescription))")
    let rawAt = offset(of: "image: a.png", in: s)
    expect(isMono(font(s, at: rawAt)) && color(s, at: rawAt) == EditorTheme.quoteColor, "frontmatter header: raw value in the code face, quiet")
    let long = render("---\nk:\n" + (1...8).map { "  n\($0): v" }.joined(separator: "\n") + "\n---\n")
    expect(long.string == "k\tn1: v\nn2: v\nn3: v… more\n", "frontmatter header: a raw value shows a few lines at most (\(long.string.debugDescription))")
    // Lines that belong to no key: the whole block, raw, above the content.
    let stray = render("---\n  stray\nk: v\n---\n# Heading\n")
    let at = offset(of: "stray", in: stray)
    expect(at != NSNotFound && isMono(font(stray, at: at)) && stray.string.contains("Heading"), "frontmatter: a block with keyless lines shown as a listing")
    expect(renderer.renderDocument("---\n  stray\nk: v\n---\nbody\n").hiddenLength == 0, "frontmatter: nothing hidden behind a raw listing")
}

do {
    // Long values are cut — three lines or 240 characters — so one
    // description can't fill the screen. A quiet "more" after each cut
    // shows just that value whole; the value itself stays plain text.
    let words = String(repeating: "word ", count: 80)
    let source = "---\ndesc: \(words)\nlines: |\n  one\n  two\n  three\n  four\n  five\n---\nbody\n"
    let s = render(source)
    let descAt = offset(of: "word", in: s)
    let descLine = (s.string as NSString).lineRange(for: NSRange(location: descAt, length: 0))
    let desc = (s.string as NSString).substring(with: NSRange(location: descAt, length: NSMaxRange(descLine) - descAt - 1))
    expect(desc.count <= MarkdownRenderer.metadataValueCharacterLimit + 6 && desc.hasSuffix("word… more"), "frontmatter header: a long value is cut between words, then \"more\" (\(desc.count) chars)")
    expect(s.attribute(.link, at: descAt, effectiveRange: nil) == nil && color(s, at: descAt) == NSColor.labelColor, "frontmatter header: the cut value itself stays plain text")
    expect(moreLinks(s) == [MarkdownRenderer.MetadataUnfold.value(0).link, MarkdownRenderer.MetadataUnfold.value(1).link], "frontmatter header: each \"more\" unfolds its own value")
    let moreAt = offset(of: "word… more", in: s) + 6
    expect(color(s, at: moreAt) == EditorTheme.quoteColor && s.attribute(.underlineStyle, at: moreAt, effectiveRange: nil) == nil, "frontmatter header: \"more\" is as quiet as \"+N more\"")
    expect(s.string.contains("one\ntwo\nthree… more\n") && !s.string.contains("four"), "frontmatter header: a multi-line value is cut to three lines")
    let bodyLineAt = offset(of: "body", in: s)
    expect(s.attribute(.link, at: bodyLineAt, effectiveRange: nil) == nil, "frontmatter header: the body is untouched by the cut links")
    let one = MarkdownRenderer(wholeMetadataValues: [1]).render(source)
    expect(one.string.contains("five") && one.string.contains("word… more") && moreLinks(one) == [MarkdownRenderer.MetadataUnfold.value(0).link], "frontmatter header: unfolding one value leaves the others cut")
    let both = MarkdownRenderer(wholeMetadataValues: [0, 1]).render(source)
    expect(both.string.contains("five") && !both.string.contains("…") && moreLinks(both).isEmpty, "frontmatter header: unfolded values show whole, no \"more\"")
    expect(MarkdownRenderer.cutValue("short") == nil, "frontmatter header: a short value isn't cut")
}

do {
    // Where a cut lands: at a sentence end when one is near the limit (no
    // ellipsis, so "." never runs into "…"), otherwise between words with
    // trailing punctuation dropped before the "…".
    let sentences = String(repeating: "Use this agent when the user asks to review a pull request. ", count: 8)
    let atSentence = MarkdownRenderer.cutValue(sentences) ?? ""
    expect(atSentence.hasSuffix("request.") && !atSentence.contains("…"), "frontmatter cut: ends at a sentence, no ellipsis (\(atSentence.suffix(20).debugDescription))")
    let commas = MarkdownRenderer.cutValue(String(repeating: "alpha, ", count: 60)) ?? ""
    expect(commas.hasSuffix("alpha…"), "frontmatter cut: trailing punctuation dropped before the ellipsis (\(commas.suffix(12).debugDescription))")
    let versions = MarkdownRenderer.cutValue(String(repeating: "see v1.2 and example.com ", count: 20)) ?? ""
    expect(versions.hasSuffix("…") && !versions.hasSuffix(".…"), "frontmatter cut: a dot inside a word isn't a sentence end (\(versions.suffix(16).debugDescription))")
    expect(MarkdownRenderer.cutValue("One.\nTwo.\nThree.\nFour.") == "One.\nTwo.\nThree.", "frontmatter cut: lines cut after a finished sentence need no ellipsis")
    expect(MarkdownRenderer.cutValue("one\ntwo:\nthree,\nfour") == "one\ntwo:\nthree…", "frontmatter cut: a line cut mid-thought gets the ellipsis")
    let cjk = MarkdownRenderer.cutValue(String(repeating: "문장이 끝났습니다。", count: 40)) ?? ""
    expect(cjk.hasSuffix("。") && !cjk.contains("…"), "frontmatter cut: a CJK full stop counts as a sentence end")
}

do {
    // Copying reads right: a multi-line value uses real newlines, its
    // continuation lines are paragraphs indented to the value column, and
    // only a row's last line takes the row spacing.
    let s = render("---\nk: |\n  one\n  two\nm: v\n---\n")
    expect(s.string == "k\tone\ntwo\nm\tv\n", "frontmatter header: multi-line values copy as lines (\(s.string.debugDescription))")
    let first = paragraphStyle(s, at: offset(of: "one", in: s))
    let second = paragraphStyle(s, at: offset(of: "two", in: s))
    expect(first?.paragraphSpacing == 0 && (second?.paragraphSpacing ?? 0) > 0, "frontmatter header: a value's lines sit together; rows are spaced")
    expect((second?.headIndent ?? 0) > 0 && second?.firstLineHeadIndent == second?.headIndent && first?.firstLineHeadIndent == 0, "frontmatter header: continuation lines start at the value column")
    expect(render("---\nk: \"a\\tb\"\n---\n").string == "k\ta b\n", "frontmatter header: tabs in a value become spaces, not tab stops")
}

do {
    // The value column is measured over every row, so unfolding doesn't
    // move it under the rows already on screen.
    let source = "---\n" + ["a: 1", "b: 2", "c: 3", "d: 4", "e: 5", "f: 6", "a-much-longer-key: 7"].joined(separator: "\n") + "\n---\nbody\n"
    let folded = render(source)
    let unfolded = MarkdownRenderer(showsAllMetadataRows: true).render(source)
    let foldedColumn = paragraphStyle(folded, at: 0)?.tabStops.first?.location
    expect(foldedColumn != nil && foldedColumn == paragraphStyle(unfolded, at: 0)?.tabStops.first?.location, "frontmatter header: unfolding keeps the value column")
    expect(!folded.string.contains("a-much-longer-key") && unfolded.string.contains("a-much-longer-key"), "frontmatter header: the long key was folded")
}

do {
    // "+N more" and a cut value unfold independently: showing the rows
    // leaves long values cut, and showing a value leaves the rows folded.
    let long = String(repeating: "long ", count: 70)
    // desc is entry 1 (after title) and the first row; late is entry 8, folded.
    let source = "---\ntitle: T\ndesc: \(long)\n" + (2...7).map { "k\($0): v\($0)" }.joined(separator: "\n") + "\nlate: \(long)\n---\n# Body\n\ntext\n"
    let rows = MarkdownRenderer(showsAllMetadataRows: true).render(source)
    expect(rows.string.contains("late\t") && !rows.string.contains("+3 more") && rows.string.contains("long… more"), "frontmatter header: \"+N more\" shows the rows, their long values still cut")
    let value = MarkdownRenderer(wholeMetadataValues: [1]).render(source)
    expect(value.string.contains("+3 more") && !value.string.contains("late\t"), "frontmatter header: a cut value unfolds without the folded rows")
    expect(!(value.string.components(separatedBy: "\n").first { $0.hasPrefix("desc\t") } ?? "").contains("…"), "frontmatter header: the clicked value shows whole")
    expect(MarkdownRenderer.MetadataUnfold(link: MarkdownRenderer.MetadataUnfold.value(8).link) == .value(8)
        && MarkdownRenderer.MetadataUnfold(link: MarkdownRenderer.MetadataUnfold.rows.link) == .rows
        && MarkdownRenderer.MetadataUnfold(link: URL(string: "https://example.com")!) == nil, "frontmatter header: unfold links round-trip, others don't match")
}

do {
    // Reader unfolds by splicing a rebuilt header over the first
    // prefixLength characters — the result must match a render made in
    // that state from the start, for rows and for a value.
    let long = String(repeating: "long ", count: 70)
    let source = "---\ntitle: T\n" + (1...8).map { "k\($0): v\($0)" }.joined(separator: "\n") + "\ndesc: \(long)\n---\n# Body\n\ntext\n"
    let folded = renderer.renderDocument(source)
    for state in [MarkdownRenderer(showsAllMetadataRows: true), MarkdownRenderer(showsAllMetadataRows: true, wholeMetadataValues: [9])] {
        let header = state.metadataHeader(folded.metadata, followedByBody: folded.bodyFollows)
        let spliced = NSMutableAttributedString(attributedString: folded.text)
        spliced.replaceCharacters(in: NSRange(location: 0, length: folded.prefixLength), with: header)
        let full = state.renderDocument(source)
        expect(spliced.string == full.text.string && header.length == full.prefixLength, "frontmatter header: unfolding in place matches a render in that state (values \(state.wholeMetadataValues.sorted()))")
    }
    expect(folded.bodyFollows && !renderer.renderDocument("---\nk: v\n---\n").bodyFollows, "frontmatter header: rendering reports whether a body follows")
}

do {
    func near(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.0001 }
    // A 13-character block becomes the 6-character header "k\tv\n" + rule;
    // the 13-character body renders as itself.
    let source = "---\nk: v\n---\n" + String(repeating: "b", count: 12) + "\n"
    let rendering = renderer.renderDocument(source)
    let length = (source as NSString).length
    expect(rendering.hiddenLength == 13 && rendering.prefixLength == 6, "frontmatter: rendering reports hidden block and header lengths (\(rendering.hiddenLength), \(rendering.prefixLength))")
    expect(rendering.renderedFraction(forSourceFraction: 0.25, sourceLength: length) == 0, "frontmatter: a position inside the metadata opens at the top, header in view")
    expect(rendering.renderedFraction(forSourceFraction: 0, sourceLength: length) == 0, "frontmatter: the top stays the top")
    let middle = rendering.renderedFraction(forSourceFraction: 0.75, sourceLength: length)
    expect(near(middle, 12.5 / 19), "frontmatter: a body position maps past the header (\(middle))")
    // A raised title counts as header too: "T\n" before a 17-character body.
    let titled = renderer.renderDocument("---\ntitle: T\n---\n" + String(repeating: "b", count: 16) + "\n")
    expect(titled.prefixLength == 2 && near(titled.renderedFraction(forSourceFraction: 0.75, sourceLength: 34), 10.5 / 19), "frontmatter: a raised title maps like the header")
    let plain = renderer.renderDocument("---\n---\n" + String(repeating: "b", count: 7) + "\n")
    expect(near(plain.renderedFraction(forSourceFraction: 0.75, sourceLength: 16), 0.5), "frontmatter: hidden block without a header shifts onto the body")
    expect(renderer.renderDocument("no frontmatter\n").renderedFraction(forSourceFraction: 0.3, sourceLength: 15) == 0.3, "frontmatter: fraction unchanged without a block")
}

// heyeuca/Tilde#10 review: rule-delimited prose must not vanish, and a
// document that is only metadata must not render as a blank page.
do {
    let s = render("---\n\n# Chapter One\n\nIt began quietly.\n\n---\n\n# Chapter Two\n\nThen it did not.\n")
    var rules = 0
    s.enumerateAttribute(.attachment, in: NSRange(location: 0, length: s.length)) { value, _, _ in
        if value != nil { rules += 1 }
    }
    expect(s.string.contains("Chapter One") && s.string.contains("It began quietly."), "frontmatter: chapters between rules stay visible")
    expect(rules == 2, "frontmatter: both rules still render (\(rules))")
}

do {
    let s = render("---\n\nShe paused.\n\n...\n\nAnd then she spoke.\n")
    expect(s.string.contains("She paused.") && s.string.contains("And then she spoke."), "frontmatter: prose before `...` stays visible")
}

do {
    let s = render("---\nname: my-skill\ndescription: Does a thing\n---\n")
    expect(s.string == "name\tmy-skill\ndescription\tDoes a thing\n", "frontmatter-only: the header is the page, no trailing rule (\(s.string.debugDescription))")
    expect(render("---\nk: v\n---\n\n  \n").string == "k\tv\n", "frontmatter-only: trailing blank lines still count as empty")
    expect(render("---\ntitle: Only a title\n---\n").string == "Only a title\n", "frontmatter-only: a lone title becomes the H1")
    let raw = render("---\nk:\n  nested: v\n---\n")
    expect(raw.string == "k\tnested: v\n" && isMono(font(raw, at: offset(of: "nested", in: raw))), "frontmatter-only: an unreadable value stays in its row")
    expect(render("---\nk: |\n  ```\n---\n").string.contains("k\t```"), "frontmatter-only: backticks in a value render as text")
}

do {
    let s = render("intro\n\n---\n\ntitle: Hello\n\n---\n\nbody\n")
    expect(s.string.contains("title: Hello") && hasAttachment(s), "frontmatter: `---` not on line 1 is a thematic break")
}

// MARK: - Frontmatter entries (metadata header)

func entries(_ source: String) -> [MarkdownFrontmatter.Entry]? {
    let ns = source as NSString
    guard let block = MarkdownFrontmatter.range(in: ns) else { return nil }
    return MarkdownFrontmatter.entries(in: ns, block: block)
}
func pairs(_ source: String) -> [String]? {
    entries(source)?.map { "\($0.key)=\($0.value)" }
}

do {
    expect(pairs("---\ntitle: Hello world\ndate: 2026-09-24\ndraft: false\n---\n") == ["title=Hello world", "date=2026-09-24", "draft=false"], "entries: plain scalars in order")
    expect(pairs("---\ntitle: \"Quoted: yes\"\nsub: 'it''s'\nesc: \"a \\\"b\\\" c\"\n---\n") == ["title=Quoted: yes", "sub=it's", "esc=a \"b\" c"], "entries: quoted scalars unescaped")
    expect(pairs("---\n\"publish date\": 2026-09-24\n'draft': no\n---\n") == ["publish date=2026-09-24", "draft=no"], "entries: quoted keys")
    expect(pairs("---\n# a comment\ntitle: Hi # trailing\nurl: https://x.com/#frag\n\n---\n") == ["title=Hi", "url=https://x.com/#frag"], "entries: comments dropped, `#` inside a value kept")
    expect(pairs("---\ntags: [a, \"b, c\", 'd']\nnone: []\n---\n") == ["tags=a, b, c, d"], "entries: flow list joined; empty list left out")
    expect(pairs("---\ntags:\n  - one\n  - \"two\"\naliases:\n- three\n---\n") == ["tags=one, two", "aliases=three"], "entries: block lists, indented or at the key's column")
    expect(pairs("---\ndesc: |\n  line one\n  line two\n\nnext: v\n---\n") == ["desc=line one\nline two", "next=v"], "entries: literal block keeps line breaks")
    expect(pairs("---\ndesc: >-\n  folded\n  text\n\n  second\n---\n") == ["desc=folded text\nsecond", ], "entries: folded block joins lines, blank line breaks")
    expect(pairs("---\ndesc: starts here\n  and continues\nk: v\n---\n") == ["desc=starts here and continues", "k=v"], "entries: multi-line plain scalar folded")
    expect(pairs("---\ndesc:\n  on the next line\n---\n") == ["desc=on the next line"], "entries: plain scalar starting below the key")
    expect(pairs("---\ntitle:\nempty: ''\nk: v\n---\n") == ["k=v"], "entries: keys without values left out")
    expect(pairs("---\n제목: 안녕\n---\n") == ["제목=안녕"], "entries: non-ASCII keys")
    expect(pairs("---\n---\n") == [], "entries: empty block has no entries")
}

do {
    func rawPairs(_ source: String) -> [String]? {
        entries(source)?.map { "\($0.key)=\($0.value)" + ($0.isRaw ? " [raw]" : "") }
    }
    expect(rawPairs("---\ntitle: x\ncover:\n  image: a.png\n  alt: A\n---\n") == ["title=x", "cover=image: a.png\nalt: A [raw]"], "entries: a nested mapping stays raw; other keys still read")
    expect(rawPairs("---\nitems:\n  - name: a\n---\n") == ["items=- name: a [raw]"], "entries: a list of mappings stays raw")
    expect(rawPairs("---\nitems:\n  - a\n    - b\n---\n") == ["items=- a\n  - b [raw]"], "entries: a nested list stays raw")
    expect(rawPairs("---\nk: {a: 1}\n---\n") == ["k={a: 1} [raw]"], "entries: a flow mapping stays raw")
    expect(rawPairs("---\nk: [a, [b]]\n---\n") == ["k=[a, [b]] [raw]"], "entries: a nested flow list stays raw")
    expect(rawPairs("---\nk: [a,\n  b]\n---\n") == ["k=[a,\nb] [raw]"], "entries: a multi-line flow list stays raw")
    expect(rawPairs("---\nbase: &b 1\nother: *b\n---\n") == ["base=&b 1 [raw]", "other=*b [raw]"], "entries: anchors and aliases stay raw")
    expect(rawPairs("---\nk: !!str 1\n---\n") == ["k=!!str 1 [raw]"], "entries: tags stay raw")
    expect(rawPairs("---\nk: \"open\n  more\"\n---\n") == ["k=\"open\nmore\" [raw]"], "entries: a multi-line quoted scalar stays raw")
    expect(rawPairs("---\nk: v\n- stray\n---\n") == ["k=v\n- stray [raw]"], "entries: a list item after a scalar stays raw")
    expect(rawPairs("---\nk: v\n  just text\n---\n") == ["k=v just text"], "entries: indented text after a scalar continues it")
    expect(entries("---\n  stray\nk: v\n---\n") == nil, "entries: a line before any key belongs to no key")
}

// MARK: - Tables

func textBlocks(_ s: NSAttributedString, at i: Int) -> [NSTextBlock] {
    (s.attribute(.paragraphStyle, at: i, effectiveRange: nil) as? NSParagraphStyle)?.textBlocks ?? []
}
func alignment(_ s: NSAttributedString, at i: Int) -> NSTextAlignment? {
    (s.attribute(.paragraphStyle, at: i, effectiveRange: nil) as? NSParagraphStyle)?.alignment
}

do {
    let s = render("| Left | Right |\n| :--- | ---: |\n| a | b |\n| c | d |\n")
    let headerAt = offset(of: "Left", in: s)
    let cellAt = offset(of: "a", in: s)
    expect(!textBlocks(s, at: headerAt).isEmpty, "table header cell has a text block")
    expect(!textBlocks(s, at: cellAt).isEmpty, "table body cell has a text block")
    expect(isBold(font(s, at: headerAt)), "table header cell is bold")
    expect(!isBold(font(s, at: cellAt)), "table body cell is not bold")
    // Right column alignment (column index 1).
    let rightAt = offset(of: "Right", in: s)
    expect(alignment(s, at: rightAt) == .right, "right-aligned column honored")
    expect(alignment(s, at: headerAt) == .left, "left-aligned column honored")
    expect(!s.string.contains("|"), "table pipes removed in preview")
    // All four data cells present.
    expect(["a","b","c","d"].allSatisfy { s.string.contains($0) }, "all table cells rendered")
}

do {
    // A table followed by a paragraph must not swallow the paragraph.
    let s = render("| H |\n| --- |\n| x |\n\nafter table\n")
    let afterAt = offset(of: "after table", in: s)
    expect(textBlocks(s, at: afterAt).isEmpty, "paragraph after table is not in a table block")
    expect(font(s, at: afterAt)?.pointSize == 14, "paragraph after table is body text")
}

// MARK: - Images

func attachment(_ s: NSAttributedString, at i: Int) -> NSTextAttachment? {
    s.attribute(.attachment, at: i, effectiveRange: nil) as? NSTextAttachment
}

do {
    // Remote image: never fetched, alt text shown as a link.
    let s = render("![a remote pic](https://example.com/x.png)\n")
    let at = offset(of: "a remote pic", in: s)
    expect(color(s, at: at) == EditorTheme.linkColor, "remote image alt tinted as link")
    expect(s.attribute(.underlineStyle, at: at, effectiveRange: nil) as? Int == NSUnderlineStyle.single.rawValue, "remote image alt underlined as link")
    expect((s.attribute(.link, at: at, effectiveRange: nil) as? URL)?.host == "example.com", "remote image link retained")
    var hasAttachment = false
    s.enumerateAttribute(.attachment, in: NSRange(location: 0, length: s.length)) { v, _, _ in if v != nil { hasAttachment = true } }
    expect(!hasAttachment, "remote image not loaded as attachment")
}

do {
    // Missing local image: quiet placeholder with alt text.
    let s = render("![my diagram](nope/missing.png)\n")
    let at = offset(of: "my diagram", in: s)
    expect(color(s, at: at) == EditorTheme.quoteColor, "missing local image shows quiet placeholder")
    expect(s.string.contains("my diagram"), "placeholder includes alt text")
}

do {
    // Empty alt text: the parser hands over U+FFFC, which must not leak
    // into the placeholder — the generic "(image)" label shows instead.
    let s = render("![](nope/missing.png)\n")
    expect(!s.string.contains("\u{FFFC}"), "empty-alt placeholder has no object-replacement character")
    expect(s.string.contains("(image)"), "empty-alt placeholder falls back to the generic label")
    let remote = render("![](https://example.com/pic.png)\n")
    expect(remote.string.contains("https://example.com/pic.png"), "empty-alt remote image falls back to its URL")
}

do {
    // Real local image resolved against baseURL → attachment.
    let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("tilde-img-\(getpid())")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let imgURL = dir.appendingPathComponent("pic.png")
    let img = NSImage(size: NSSize(width: 40, height: 20))
    img.lockFocus(); NSColor.systemBlue.setFill(); NSRect(x: 0, y: 0, width: 40, height: 20).fill(); img.unlockFocus()
    let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
    try? rep.representation(using: .png, properties: [:])!.write(to: imgURL)

    let localRenderer = MarkdownRenderer(baseURL: dir)
    let s = localRenderer.render("![pic](pic.png)\n")
    var found: NSTextAttachment?
    s.enumerateAttribute(.attachment, in: NSRange(location: 0, length: s.length)) { v, _, _ in
        if let a = v as? NSTextAttachment { found = a }
    }
    expect(found?.image != nil, "local image loaded as attachment")
    expect((found?.bounds.width ?? 0) > 0, "attachment has non-zero width")
    try? FileManager.default.removeItem(at: dir)
}

// MARK: - Robustness

do {
    let s = render("")
    expect(s.length == 0, "empty input renders empty")
}
do {
    // Malformed / partial markdown must not crash and must produce text.
    let s = render("# unterminated **bold and [broken](\n\n```\nno close")
    expect(s.length > 0, "malformed markdown still renders")
}
do {
    let s = render("plain text no markdown at all\n")
    expect(font(s, at: 0)?.pointSize == 14, "plain paragraph is body font")
}

// MARK: - Performance: Reader entry cost at the sync-render threshold

do {
    // ReaderView renders documents up to 256 KB synchronously on entry
    // (larger ones go to a background queue), and renders exactly ONCE per
    // entry. This pins the entry cost at that threshold with a generous
    // bound — a reintroduced double render or a parser-walk regression
    // roughly doubles the time and trips it.
    let piece = """
        ## Section heading

        A paragraph with **bold**, *italic*, `code`, and [a link](https://example.com).

        - list item one
        - list item two

        ```swift
        let value = compute(42)
        ```

        > a quoted line

        """
    var md = ""
    while md.utf8.count < 256 * 1024 { md += piece }
    let start = Date()
    let out = renderer.render(md)
    let elapsed = Date().timeIntervalSince(start)
    expect(out.length > 0, "256 KB document renders")
    expect(elapsed < 3.0, "256 KB render in \(String(format: "%.2f", elapsed))s (< 3s sync-entry bound)")
}

// MARK: - Fuzz: renderer must never crash

do {
    var seed: UInt64 = 0xF022
    func rand(_ n: Int) -> Int {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return Int((seed >> 33) % UInt64(n))
    }
    let pieces = ["# ", "## ", "- ", "1. ", "> ", "```", "**", "*", "`", "~~",
                  "[", "](", ")", "![", "|", "---", "\n", "\n\n", "text ", "\t",
                  "http://x.y/z", "café ☕ 日本語 ", "  ", "\\", "<div>"]
    var crashes = 0
    for i in 0..<500 {
        var md = ""
        let parts = 3 + rand(40)
        for _ in 0..<parts { md += pieces[rand(pieces.count)] }
        // Occasionally inject raw random bytes as scalars.
        if rand(4) == 0 { md += String(UnicodeScalar(0x20 + rand(0x2000)) ?? " ") }
        let out = renderer.render(md)
        // Any non-crashing result (including empty) is acceptable.
        if out.length < 0 { crashes += 1 }
        _ = i
    }
    expect(crashes == 0, "fuzz: 500 random/malformed inputs render without crashing")
}

print("\n\(passed) passed, \(failed) failed")
exit(failed == 0 ? 0 : 1)
