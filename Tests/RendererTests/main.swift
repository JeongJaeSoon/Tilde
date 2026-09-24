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
    expect(MarkdownRenderer.anchorSlug(for: "Hello, World!") == "hello-world", "slug drops punctuation")
    expect(MarkdownRenderer.anchorSlug(for: "already-a-slug") == "already-a-slug", "slugging is idempotent")
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

do {
    let s = render("---\ntitle: Hello\ntags: [a_b]\n---\n# Heading\n\nbody\n")
    expect(!s.string.contains("title"), "frontmatter: metadata hidden")
    expect(!hasAttachment(s), "frontmatter: fences are not thematic breaks")
    expect(s.string.hasPrefix("Heading"), "frontmatter: document starts at the real content")
    expect(paragraphStyle(s, at: 0)?.paragraphSpacingBefore == 0, "frontmatter: first real block gets no leading space")
}

do {
    let s = render("---\ntitle: Hello\n...\nbody\n")
    expect(!s.string.contains("title") && s.string.hasPrefix("body"), "frontmatter: `...` closes the block")
}

do {
    let s = render("---\n---\nbody\n")
    expect(s.string.hasPrefix("body") && !hasAttachment(s), "frontmatter: empty block hidden")
}

do {
    let s = render("---\ntitle: Hello\n\nbody\n")
    expect(hasAttachment(s), "frontmatter: no closing fence keeps the thematic break")
    expect(s.string.contains("title: Hello"), "frontmatter: no closing fence keeps the text")
}

do {
    // 20-character block + 20-character body: the editor's fraction of the
    // whole source maps onto the body alone.
    let source = "---\ntitle: 1234\n---\n" + String(repeating: "b", count: 19) + "\n"
    let hidden = renderer.renderDocument(source).hiddenLength
    let length = (source as NSString).length
    expect(hidden == 20, "frontmatter: rendering reports the hidden length")
    expect(MarkdownRenderer.renderedFraction(0.75, hiddenLength: hidden, sourceLength: length) == 0.5, "frontmatter: reading fraction shifts past the hidden block")
    expect(MarkdownRenderer.renderedFraction(0.25, hiddenLength: hidden, sourceLength: length) == 0, "frontmatter: a position inside the metadata opens at the top")
    expect(MarkdownRenderer.renderedFraction(0.3, hiddenLength: 0, sourceLength: 15) == 0.3, "frontmatter: fraction unchanged without a block")
    expect(renderer.renderDocument("---\nk: v\n---\n").hiddenLength == 0, "frontmatter: nothing hidden when the block is shown as a listing")
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
    let source = "---\nname: my-skill\ndescription: Does a thing\n---\n"
    let s = render(source)
    let at = offset(of: "name: my-skill", in: s)
    expect(at != NSNotFound, "frontmatter-only: the block is shown instead of a blank page")
    expect(at != NSNotFound && isMono(font(s, at: at)), "frontmatter-only: shown as a code listing")
    expect(at != NSNotFound && s.attribute(EditorTheme.codeBlockMarker, at: at, effectiveRange: nil) != nil, "frontmatter-only: listing gets the code block background")
    expect(render("---\nk: v\n---\n\n  \n").string.contains("k: v"), "frontmatter-only: trailing blank lines still count as empty")
    expect(render("---\nk: ```\n---\n").string.contains("k: ```"), "frontmatter-only: backticks inside the block survive the listing fence")
}

do {
    let s = render("intro\n\n---\n\ntitle: Hello\n\n---\n\nbody\n")
    expect(s.string.contains("title: Hello") && hasAttachment(s), "frontmatter: `---` not on line 1 is a thematic break")
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
